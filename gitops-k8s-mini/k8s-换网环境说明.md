# 单机 Kubernetes 换网/换场地 环境说明

> 主机：k8s-master（Ubuntu 24.04.5，4C/14G，ens18 走 DHCP）
> 版本：kubeadm/kubelet v1.36.2，containerd 2.4.2，Calico v3.29.4
> 形态：单机同时承担 control-plane 与 worker（master + node）

## 一、核心思路

集群的身份不再绑定 DHCP 地址，而是绑定一个**永远不变的虚拟地址** `10.10.10.10/32`（由 dummy0 网卡承载）。
局域网 IP 怎么变都不影响集群内部；kubectl 入口则固定走 `https://127.0.0.1:6443`，在本机永远可用。

```
        ┌─────────────────────────────────────────────┐
        │  Ubuntu (一台机器)                          │
        │                                             │
  用户  │  kubectl ──► 127.0.0.1:6443 ─┐              │
        │                              ▼              │
        │   dummy0  10.10.10.10/32  ← apiserver       │
        │   （永不变）               ← etcd            │
        │                              ▲              │
        │   ens18   192.168.x.x (DHCP) ┘ 仅供对外通信  │
        │                              │              │
        │   节点 InternalIP = 10.10.10.10              │
        │   Calico 节点地址  = 10.10.10.10 (锁定 dummy0)│
        └─────────────────────────────────────────────┘
```

## 二、关键配置对照

| 项目 | 取值 | 说明 |
|---|---|---|
| 控制面 Endpoint | `10.10.10.10:6443` | kubeadm `controlPlaneEndpoint` |
| apiserver advertise | `10.10.10.10` | `kubernetes` Service(10.96.0.1) 指向它 |
| etcd | `10.10.10.10:2379/2380` | 证书 SAN 含 10.10.10.10、127.0.0.1 |
| kubectl 入口 | `https://127.0.0.1:6443` | `~/.kube/config` |
| 证书 SAN | `10.96.0.1, 10.10.10.10, 127.0.0.1, localhost, k8s-master` + 当前局域网 IP | 局域网 IP 由脚本动态追加 |
| kubelet | `--node-ip=10.10.10.10` | Node InternalIP 固定 |
| Calico | `IP_AUTODETECTION_METHOD=interface=dummy0` | 不会误选 ens18 |
| Pod 网段 | `10.244.0.0/16`（Calico 分配 10.244.x.0/24） | 与 kubeadm `podSubnet` 一致 |
| Service 网段 | `10.96.0.0/12` | ClusterIP 10.96.0.1 / DNS 10.96.0.10 |
| 单节点调度 | 已移除 `node-role.kubernetes.io/control-plane` 污点 | 业务 Pod 可以直接跑在本机 |
| 默认 StorageClass | `local-path`（/opt/local-path-provisioner） | PVC 可直接申请 |

## 三、日常使用

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
sudo k8s-info.sh          # 一屏看全：当前 IP / dummy0 / 节点 / Pod / 证书 SAN
```

## 四、换了路由器 / 换了场地，需要做什么

**什么都不用做。** 只要机器开机，`k8s-dummy0.service` 会先于 kubelet 建好 10.10.10.10，集群自己起来。

如果你还想用「局域网 IP:6443」从别的电脑直连（Lens、远程 kubectl）：

```bash
sudo k8s-info.sh          # 看当前局域网 IP 是否已在证书里
sudo k8s-allow-ip.sh      # 不在就执行一次，自动把当前 IP 加进 SAN
```

开机时 `k8s-ip-autoadapt.service` 也会自动做这件事，所以通常无需手动。
把 `~/.kube/config` 里的 `server` 改成 `https://<当前IP>:6443` 即可拷给其它电脑用（CA 公钥在 `/etc/kubernetes/pki/ca.crt`）。

## 五、排查手册

| 现象 | 处理 |
|---|---|
| 节点 NotReady | `systemctl status kubelet` → `journalctl -u kubelet -n 100` |
| `ip addr show dummy0` 没有地址 | `sudo systemctl restart k8s-dummy0` |
| kubectl 连不上 | `systemctl status kubelet`；`ss -lntp \| grep 6443`；`openssl s_client -connect 127.0.0.1:6443` |
| Pod 卡在 ContainerCreating | `kubectl describe pod`；`journalctl -u kubelet \| grep -i cni`；`kubectl -n kube-system logs ds/calico-node` |
| DNS 解析失败 | `kubectl -n kube-system get pods -l k8s-app=kube-dns`；`kubectl -n kube-system logs ds/calico-node \| tail -50` |
| 证书到期检查 | `sudo kubeadm certs check-expiration` |

**不要做的事**：直接改 `/etc/kubernetes/manifests/kube-apiserver.yaml` 里的 `--advertise-address`。
上一版环境就是这么坏的——把 advertise 改成 127.0.0.1 后，`kubernetes` Service 的 Endpoint 变成 127.0.0.1，
所有 Pod 都连不上 apiserver，Calico/CoreDNS 集体挂掉。
需要改地址时，改 `/root/kubeadm-config.yaml` 再用 kubeadm 重新签发证书。

## 六、备份与回滚

- 旧环境配置备份：`/root/k8s-backup-20261114-054052/`（`etc-kubernetes.tar.gz`、`others.tar.gz`）
- 本文件：`/root/k8s-README.md`
- kubeadm 配置（唯一真源）：`/root/kubeadm-config.yaml`

集群是**重建**的（旧 etcd 数据已被清空、addon 全丢，无可保留内容），回滚没有意义；
如果确实要回到旧状态，只能重新 `kubeadm init` 并把 IP 改回 192.168.31.66 网段。
