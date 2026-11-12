# Kubernetes 单机安装（Ubuntu 24.04，kubeadm，master + node 同一台服务器）

用 kubeadm 在**一台** Ubuntu 24.04 服务器上搭建 Kubernetes v1.36.2，这台服务器既是 master（控制平面），也是 node（运行业务 Pod）。容器运行时 containerd，网络插件 Calico，默认存储 local-path。装好后用本仓库的 `k8s/` 部署 yudao 依赖环境。

> 适合开发、测试或资源有限的场景，没有高可用：服务器宕机整个集群就不可用。
> 有两台及以上服务器时看 [k8s-cluster.md](k8s-cluster.md)；单机装好后也可以按那篇第五节再加入 node。
> Windows 本地开发直接用 Docker Desktop 自带的单节点 Kubernetes 即可，不需要看本文，见根目录 `README.md`。
> 参考教程：[Ubuntu 24.04 部署 K8s 1.36.2，单 Master 单 Node](https://www.cnzhuji.com/article/57_191047.html)。

## 0. 环境信息

| 项目 | 取值 |
|---|---|
| 操作系统 | Ubuntu 24.04 LTS（noble），可以是最小化安装 |
| K8s 版本 | v1.36.2（kubeadm、kubelet、kubectl 版本一致） |
| 容器运行时 | containerd（`containerd.io`，来自 Docker 软件源） |
| 网络插件 | Calico v3.29.4 |
| 默认存储 | local-path-provisioner v0.0.32，数据在 `/opt/local-path-provisioner` |
| Pod 网段 | `192.168.0.0/16`；服务器 IP 是 `192.168.x.x` 时自动改用 `10.244.0.0/16` |
| Service 网段 | `10.96.0.0/12`（kubeadm 默认） |
| 配置 | 最低 4C8G、100G 磁盘；yudao 中间件全开建议 8C16G 以上 |
| 操作账号 | 有 sudo 权限的普通账号（不直接用 root） |

本文与同目录的两个文件配套：

| 文件 | 说明 |
|---|---|
| `k8s-install.env` | 安装变量：国内 / 海外、主机名、IP、Pod 网段、各软件源和镜像地址、版本号 |
| `install-k8s-single.sh` | 一键安装脚本，步骤与本文第一 ~ 六节一一对应（每节标题后的 `步骤 xxx`），每步带校验，失败即停 |

两种用法任选其一：

- **脚本安装**：见下面“快速安装”，一条命令跑完第一 ~ 六节。
- **手动安装**：从第一节开始，**从上往下依次复制执行**。每个代码块开头都有 `source ~/k8s-install.env`，SSH 断开重连后接着执行即可；国内专用的步骤用 `if [ "$REGION" = cn ]` 自动判断，不需要手动挑选。

约定：

- 全文用普通账号执行，需要 root 权限的命令都已加 `sudo`；写系统文件用 `sudo tee`。不要 `sudo -i` 切到 root 后再执行，否则 `$HOME` 会变成 root 的，kubectl 凭证会放错位置。
- `kubectl` 不加 sudo：它读取的是当前账号的 `~/.kube/config`。
- 和集群版的区别：hosts 只写本机；不需要 `kubeadm join`；初始化后要**去掉 control-plane 污点**，否则业务 Pod 调度不上来。

## 快速安装（脚本）

把 `k8s-install.env`、`install-k8s-single.sh` 放到服务器上（服务器能访问仓库时直接 `git clone`；最小化系统没有 git 时先 `sudo apt update && sudo apt install -y git`，或在开发机上 `scp` 这两个文件过去）：

```bash
# 开发机上执行：改成服务器的登录账号和 IP
scp infra/ubuntu-24.04/k8s-install.env infra/ubuntu-24.04/install-k8s-single.sh k8s@10.0.0.10:~/
```

服务器上执行：

```bash
vim ~/k8s-install.env          # 确认 REGION（cn / global）；多网卡时把 NODE_IP 改成固定值
bash ~/install-k8s-single.sh   # 按顺序执行全部步骤
```

- 中途失败：按报错处理后，用 `bash ~/install-k8s-single.sh --from <步骤名>` 从失败的步骤继续；已完成的步骤也可以重复执行。
- 只执行某几步：`bash ~/install-k8s-single.sh calico verify`；查看全部步骤：`--list`。
- `raw.githubusercontent.com` 下载不了时，在能访问 GitHub 的机器上下载 `calico.yaml`、`local-path-storage.yaml`（地址见第四节第 4 步、第六节）放到服务器的 `~/`，脚本会直接使用。

脚本跑完后看第七节部署 yudao-env。

## 一、系统前置配置

### 0. 创建安装变量文件

后面每个代码块都会先 `source ~/k8s-install.env`。内容与仓库中的 `k8s-install.env` 相同，已经有这个文件时跳过本步。

```bash
cat > ~/k8s-install.env <<'EOF'
# 服务器位置：cn = 国内（阿里云源 + Docker Hub 国内加速），global = 海外（官方源）
REGION=cn

# 版本
K8S_VER=1.36.2
K8S_MINOR=v${K8S_VER%.*}
CALICO_VER=v3.29.4
LOCAL_PATH_VER=v0.0.32

# 节点：主机名、IP（默认取本机第一个地址；多网卡取错时改成固定值，如 NODE_IP=192.168.1.100）
NODE_NAME=k8s-master
NODE_IP=$(hostname -I | awk '{print $1}')

# Pod 网段：服务器 IP 是 192.168.x.x 时改用 10.244.0.0/16，避免与内网冲突
if [[ $NODE_IP == 192.168.* ]]; then POD_CIDR=10.244.0.0/16; else POD_CIDR=192.168.0.0/16; fi

if [ "$REGION" = cn ]; then
  DOCKER_MIRROR=https://mirrors.aliyun.com/docker-ce                      # containerd.io 软件源
  K8S_MIRROR=https://mirrors.aliyun.com/kubernetes-new/core/stable        # kubeadm/kubelet/kubectl 软件源
  IMAGE_REPO=registry.aliyuncs.com/google_containers                      # 控制平面镜像、pause 镜像
  # Docker Hub 国内加速（2026-11-12 实测可用，第三方公益服务可能失效；按顺序尝试，第一个用于清单中的镜像地址）
  DOCKER_HUB_MIRRORS="docker.m.daocloud.io docker.1ms.run docker.1panel.live docker.xuanyuan.me"
else
  DOCKER_MIRROR=https://download.docker.com
  K8S_MIRROR=https://pkgs.k8s.io/core:/stable:
  IMAGE_REPO=registry.k8s.io
  DOCKER_HUB_MIRRORS="docker.io"
fi
DOCKER_HUB_MIRROR=${DOCKER_HUB_MIRRORS%% *}
EOF
```

海外服务器把 `REGION=cn` 改成 `REGION=global`；多网卡时把 `NODE_IP` 改成固定值：

```bash
vim ~/k8s-install.env
```

校验：

```bash
source ~/k8s-install.env
echo "REGION=$REGION NODE_NAME=$NODE_NAME NODE_IP=$NODE_IP POD_CIDR=$POD_CIDR"
echo "IMAGE_REPO=$IMAGE_REPO DOCKER_HUB_MIRROR=$DOCKER_HUB_MIRROR"
```

成功标准：各项都不为空；`NODE_IP` 是本机内网 IP（不是 `172.17.0.1` 这类容器网卡地址，可以用 `ip -4 addr` 对照）。

Docker Hub 加速地址都是第三方公益服务。某个地址失效时，在 `DOCKER_HUB_MIRRORS` 中删掉或调整顺序。检查地址是否可用：

```bash
curl -s -o /dev/null -w "%{http_code}\n" --max-time 8 https://docker.m.daocloud.io/v2/
```

返回 `200` 或 `401` 说明服务在线（`401` 是正常的鉴权提示）；超时、`429`（限流）、`5xx` 说明不可用。

### 1. 更新软件源与系统（步骤 `apt`）

国内服务器把 Ubuntu 源换成阿里云（Ubuntu 24.04 的源配置在 `/etc/apt/sources.list.d/ubuntu.sources`），然后更新系统：

```bash
source ~/k8s-install.env
if [ "$REGION" = cn ]; then
  [ -f /etc/apt/sources.list.d/ubuntu.sources.bak ] || sudo cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
  sudo sed -i 's#http://\(archive\|security\).ubuntu.com#https://mirrors.aliyun.com#g' /etc/apt/sources.list.d/ubuntu.sources
fi
sudo apt update && sudo apt upgrade -y
```

成功标准：`apt update` 无报错。

### 2. 安装基础工具（步骤 `tools`）

按最小化安装的 Ubuntu 考虑，后续步骤用到的工具在这里一次装好：

```bash
sudo apt install -y \
  ca-certificates curl gnupg apt-transport-https \
  chrony ufw iputils-ping iproute2 \
  conntrack socat ethtool ebtables iptables \
  vim git openssh-client
```

| 工具 | 用途 |
|---|---|
| `ca-certificates`、`curl`、`gnupg`、`apt-transport-https` | 下载 GPG 密钥、添加软件源、下载 `calico.yaml` 等清单 |
| `chrony` | 时间同步 |
| `ufw` | 防火墙（本地部署保持关闭，装上便于确认状态） |
| `iputils-ping`、`iproute2` | `ping` 校验 hosts，`ip` 查本机 IP |
| `conntrack`、`socat`、`ethtool`、`ebtables`、`iptables` | kubelet / kube-proxy 运行依赖，kubeadm 预检会检查 |
| `vim` | 修改配置文件 |
| `git`、`openssh-client` | 拉取本仓库、`scp` 复制凭证 |

`crictl`（`cri-tools`）在 K8s 软件源里，第三节与 kubeadm 一起安装；`ctr` 随 `containerd.io` 安装。

校验：

```bash
for c in curl gpg chronyc ufw ping ip conntrack socat iptables vim git scp; do
  command -v $c > /dev/null && echo "OK  $c" || echo "缺少 $c"
done
```

成功标准：全部输出 `OK`，没有 `缺少`。

### 3. 关闭 Swap（步骤 `swap`）

```bash
sudo swapoff -a
sudo sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab
cat /proc/swaps
```

成功标准：`/proc/swaps` 只有表头，没有 swap 挂载行。

### 4. 加载内核模块、开启 IP 转发（步骤 `kernel`）

```bash
printf 'overlay\nbr_netfilter\n' | sudo tee /etc/modules-load.d/k8s.conf > /dev/null
sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/k8s.conf > /dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system > /dev/null

sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
```

成功标准：三个参数都为 `1`。

### 5. 主机名与 hosts 解析（步骤 `hosts`）

```bash
source ~/k8s-install.env
sudo hostnamectl set-hostname $NODE_NAME
# 先删除旧的同名映射再追加，重复执行不会产生多行
sudo sed -i "/[[:space:]]$NODE_NAME\$/d" /etc/hosts
echo "$NODE_IP $NODE_NAME" | sudo tee -a /etc/hosts > /dev/null

hostname
getent hosts $NODE_NAME
```

成功标准：`hostname` 输出 `k8s-master`；`getent hosts` 解析到 `$NODE_IP`（不是 `127.0.1.1`）。

### 6. 时间同步与防火墙（步骤 `time`）

```bash
sudo systemctl enable --now chrony
# 本地部署不启用防火墙
sudo ufw disable

chronyc tracking | grep -E 'Reference|System time'
sudo ufw status
```

成功标准：chrony 有参考时钟、偏差在毫秒级；ufw 为 `Status: inactive`。

本地部署不开防火墙，服务器**只能放在内网**。要暴露到公网时，用云厂商安全组只放行必要端口（SSH、6443、需要访问的 yudao 服务端口），并限制来源 IP。

## 二、安装 containerd（步骤 `containerd`）

### 1. 添加 Docker 软件源并安装 containerd.io

`containerd.io` 在 Docker 的软件源中（只装 containerd，不需要 docker-ce）：

```bash
source ~/k8s-install.env
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL $DOCKER_MIRROR/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
$DOCKER_MIRROR/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y containerd.io
containerd --version
```

成功标准：输出 containerd 版本号。

### 2. 配置 containerd

生成默认配置、cgroup 驱动改为 systemd（与 kubelet 一致）。已经配置过（`SystemdCgroup = true`）时不重新生成，避免覆盖已有修改：

```bash
sudo mkdir -p /etc/containerd
if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml 2> /dev/null; then
  containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
fi
grep -n SystemdCgroup /etc/containerd/config.toml
```

成功标准：输出 `SystemdCgroup = true`。没有这一行时（部分 containerd 2.x 的默认配置不带），用 `sudo vi /etc/containerd/config.toml` 在 runc 的 `options` 段手动加上 `SystemdCgroup = true`。

国内服务器还要做两件事（`REGION=global` 时自动跳过）：

- **pause 镜像换成阿里云**：`kubeadm init --image-repository` 只影响控制平面镜像，containerd 的 pause 镜像要单独改，否则 init 会卡在拉取 `registry.k8s.io/pause`。
- **Docker Hub 国内加速**：Calico、nginx、busybox 以及 yudao 各服务（mysql、redis 等）的镜像都在 Docker Hub。配置后所有 `docker.io/...` 和不带仓库前缀的镜像（如 `mysql:8.0.21`）都依次尝试 `DOCKER_HUB_MIRRORS` 中的地址，**不回落到 Docker 官方地址**。

```bash
source ~/k8s-install.env
if [ "$REGION" = cn ]; then
  sudo sed -i "s#registry.k8s.io/pause#$IMAGE_REPO/pause#" /etc/containerd/config.toml
  # 让 containerd 读取 /etc/containerd/certs.d 下的镜像仓库配置（默认配置中有两处 config_path = ''，都改）
  sudo sed -i "s#config_path = ''#config_path = '/etc/containerd/certs.d'#" /etc/containerd/config.toml
  sudo mkdir -p /etc/containerd/certs.d/docker.io
  {
    echo "server = \"https://$DOCKER_HUB_MIRROR\""
    for m in $DOCKER_HUB_MIRRORS; do
      printf '\n[host."https://%s"]\n  capabilities = ["pull", "resolve"]\n' "$m"
    done
  } | sudo tee /etc/containerd/certs.d/docker.io/hosts.toml > /dev/null
  grep -nE "pause|config_path" /etc/containerd/config.toml
  cat /etc/containerd/certs.d/docker.io/hosts.toml
fi
```

成功标准（国内）：pause 镜像为 `registry.aliyuncs.com/google_containers/pause:x.x`；两处 `config_path` 都是 `'/etc/containerd/certs.d'`（`plugin_config_path` 那行不用管）；`hosts.toml` 的 `server` 和每个 `[host."https://..."]` 是 `DOCKER_HUB_MIRRORS` 中的地址。

重启生效：

```bash
sudo systemctl enable containerd
sudo systemctl restart containerd
systemctl is-active containerd
```

成功标准：输出 `active`。

## 三、安装 kubeadm、kubelet、kubectl

### 1. 添加 K8s 软件源并安装（步骤 `kube`）

```bash
source ~/k8s-install.env
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL $K8S_MIRROR/$K8S_MINOR/deb/Release.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] $K8S_MIRROR/$K8S_MINOR/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
sudo apt update

apt-cache madison kubeadm | head -3        # 确认源里有 $K8S_VER
# cri-tools 提供 crictl（排查容器用），新版 kubeadm 不再自动安装
sudo apt install -y --allow-change-held-packages kubeadm=${K8S_VER}-* kubelet=${K8S_VER}-* kubectl=${K8S_VER}-* cri-tools
# 锁定版本，防止 apt upgrade 时意外升级
sudo apt-mark hold kubelet kubeadm kubectl cri-tools containerd.io
sudo systemctl enable --now kubelet
# crictl 默认连接 containerd，之后不用每次带 --runtime-endpoint
sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock

kubeadm version -o short
apt-mark showhold
```

此时 kubelet 会每隔几秒重启一次（等待 `kubeadm init` 下发配置），属于正常现象。

成功标准：kubeadm 版本为 `v1.36.2`；锁定列表包含 `containerd.io`、`cri-tools`、`kubeadm`、`kubectl`、`kubelet`。

### 2. 验证镜像拉取（步骤 `pull`）

```bash
source ~/k8s-install.env
sudo crictl pull $DOCKER_HUB_MIRROR/library/busybox:1.36
```

成功标准：输出 `Image is up to date for ...`。失败时检查第二节第 2 步的 `hosts.toml`，换成可用的加速地址后 `sudo systemctl restart containerd` 再试。

## 四、初始化集群

### 1. 拉取镜像并初始化（步骤 `init`）

```bash
source ~/k8s-install.env
sudo kubeadm config images pull --kubernetes-version=v$K8S_VER --image-repository=$IMAGE_REPO

sudo kubeadm init \
  --apiserver-advertise-address=$NODE_IP \
  --kubernetes-version=v$K8S_VER \
  --pod-network-cidr=$POD_CIDR \
  --image-repository=$IMAGE_REPO | tee ~/kubeadm-init.log
```

成功标准：`images pull` 每个镜像都输出 `[config/images] Pulled ...`；init 输出 `Your Kubernetes control-plane has initialized successfully!`。末尾的 `kubeadm join` 命令单机用不到，以后要加 node 时可以用 `sudo kubeadm token create --print-join-command` 重新生成。

- `images pull` 报 `not found`：镜像源还没同步该补丁版本，把 `K8S_VER` 换成已有的 1.36.x，回到第三节重新安装同一版本。
- init 失败：按附录排查，重试前先清理上一次的残留：

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d $HOME/.kube
```

### 2. 配置 kubectl（步骤 `kubeconfig`）

把管理员凭证复制到当前账号目录，之后 kubectl 不需要 sudo：

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl get nodes
kubectl get pods -n kube-system
```

成功标准：`k8s-master` 为 `NotReady`（还没装网络插件，正常）；`etcd`、`kube-apiserver`、`kube-controller-manager`、`kube-scheduler`、`kube-proxy` 为 `Running`，`coredns` 为 `Pending`（等网络插件）。

`admin.conf` / `~/.kube/config` 是集群最高权限凭证，不要提交到仓库或发到聊天工具里。

### 3. 去掉 control-plane 污点（步骤 `taint`，单机关键步骤）

kubeadm 默认给 master 打上 `node-role.kubernetes.io/control-plane:NoSchedule` 污点，业务 Pod 不会调度到 master。单机没有其他 node，必须去掉；同时打上 worker 角色标签：

```bash
source ~/k8s-install.env
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl label node $NODE_NAME node-role.kubernetes.io/worker= --overwrite

kubectl describe node $NODE_NAME | grep -A2 Taints
```

成功标准：`Taints` 只剩 `node.kubernetes.io/not-ready:NoSchedule`（装完网络插件后会自动消失）或 `<none>`，没有 `control-plane`。

### 4. 部署 Calico 网络插件（步骤 `calico`）

先下载清单、写入 Pod 网段、换成加速地址并试拉，确认没问题再 apply。`raw.githubusercontent.com` 下载不了时，在能访问 GitHub 的机器上下载 `https://raw.githubusercontent.com/projectcalico/calico/v3.29.4/manifests/calico.yaml`，`scp` 到服务器的 `~/calico.yaml`，下面的 `curl` 会跳过。

```bash
source ~/k8s-install.env
cd ~
[ -s calico.yaml ] || curl -fsSLo calico.yaml https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VER/manifests/calico.yaml

# Pod 网段写入清单：与 kubeadm init 的 --pod-network-cidr 一致，不依赖 Calico 自动识别
sed -i -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' \
       -e "s|#   value: \"192.168.0.0/16\"|  value: \"$POD_CIDR\"|" calico.yaml
# 镜像换成 Docker Hub 加速地址
sed -i "s#docker.io/#$DOCKER_HUB_MIRROR/#g" calico.yaml

grep -n -A1 -- "- name: CALICO_IPV4POOL_CIDR" calico.yaml
grep "image:" calico.yaml | sort -u
sudo crictl pull $DOCKER_HUB_MIRROR/calico/node:$CALICO_VER
```

成功标准：`CALICO_IPV4POOL_CIDR` 两行前面没有 `#`，值与 `$POD_CIDR` 一致；`image:` 都是 `$DOCKER_HUB_MIRROR/calico/...`（国内为 `docker.m.daocloud.io/calico/...`）；`crictl pull` 输出 `Image is up to date for ...`。

部署并等待就绪：

```bash
source ~/k8s-install.env
kubectl apply -f ~/calico.yaml
kubectl -n kube-system rollout status daemonset/calico-node --timeout=300s
kubectl -n kube-system rollout status deployment/calico-kube-controllers --timeout=300s
kubectl -n kube-system rollout status deployment/coredns --timeout=300s
kubectl wait --for=condition=Ready node/$NODE_NAME --timeout=120s
kubectl get pods -n kube-system
```

成功标准：三个 `rollout status` 都输出 `successfully rolled out`；节点 `condition met`；`kube-system` 下所有 Pod `Running`。

第一次部署要拉镜像，`calico-node` 停在 `Init:0/3` 一两分钟属于正常；calico-node 就绪后 `calico-kube-controllers`、`coredns` 才开始创建。超时的话，用 `kubectl describe pod -n kube-system -l k8s-app=calico-node | tail -15` 查看是否拉镜像失败。

- 服务器有多块网卡时，Calico 可能选错网卡，在 `calico-node` 的环境变量中加 `IP_AUTODETECTION_METHOD=interface=eth0`（换成内网的网卡名）。
- 升级 Calico 前到 <https://github.com/projectcalico/calico/releases> 确认与当前 K8s 版本兼容。

## 五、最终验证（步骤 `verify`）

验证调度、NodePort 和集群 DNS，最后清理测试资源：

```bash
source ~/k8s-install.env
kubectl create deployment test-nginx --image=$DOCKER_HUB_MIRROR/library/nginx --replicas=2
kubectl expose deployment test-nginx --port=80 --type=NodePort
kubectl rollout status deployment/test-nginx --timeout=180s
kubectl get pods -o wide -l app=test-nginx
curl -s http://$NODE_IP:$(kubectl get svc test-nginx -o jsonpath='{.spec.ports[0].nodePort}') | grep title

# DNS：不用 -it（第一次要拉镜像，交互模式像卡住一样，Ctrl+C 后 Pod 会残留）；
# 查完整域名（busybox 新版 nslookup 不使用 search 域，查短名 kubernetes.default 会报 NXDOMAIN）
kubectl run dns-test --image=$DOCKER_HUB_MIRROR/library/busybox:1.36 --restart=Never -- nslookup kubernetes.default.svc.cluster.local
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/dns-test --timeout=120s
kubectl logs dns-test

# 清理
kubectl delete pod dns-test
kubectl delete deployment,service test-nginx
```

成功标准：`rollout status` 输出 `successfully rolled out`，两个 nginx Pod 调度到 `k8s-master`（一直 `Pending` 说明污点没去掉，回到第四节第 3 步）；`curl` 输出 `<title>Welcome to nginx!</title>`；`kubectl logs dns-test` 输出 `Name: kubernetes.default.svc.cluster.local` 和 `Address: 10.96.0.1`。

重复执行前如果提示 `AlreadyExists`，先执行最后的清理命令。

## 六、默认 StorageClass（步骤 `storage`）

本仓库的清单用 PVC 存数据，并依赖**默认 StorageClass**（Docker Desktop 自带，kubeadm 集群没有）。单机用 local-path-provisioner，数据存在本机 `/opt/local-path-provisioner`。下载不了时同 Calico，把 `https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.32/deploy/local-path-storage.yaml` 放到服务器的 `~/`。

```bash
source ~/k8s-install.env
cd ~
[ -s local-path-storage.yaml ] || curl -fsSLO https://raw.githubusercontent.com/rancher/local-path-provisioner/$LOCAL_PATH_VER/deploy/local-path-storage.yaml
# 镜像（provisioner、辅助 Pod 用的 busybox）换成 Docker Hub 加速地址
sed -i -e "s#image: rancher/#image: $DOCKER_HUB_MIRROR/rancher/#" \
       -e "s#image: busybox#image: $DOCKER_HUB_MIRROR/library/busybox#" local-path-storage.yaml
grep -n "image:" local-path-storage.yaml

kubectl apply -f local-path-storage.yaml
kubectl -n local-path-storage rollout status deployment/local-path-provisioner --timeout=180s
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass
```

成功标准：两处 `image:` 都以 `$DOCKER_HUB_MIRROR/` 开头；`rollout status` 输出 `successfully rolled out`；`local-path` 后面带 `(default)`。

验证能创建存储卷。`VOLUMEBINDINGMODE` 是 `WaitForFirstConsumer`，PVC 要等有 Pod 使用时才会真正创建，所以用一个 Pod 来测（`EOF` 不加引号，`$DOCKER_HUB_MIRROR` 会被替换成实际地址）：

```bash
source ~/k8s-install.env
cat > ~/test-pvc.yaml <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pvc-pod
spec:
  containers:
    - name: busybox
      image: $DOCKER_HUB_MIRROR/library/busybox:1.36
      command: ["sh", "-c", "echo ok > /data/test && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: test-pvc
EOF
kubectl apply -f ~/test-pvc.yaml
kubectl wait --for=condition=Ready pod/test-pvc-pod --timeout=180s
kubectl get pvc test-pvc
sudo ls /opt/local-path-provisioner/

# 清理（删除 PVC 后，local-path 会自动删除对应目录）
kubectl delete -f ~/test-pvc.yaml
rm ~/test-pvc.yaml
```

成功标准：`wait` 输出 `condition met`；PVC 的 `STATUS` 为 `Bound`；`/opt/local-path-provisioner/` 下能看到 `pvc-xxxx_default_test-pvc` 目录。PVC 一直 `Pending` 时，`kubectl describe pvc test-pvc` 查看事件，检查 `local-path` 是否为 `(default)`、`local-path-provisioner` Pod 是否 `Running`。

有数据盘时，可以把数据目录改到数据盘：编辑 `local-path-storage` 命名空间中的 ConfigMap `local-path-config`，把 `paths` 改成如 `["/data/local-path-provisioner"]`（`kubectl -n local-path-storage edit configmap local-path-config`），只影响之后新建的 PVC。

## 七、部署 yudao-env 到该集群

### 1. 在开发机上访问集群

把服务器上当前账号的 `~/.kube/config` 复制到开发机，**合并时改一个好认的上下文名**，避免和其他集群混淆：

```bash
# 开发机（WSL / Linux）：改成服务器的登录账号和 IP
SERVER_USER=k8s
SERVER_IP=10.0.0.10
echo "$SERVER_USER@$SERVER_IP"

scp $SERVER_USER@$SERVER_IP:.kube/config ~/.kube/yudao-k8s.conf
KUBECONFIG=~/.kube/yudao-k8s.conf kubectl config rename-context kubernetes-admin@kubernetes yudao-k8s
KUBECONFIG=~/.kube/config:~/.kube/yudao-k8s.conf kubectl config view --flatten > /tmp/kubeconfig && mv /tmp/kubeconfig ~/.kube/config
chmod 600 ~/.kube/config

kubectl --context yudao-k8s get nodes
```

本仓库的脚本默认上下文是 `docker-desktop`，用这个集群时显式指定：

```bash
export K8S_CONTEXT=yudao-k8s
./k8s/yudao-k8s.sh
```

也可以直接在服务器上 clone 本仓库执行（服务器上只有这一个集群，不需要改上下文名，`export K8S_CONTEXT=kubernetes-admin@kubernetes` 即可）。

**每次操作前确认上下文**（`kubectl config current-context`）：开发机上可能同时配置了线上集群，脚本都显式带 `--context`，手动执行 kubectl 时也要带上。

### 2. 清单需要调整的地方

`k8s/services/*.yaml` 是按 Docker Desktop 写的。单机部署比多节点简单（所有 Pod 都在这台服务器上），但仍要处理：

| 问题 | 涉及清单 | 处理方式 |
|---|---|---|
| `hostPath` 写死为 `/run/desktop/mnt/host/d/...`（Docker Desktop 的 Windows 盘映射） | `mysql.yaml`、`postgres.yaml`、`rocketmq.yaml`、`seata.yaml` | 把本仓库 `config/` 复制到服务器（如 `sudo mkdir -p /opt/yudao-env && sudo chown $USER /opt/yudao-env` 后放到 `/opt/yudao-env/config`），`hostPath.path` 改成该路径；在服务器上 clone 仓库时直接指向仓库里的 `config/` |
| `hostPort` 占用服务器端口 | 所有服务 | 访问地址是**服务器 IP**，不再是 `127.0.0.1`；注意不要和服务器上其他进程（如另装的 Docker 容器）端口冲突 |
| Jenkins 挂载 `/var/run/docker.sock`、`/usr/bin/docker` | `jenkins.yaml` | 服务器只有 containerd，没有 Docker；需要按 [Docker 环境安装](docker.md) 另装 docker-ce（与 kubelet 共用 containerd 没有问题），或者不部署 Jenkins |
| PVC 依赖默认 StorageClass | 所有带 PVC 的服务 | 按第六节配置 |
| Secret `yudao-env` 由 `.env` 生成 | 所有服务 | 脚本自动同步；`.env` 中的 `ROCKETMQ_BROKER_IP`、`SEATA_IP` 改成服务器 IP |
| 资源 | 所有服务 | 控制平面自身约占 1C2G；中间件全开内存吃紧时只启动需要的服务，`kubectl top` 需要另装 metrics-server |

## 八、运维操作

### 补配 / 更换 Docker Hub 加速地址

某个加速地址失效、Pod 出现 `ImagePullBackOff` 时：

**1. 修改 `~/k8s-install.env` 中的 `DOCKER_HUB_MIRRORS`**（删掉失效的地址或调整顺序，检查方法见第一节第 0 步）：

```bash
vim ~/k8s-install.env
```

**2. 重新生成 containerd 配置并试拉**（与第二节第 2 步相同，可以重复执行；也可以直接 `bash ~/install-k8s-single.sh containerd pull`）：

```bash
source ~/k8s-install.env
sudo sed -i "s#config_path = ''#config_path = '/etc/containerd/certs.d'#" /etc/containerd/config.toml
sudo mkdir -p /etc/containerd/certs.d/docker.io
{
  echo "server = \"https://$DOCKER_HUB_MIRROR\""
  for m in $DOCKER_HUB_MIRRORS; do
    printf '\n[host."https://%s"]\n  capabilities = ["pull", "resolve"]\n' "$m"
  done
} | sudo tee /etc/containerd/certs.d/docker.io/hosts.toml > /dev/null
sudo systemctl restart containerd
sudo crictl pull $DOCKER_HUB_MIRROR/library/busybox:1.36
```

成功标准：`crictl pull` 输出 `Image is up to date for ...`。重启 containerd 不影响已经在运行的 Pod；`kubectl` 短暂连不上时等十几秒即可。

**3. 让拉取失败的 Pod 重新拉取**

镜像地址已经是加速地址的，删除 Pod 让控制器重建：

```bash
kubectl delete pod <Pod名> -n <命名空间>
```

镜像地址是旧加速地址、`docker.io/...` 或不带仓库前缀的，用 `kubectl set image` 改成新地址（Deployment 会自动滚动重建 Pod），以 nginx 为例（Deployment `test-nginx`，容器名 `nginx`）：

```bash
source ~/k8s-install.env
kubectl set image deployment/test-nginx nginx=$DOCKER_HUB_MIRROR/library/nginx
kubectl rollout status deployment/test-nginx --timeout=120s
```

成功标准：`rollout status` 输出 `successfully rolled out`。更新过程中旧 Pod 会短暂显示 `Completed` / `Terminating` 后消失，属于正常。

### 扩展为集群

以后有了新服务器，按 [k8s-cluster.md](k8s-cluster.md) 第一 ~ 三节准备新节点，再执行第五节 join。原单机节点继续做 master；如果不想让业务 Pod 继续跑在 master 上，把污点加回去：

```bash
kubectl taint nodes k8s-master node-role.kubernetes.io/control-plane=:NoSchedule
```

### 重置

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
rm -rf $HOME/.kube
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
```

之后可以从第四节重新初始化。**会清空 etcd，集群内所有资源都会丢失**；local-path 的 PVC 数据留在 `/opt/local-path-provisioner`，不需要时手动删除。

### 证书续期

kubeadm 签发的证书有效期 1 年，`kubeadm upgrade` 时会自动续期。不升级的集群要在到期前手动续期：

```bash
sudo kubeadm certs check-expiration
sudo kubeadm certs renew all
# 续期后重启控制平面组件（静态 Pod）：临时移走再移回清单
sudo mkdir -p /tmp/manifests
sudo sh -c 'mv /etc/kubernetes/manifests/*.yaml /tmp/manifests/ && sleep 20 && mv /tmp/manifests/*.yaml /etc/kubernetes/manifests/'
# 更新当前账号的 kubectl 凭证（开发机上的副本也要重新复制）
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

## 附录：排错

常用命令：

```bash
sudo journalctl -u kubelet -f                     # 查看 kubelet 日志
kubectl describe pod <pod> -n <ns>                # 查看 Pod 事件
kubectl describe node k8s-master                  # 查看节点污点、资源占用、事件
```

### 拉镜像报 `dial tcp ...:443: i/o timeout`（`registry.k8s.io` / `pkg.dev`）

原因：国内服务器访问不了 `registry.k8s.io`（实际会跳转到 Google 的 `pkg.dev`）。
解决：确认 `~/k8s-install.env` 中 `REGION=cn`；containerd 的 pause 镜像换成阿里云（第二节第 2 步）；init 已经执行过的先 `sudo kubeadm reset -f`，再重新执行第四节第 1 步。

### init 报 `wait-control-plane ... dial tcp <IP>:6443: connect: connection refused`

原因：控制平面容器没有启动。国内服务器最常见的是 containerd 的 pause 镜像仍是 `registry.k8s.io/pause`（漏了第二节第 2 步），`sudo journalctl -u kubelet --no-pager -n 50` 中能看到 `failed to pull image "registry.k8s.io/pause:x.x"`；`kubeadm --image-repository` 只影响控制平面镜像，不影响 containerd 的 pause 镜像。
解决：

```bash
sudo sed -i 's#registry.k8s.io/pause#registry.aliyuncs.com/google_containers/pause#' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d $HOME/.kube
```

然后重新执行第四节第 1 步。其他原因（如 `SystemdCgroup` 不是 `true`）用 `sudo crictl ps -a` 看 etcd、kube-apiserver 是否在反复重启，再用 `sudo crictl logs <容器ID>` 看日志。

### 业务 Pod 一直 Pending，事件提示 `untolerated taint {node-role.kubernetes.io/control-plane: }`

原因：没有去掉 control-plane 污点。
解决：执行第四节第 3 步。

### Pod Pending，事件提示 `Insufficient cpu` / `Insufficient memory`

原因：单机资源不够，控制平面和中间件抢资源。
解决：`kubectl describe node k8s-master` 查看 `Allocated resources`；停掉不用的中间件，或给服务器扩容。

### preflight 报 `[ERROR Swap]` / `[ERROR FileContent--proc-sys-net-bridge-bridge-nf-call-iptables]`

原因：swap 未关闭，或 `br_netfilter` 模块未加载。
解决：重新执行第一节第 3、4 步。

### kubectl 报 `connection to the server localhost:8080 was refused`

原因：当前账号没有 `~/.kube/config`，或者用了 `sudo kubectl`（读的是 root 的 `/root/.kube/config`）。
解决：按第四节第 2 步复制凭证，kubectl 不加 sudo。

### `apt install kubeadm=1.36.2-*` 提示找不到版本

原因：K8s 源的版本目录不对（如写成了 `v1.35`），或镜像源尚未同步该补丁版本。
解决：`cat /etc/apt/sources.list.d/kubernetes.list` 确认是 `v1.36`；`apt-cache madison kubeadm` 查看可用版本。

### 节点一直 NotReady / coredns 一直 Pending

原因：Calico 没起来（镜像拉取失败最常见），或防火墙被开启后拦截了 Pod 网络流量。
解决：`kubectl get pods -n kube-system | grep calico` 找到 Pod，`kubectl describe pod` / `kubectl logs` 看原因；`sudo ufw status` 确认防火墙为 `inactive`。

### Pod 卡在 `ImagePullBackOff`（calico、nginx、busybox 等 Docker Hub 镜像）

原因：拉不到 Docker Hub 镜像（国内最常见，直接访问官方地址时好时坏：Calico 能拉下来，nginx 却失败）。
解决：按第二节第 2 步配置 containerd 的国内加速地址，清单和命令里的镜像写成 `$DOCKER_HUB_MIRROR/...`；已配置仍失败时，用第一节第 0 步的 `curl` 命令逐个检查加速地址，删掉不可用的，`sudo systemctl restart containerd` 后让 Pod 重新拉取，完整步骤见第八节“补配 / 更换 Docker Hub 加速地址”。`kubectl describe pod <Pod名> | tail -10` 可以看到是哪个镜像拉取失败。

### DNS 测试报 `server can't find kubernetes.default: NXDOMAIN`，`kubectl wait` 一直不返回

原因：busybox 新版本的 `nslookup` 不使用 `/etc/resolv.conf` 的 search 域，短名 `kubernetes.default` 不会补全成 `kubernetes.default.svc.cluster.local`；命令失败后 Pod 为 `Failed`，等待 `Succeeded` 的 `kubectl wait` 会一直等到超时。输出第一行 `Server: 10.96.0.10` 说明 CoreDNS 本身是通的。
解决：`kubectl delete pod dns-test` 后改查完整域名 `kubernetes.default.svc.cluster.local`（第五节已是这种写法）。

### Pod 拿到的 IP 不在 Pod 网段内，或与内网 IP 冲突

原因：`calico.yaml` 中 `CALICO_IPV4POOL_CIDR` 没有改，或与 `kubeadm init` 的 `--pod-network-cidr` 不一致。
解决：`kubectl get ippools -o wide` 查看 Calico 实际使用的网段；不一致时重置集群，按文档重新 init 并在 apply 前改好 `calico.yaml`。

### Pod 一直 Pending，提示 `unbound immediate PersistentVolumeClaims`

原因：集群没有默认 StorageClass。
解决：按第六节安装 local-path-provisioner 并设为默认。

### MySQL / PostgreSQL Pod 报 `hostPath type check failed`

原因：清单里的 `hostPath` 仍是 Docker Desktop 路径，服务器上不存在（initdb 目录用的是 `type: Directory`）。
解决：按第七节把 `config/` 放到服务器上并修改 `hostPath.path`。
