# fixed-ip-k8s：让单机 K8s 换网络/换场地后照常工作

一台 Ubuntu 同时跑 master + node，机器会在**不同路由器、不同网段、不同场地**之间搬动，IP 由 DHCP 分配、每次都可能变。
这套脚本把集群的身份从「DHCP 地址」解耦出来，绑到一块**永不变化的虚拟网卡**上，换网后无需任何人工干预。

> 与 `../../infra/ubuntu-24.04/install-k8s-single.sh` 的关系：那个脚本负责「第一次把 K8s 装上」，面向固定 IP；
> 本目录是它的**换网改造版**，用 dummy0 固定地址重建控制面。两条路二选一，不要混着跑。

## 思路

```text
        ┌──────────────────────────────────────────────┐
        │  Ubuntu（一台机器）                          │
   用户 │  kubectl ──► 127.0.0.1:6443 ─┐               │
        │                             ▼               │
        │   dummy0  10.10.10.10/32  ← apiserver        │
        │   （永不变）               ← etcd             │
        │                             ▲               │
        │   ens18   192.168.x.x(DHCP)─┘ 只用于对外通信  │
        │                                              │
        │   Node InternalIP = 10.10.10.10              │
        │   Calico 节点地址  = 10.10.10.10             │
        └──────────────────────────────────────────────┘
```

| 项目 | 取值 | 为什么 |
|---|---|---|
| 控制面 Endpoint / apiserver advertise | `10.10.10.10:6443` | 固定，跟着 dummy0 走 |
| kubectl 入口 | `https://127.0.0.1:6443` | 本机永远连得上，apiserver bind 0.0.0.0，两个地址都通 |
| kubelet `--node-ip` | `10.10.10.10` | Node InternalIP 不再漂移 |
| Calico | `IP_AUTODETECTION_METHOD=interface=dummy0` | 否则会误选 ens18 的 DHCP 地址 |
| 证书 SAN | `10.96.0.1, 10.10.10.10, 127.0.0.1, localhost, k8s-master` + 当前局域网 IP | 局域网 IP 由 `k8s-allow-ip.sh` 追加 |
| 单节点调度 | 去掉 `control-plane:NoSchedule` 污点 | master 也要跑业务 Pod |

**为什么不能把 advertise 也写成 127.0.0.1**：那样 `kubernetes` Service（10.96.0.1）的 Endpoint 会变成 127.0.0.1，
Pod 在自己网络命名空间里连不上它，Calico 申请容器沙箱时会超时，随后 CoreDNS 一起挂。
2026-11-14 那次故障就是这么来的。

## 目录

```text
fixed-ip-k8s/
├── setup/                     # 建集群，按序号执行（03/04 是一次性的，其余幂等）
│   ├── 01-dummy0.sh           # 装 dummy0 与 systemd 单元，固定 10.10.10.10/32
│   ├── 02-backup-reset.sh     # 备份 /etc/kubernetes 等，kubeadm reset 并清残留
│   ├── 03-kernel-init.sh      # swap/sysctl + kubeadm init（读 config/kubeadm-config.yaml）
│   ├── 04-kubeconfig-cni.sh   # kubectl 入口 127.0.0.1 + 去污点 + 装 Calico（锁 dummy0）
│   ├── 05-storage.sh          # local-path 设为默认 StorageClass + PVC 验证
│   ├── 06-verify.sh           # 端到端验证：DNS / ClusterIP / apiserver / 外网
│   └── 07-ops-tools.sh        # 装 /usr/local/bin 运维脚本 + 开机自适应单元
├── config/
│   ├── kubeadm-config.yaml    # 唯一真源（Endpoint、certSANs、node-ip 都在这里）
│   ├── k8s-dummy0.service     # dummy0 单元（Before=kubelet.service）
│   ├── k8s-dummy.conf         # 开机加载 dummy 模块
│   └── k8s-ip-autoadapt.service  # 开机把当前局域网 IP 加进证书 SAN
├── manifests/                 # 离线清单：不联网也能装
│   ├── calico.yaml            # Calico v3.29.4（镜像已换成 docker.m.daocloud.io）
│   └── local-path-storage.yaml
├── ops/                       # 装到 /usr/local/bin，日常用
│   ├── k8s-info.sh            # 一屏看当前 IP / dummy0 / 节点 / Pod / 证书 SAN
│   └── k8s-allow-ip.sh        # 把指定或当前 IP 加进 apiserver 证书 SAN
└── tools/
    └── ssh-run.py             # Windows 开发机上用的 SSH 传输工具（paramiko，免 sshpass）
```

## 用法

整个目录自带清单，**不联网也能重建**（镜像仍需本机 containerd 里已有，或能拉到加速地址）。
传到服务器后按顺序执行（`SUDO_PASS` 不传则走交互式 sudo，脚本里不存密码）：

```bash
scp -r fixed-ip-k8s k8s@<服务器>:~/
ssh k8s@<服务器>
cd ~/fixed-ip-k8s
bash setup/01-dummy0.sh
bash setup/02-backup-reset.sh        # 会清空旧集群，有备份到 /root/k8s-backup-<时间戳>/
bash setup/03-kernel-init.sh
bash setup/04-kubeconfig-cni.sh      # 默认读 manifests/calico.yaml
bash setup/05-storage.sh             # 默认读 manifests/local-path-storage.yaml
bash setup/06-verify.sh
bash setup/07-ops-tools.sh
```

无人值守时可以 `SUDO_PASS=xxx bash setup/01-dummy0.sh`。

## 换路由器 / 换场地之后

**什么都不用做。** 开机时 `k8s-dummy0.service` 先于 kubelet 建好 10.10.10.10，集群自己起来；
`k8s-ip-autoadapt.service` 会把新的局域网 IP 加进证书 SAN。

```bash
sudo k8s-info.sh          # 看当前 IP、dummy0、节点、Pod、证书里有哪些 IP
sudo k8s-allow-ip.sh      # 想把当前 IP 加进证书（开机已自动做，手动跑也幂等）
```

只想本机 kubectl，完全不用管证书。想让局域网另一台电脑直连：
把 `~/.kube/config` 里的 `server` 改成 `https://<当前IP>:6443` 拷过去即可（CA 在 `/etc/kubernetes/pki/ca.crt`）。

## 改固定地址

`10.10.10.10` 出现在三处，要改就一起改，然后按 02→03 重建：

1. `config/k8s-dummy0.service` 的 `ip addr add`
2. `config/kubeadm-config.yaml` 的 `advertiseAddress`、`controlPlaneEndpoint`、`certSANs`、`node-ip`
3. `setup/04-kubeconfig-cni.sh` 里 `sed` 替换的 `server: https://10.10.10.10:6443`
4. `ops/k8s-info.sh`、`ops/k8s-allow-ip.sh` 里的提示文案（仅展示用）

## 离线备份

本目录就是一套完整的离线备份，内容包括：建集群的全部脚本、kubeadm 配置、systemd 单元、运维脚本、Calico 与
local-path 清单。同目录下的 `fixed-ip-k8s-offline-<日期>.tar.gz` 是打包好的单个文件，直接拷到 U 盘/网盘即可。

恢复方式：解包 → `scp -r` 到目标机器 → 按上面顺序 `bash setup/*.sh`。

```bash
# 需要重新打包时
tar czf fixed-ip-k8s-offline-$(date +%Y%m%d).tar.gz fixed-ip-k8s
```

机器上另有两份运行时备份（**不在本目录**，只在该服务器上）：

| 路径 | 内容 |
|---|---|
| `/root/k8s-backup-<时间戳>/` | 重建前的 `/etc/kubernetes`、`/etc/cni`、`/var/lib/kubelet`、`/root/.kube` |
| `/root/kubeadm-config.yaml` | 当前生效的 kubeadm 配置（`k8s-allow-ip.sh` 会往里追加 certSANs） |
| `/root/k8s-README.md` | 环境说明 |

## 排障

| 现象 | 处理 |
|---|---|
| 节点 NotReady | `systemctl status kubelet` → `journalctl -u kubelet -n 100` |
| `ip addr show dummy0` 没地址 | `sudo systemctl restart k8s-dummy0` |
| kubectl 连不上 | `ss -lntp \| grep 6443`；`openssl s_client -connect 127.0.0.1:6443` |
| Pod 卡 ContainerCreating | `kubectl -n kube-system logs ds/calico-node \| tail -50` |
| 证书到期 | `sudo kubeadm certs check-expiration` |
| 重签证书没生效 | v1.36 的 `kubeadm certs renew apiserver` 只提示「Using existing certificate」，`k8s-allow-ip.sh` 已用「移走旧证书 + `kubeadm init phase certs apiserver`」兜底 |

**不要直接改** `/etc/kubernetes/manifests/kube-apiserver.yaml` 的 `--advertise-address`，
改 `/root/kubeadm-config.yaml` 后重签证书才是可持续的做法。

## 本仓库这套环境的实际值

2026-11-14 在 `k8s@192.168.1.102`（Ubuntu 24.04.5、4C/14G、ens18 DHCP）上执行过全套：
kubeadm/kubelet v1.36.2、containerd 2.4.2、Calico v3.29.4、podSubnet `10.244.0.0/16`。
细节见 `../k8s-换网环境说明.md`，机器上同一份在 `/root/k8s-README.md`。
