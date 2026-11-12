# Kubernetes 单机安装（Ubuntu 24.04，kubeadm，master + node 同一台服务器）

用 kubeadm 在**一台** Ubuntu 24.04 服务器上搭建 Kubernetes v1.36.2，这台服务器既是 master（控制平面），也是 node（运行业务 Pod）。容器运行时 containerd，网络插件 Calico。装好后用本仓库的 `k8s/` 部署 yudao 依赖环境。

> 适合开发、测试或资源有限的场景，没有高可用：服务器宕机整个集群就不可用。
> 有两台及以上服务器时看 [k8s-cluster.md](k8s-cluster.md)；单机装好后也可以按那篇第五节再加入 node。
> Windows 本地开发直接用 Docker Desktop 自带的单节点 Kubernetes 即可，不需要看本文，见根目录 `README.md`。
> 参考教程：[Ubuntu 24.04 部署 K8s 1.36.2，单 Master 单 Node](https://www.cnzhuji.com/article/57_191047.html)。

## 0. 环境信息

| 项目 | 取值 |
|---|---|
| 操作系统 | Ubuntu 24.04 LTS（noble） |
| K8s 版本 | v1.36.2（kubeadm、kubelet、kubectl 版本一致） |
| 容器运行时 | containerd（`containerd.io`，来自 Docker 官方源） |
| 网络插件 | Calico v3.29.4 |
| Pod 网段 | `192.168.0.0/16`（Calico 默认）；服务器 IP 是 `192.168.x.x` 时自动改用 `10.244.0.0/16` |
| Service 网段 | `10.96.0.0/12`（kubeadm 默认） |
| 操作账号 | 有 sudo 权限的普通账号（不直接用 root） |

| 角色 | 主机名 | IP（示例） | 配置 |
|---|---|---|---|
| master + node | `k8s-master` | `10.0.0.10`（自动获取，见下文 `NODE_IP`） | 最低 4C8G、100G 磁盘；yudao 中间件全开建议 8C16G 以上 |

- Pod 网段、Service 网段**不能**与服务器所在网段重叠；服务器内网是 `192.168.x.x` 时，把 Pod 网段换成 `10.244.0.0/16` 等其他私有网段（文档中的命令会按服务器 IP 自动选择；`kubeadm init` 的 `--pod-network-cidr` 和 `calico.yaml` 的 `CALICO_IPV4POOL_CIDR` 必须一致）。
- **先赋值、再执行**：涉及 IP、镜像源的步骤都先给变量赋值并用 `echo` 确认，再执行后面的命令。变量只在当前终端有效，SSH 重连或新开窗口后要重新赋值，否则变量为空，命令会报错。
- **国内 / 海外二选一**：镜像源分两套写法，按服务器位置只执行其中一个代码块。国内服务器访问不了 `registry.k8s.io`、Docker Hub（报 `i/o timeout`），必须用阿里云。
- 文中 `10.0.0.10` 等 IP 只是示例，**不要原样复制**；也不要把 `<xxx>` 这类占位符原样粘贴进命令（bash 会把 `<` 当成重定向，报 `No such file or directory`）。
- 全文用普通账号执行，需要 root 权限的命令都已加 `sudo`。写系统文件统一用 `sudo tee`（`sudo echo ... > 文件` 中的重定向不走 sudo，会报 Permission denied）。不要 `sudo -i` 切到 root 后再执行，否则 `$HOME`、`$USER` 会变成 root 的，kubectl 凭证会放错位置。
- `kubectl` 不加 sudo：它读取的是当前账号的 `~/.kube/config`。
- 和集群版的区别只有三处：hosts 只写本机；不需要 `kubeadm join`；初始化后要**去掉 control-plane 污点**，否则业务 Pod 调度不上来。

## 一、系统前置配置

### 1. 更新软件源与系统

国内服务器先把 Ubuntu 源换成阿里云（海外服务器跳过这一段）。Ubuntu 24.04 的源配置在 `/etc/apt/sources.list.d/ubuntu.sources`（不再是 `/etc/apt/sources.list`）：

```bash
sudo cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
sudo sed -i 's#http://\(archive\|security\).ubuntu.com#https://mirrors.aliyun.com#g' /etc/apt/sources.list.d/ubuntu.sources
```

更新软件包列表和系统：

```bash
sudo apt update && sudo apt upgrade -y
```

成功标准：`apt update` 无报错。

### 2. 安装基础工具

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
| `ca-certificates`、`curl`、`gnupg`、`apt-transport-https` | 下载 GPG 密钥、添加 Docker / K8s 软件源、下载 `calico.yaml` |
| `chrony` | 时间同步 |
| `ufw` | 防火墙（本地部署保持关闭，装上便于确认状态） |
| `iputils-ping`、`iproute2` | `ping` 校验 hosts，`ip` 查本机 IP |
| `conntrack`、`socat`、`ethtool`、`ebtables`、`iptables` | kubelet / kube-proxy 运行依赖，kubeadm 预检会检查 |
| `vim` | 修改配置文件 |
| `git`、`openssh-client` | 拉取本仓库、`scp` 复制凭证 |

`crictl`（`cri-tools`）和 `ctr` 不在这里装：`cri-tools` 在 K8s 软件源里，第三节添加源后与 kubeadm 一起安装；`ctr` 随 `containerd.io` 一起安装。

校验：

```bash
for c in curl gpg chronyc ufw ping ip conntrack socat iptables vim git scp; do
  command -v $c > /dev/null && echo "OK  $c" || echo "缺少 $c"
done
```

成功标准：全部输出 `OK`，没有 `缺少`。

### 3. 关闭 Swap（K8s 强制要求）

```bash
# 临时关闭
sudo swapoff -a
# 永久：注释 fstab 中的 swap 行
sudo sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab
```

校验：

```bash
cat /proc/swaps
```

成功标准：只有表头，没有 swap 挂载行。

### 4. 加载内核模块、开启 IP 转发

```bash
# 开机自动加载
sudo tee /etc/modules-load.d/k8s.conf > /dev/null <<'EOF'
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl 持久配置
sudo tee /etc/sysctl.d/k8s.conf > /dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

校验：

```bash
lsmod | grep -E 'overlay|br_netfilter'
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
```

成功标准：两个模块都已加载，三个参数都为 `1`。

### 5. 主机名与 hosts 解析

```bash
sudo hostnamectl set-hostname k8s-master

# 本机 IP：取第一个地址，确认是内网 IP 后再写入 hosts
NODE_IP=$(hostname -I | awk '{print $1}')
echo $NODE_IP
```

`NODE_IP` 不对时（多网卡，第一个不是内网网卡），用 `ip -4 addr` 找到正确的 IP 手动赋值，如 `NODE_IP=192.168.1.100`。确认无误后写入 hosts：

```bash
echo "$NODE_IP k8s-master" | sudo tee -a /etc/hosts > /dev/null
```

校验：

```bash
hostname
grep k8s-master /etc/hosts
ping -c 2 k8s-master
```

成功标准：`hostname` 输出 `k8s-master`；hosts 中有映射，解析到的是本机 IP（不是 `127.0.1.1`）。

### 6. 时间同步与防火墙

```bash
sudo systemctl enable --now chrony

# 本地部署不启用防火墙（ufw 已在第 2 步安装，保持关闭）
sudo ufw disable
```

校验：

```bash
chronyc tracking | grep -E 'Reference|System time'
sudo ufw status
```

成功标准：chrony 有参考时钟、偏差在毫秒级；ufw 为 `Status: inactive`。

本地部署不开防火墙，服务器**只能放在内网**。要暴露到公网时，用云厂商安全组只放行必要端口（SSH、6443、需要访问的 yudao 服务端口），并限制来源 IP。

## 二、安装 containerd

### 1. 添加 Docker 官方源

`containerd.io` 在 Docker 的软件源中（只装 containerd，不需要 docker-ce）：

软件源地址二选一。国内服务器：

```bash
DOCKER_MIRROR=https://mirrors.aliyun.com/docker-ce
```

海外服务器：

```bash
DOCKER_MIRROR=https://download.docker.com
```

确认变量（输出为空说明没赋值或换了终端，重新执行上面一行）：

```bash
echo $DOCKER_MIRROR
```

添加源：

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL $DOCKER_MIRROR/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
$DOCKER_MIRROR/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

校验：

```bash
cat /etc/apt/sources.list.d/docker.list
gpg --show-keys /etc/apt/keyrings/docker.asc
```

成功标准：源地址正确、系统代号为 `noble`、架构与本机一致；能打印出 Docker 公钥信息（发行方、指纹）。

### 2. 安装 containerd.io

```bash
sudo apt update
sudo apt install -y containerd.io
```

校验：

```bash
containerd --version
systemctl is-active containerd
```

成功标准：输出版本号，服务状态 `active`。

### 3. 生成默认配置、使用 systemd cgroup 驱动

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# cgroup 驱动改为 systemd（与 kubelet 一致）
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

**仅国内服务器**：pause 镜像换成阿里云地址（海外服务器跳过，否则 `kubeadm init` 会卡在拉取 pause 镜像）：

```bash
sudo sed -i 's#registry.k8s.io/pause#registry.aliyuncs.com/google_containers/pause#' /etc/containerd/config.toml
```

**仅国内服务器**：给 Docker Hub（docker.io）配置国内镜像加速。Calico、nginx、busybox 以及 yudao 各服务（mysql、redis 等）的镜像都在 Docker Hub，国内直接访问官方地址超时或被限流。

先设置后续步骤使用的加速地址变量（二选一）。国内服务器：

```bash
DOCKER_HUB_MIRROR=docker.m.daocloud.io
```

海外服务器（可以直接访问 Docker Hub，跳过下面的 containerd 配置）：

```bash
DOCKER_HUB_MIRROR=docker.io
```

确认变量（第三 ~ 五节的拉取测试、Calico、nginx 都会用到；换了终端要重新赋值）：

```bash
echo $DOCKER_HUB_MIRROR
```

国内服务器配置 containerd：所有 `docker.io/...` 镜像依次尝试下面几个国内地址，**不回落到 Docker 官方地址**。清单里没写仓库前缀的镜像（如 `mysql:8.0.21`）也走这里。

```bash
# 让 containerd 读取 /etc/containerd/certs.d 下的镜像仓库配置（默认配置中有两处 config_path = ''，都改）
sudo sed -i "s#config_path = ''#config_path = '/etc/containerd/certs.d'#" /etc/containerd/config.toml

sudo mkdir -p /etc/containerd/certs.d/docker.io
sudo tee /etc/containerd/certs.d/docker.io/hosts.toml > /dev/null <<'EOF'
server = "https://docker.m.daocloud.io"

[host."https://docker.m.daocloud.io"]
  capabilities = ["pull", "resolve"]

[host."https://docker.1ms.run"]
  capabilities = ["pull", "resolve"]

[host."https://docker.1panel.live"]
  capabilities = ["pull", "resolve"]

[host."https://docker.xuanyuan.me"]
  capabilities = ["pull", "resolve"]
EOF
```

上面的地址 2026-11-12 实测可用（都是第三方公益服务，可能限流或下线）：

| 地址 | 提供方 |
|---|---|
| `docker.m.daocloud.io` | DaoCloud |
| `docker.1ms.run` | 毫秒镜像 |
| `docker.1panel.live` | 1Panel 社区 |
| `docker.xuanyuan.me` | 轩辕镜像 |

`mirror.ccs.tencentyun.com`、`<ID>.mirror.aliyuncs.com` 等云厂商加速地址只能在对应云的服务器内网使用。某个地址失效时，从 `hosts.toml` 中删掉或调整顺序，`sudo systemctl restart containerd` 后生效。检查某个地址能否拉取镜像：

```bash
curl -s -o /dev/null -w "%{http_code}\n" --max-time 8 https://docker.m.daocloud.io/v2/
```

返回 `200` 或 `401` 说明服务在线（`401` 是正常的鉴权提示）；超时、`429`（限流）、`5xx` 说明不可用。

重启生效：

```bash
sudo systemctl restart containerd
sudo systemctl enable containerd
```

校验：

```bash
grep -n SystemdCgroup /etc/containerd/config.toml
grep -n pause /etc/containerd/config.toml
# 以下两条仅国内服务器
grep -n "config_path" /etc/containerd/config.toml
cat /etc/containerd/certs.d/docker.io/hosts.toml
```

成功标准：输出 `SystemdCgroup = true`；国内服务器的 pause 镜像为 `registry.aliyuncs.com/google_containers/pause:x.x`，两处 `config_path` 都是 `'/etc/containerd/certs.d'`（`plugin_config_path` 那行不用管），`hosts.toml` 内容与上面一致。如果没有 `SystemdCgroup` 这一行（部分 containerd 2.x 的默认配置不带），用 `sudo vi /etc/containerd/config.toml` 在 runc 的 `options` 段手动加上 `SystemdCgroup = true`，再 `sudo systemctl restart containerd`。

## 三、安装 kubeadm、kubelet、kubectl

### 1. 添加 K8s 源（v1.36）

软件源地址二选一。国内服务器：

```bash
K8S_MIRROR=https://mirrors.aliyun.com/kubernetes-new/core/stable
```

海外服务器：

```bash
K8S_MIRROR=https://pkgs.k8s.io/core:/stable:
```

确认变量（输出为空说明没赋值或换了终端，重新执行上面一行）：

```bash
echo $K8S_MIRROR
```

添加源：

```bash
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL $K8S_MIRROR/v1.36/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] $K8S_MIRROR/v1.36/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
```

校验：

```bash
cat /etc/apt/sources.list.d/kubernetes.list
sudo apt update
```

成功标准：源地址以 `/v1.36/deb/` 结尾，`apt update` 无 GPG 密钥报错。

### 2. 安装指定版本并锁定

```bash
K8S_VER=1.36.2
apt-cache madison kubeadm | head -5        # 确认源里有该版本
sudo apt install -y kubeadm=${K8S_VER}-* kubelet=${K8S_VER}-* kubectl=${K8S_VER}-*
# crictl（排查容器用），新版 kubeadm 不再自动安装
sudo apt install -y cri-tools

# 锁定版本，防止 apt upgrade 时意外升级
sudo apt-mark hold kubelet kubeadm kubectl cri-tools containerd.io
sudo systemctl enable --now kubelet

# crictl 默认连接 containerd，之后不用每次带 --runtime-endpoint
sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock
```

此时 kubelet 会每隔几秒重启一次（等待 `kubeadm init` 下发配置），属于正常现象。

校验：

```bash
kubeadm version -o short
kubectl version --client
kubelet --version
apt-mark showhold
sudo crictl version
# 验证 Docker Hub 镜像加速（DOCKER_HUB_MIRROR 为空时按第二节第 3 步重新赋值）
sudo crictl pull $DOCKER_HUB_MIRROR/library/busybox:1.36
```

成功标准：三个组件版本都是 `v1.36.2`；锁定列表包含 `containerd.io`、`cri-tools`、`kubeadm`、`kubectl`、`kubelet`；`crictl version` 能输出 containerd 的版本；`crictl pull` 输出 `Image is up to date for ...`。

## 四、初始化集群

### 1. 设置变量

```bash
# 本机 IP：取本机第一个地址
NODE_IP=$(hostname -I | awk '{print $1}')
# Pod 网段：本机 IP 是 192.168.x.x 时改用 10.244.0.0/16，避免与内网冲突
if [[ $NODE_IP == 192.168.* ]]; then POD_CIDR=10.244.0.0/16; else POD_CIDR=192.168.0.0/16; fi
```

镜像仓库二选一。国内服务器：

```bash
IMAGE_REPO=registry.aliyuncs.com/google_containers
```

海外服务器：

```bash
IMAGE_REPO=registry.k8s.io
```

确认变量：

```bash
echo "NODE_IP=$NODE_IP POD_CIDR=$POD_CIDR IMAGE_REPO=$IMAGE_REPO"
```

成功标准：三个值都不为空；`NODE_IP` 是本机内网 IP（不是 docker0 的 `172.17.0.1` 之类）。不对时用 `ip -4 addr` 找到正确的 IP 手动赋值（如 `NODE_IP=192.168.1.100`），再重新执行 `POD_CIDR` 那一行。

### 2. 拉取镜像

```bash
sudo kubeadm config images list --kubernetes-version=v1.36.2 --image-repository=$IMAGE_REPO
sudo kubeadm config images pull --kubernetes-version=v1.36.2 --image-repository=$IMAGE_REPO
```

成功标准：每个镜像都输出 `[config/images] Pulled ...`。

- 报 `i/o timeout`：服务器访问不了所选仓库，国内服务器要用阿里云（见上一步）。
- 报 `not found`：阿里云还没同步该补丁版本，`--kubernetes-version` 换成已有的 1.36.x，并用 apt 把 kubeadm、kubelet、kubectl 装成同一版本。

### 3. kubeadm init

```bash
sudo kubeadm init \
  --apiserver-advertise-address=$NODE_IP \
  --kubernetes-version=v1.36.2 \
  --pod-network-cidr=$POD_CIDR \
  --image-repository=$IMAGE_REPO | tee ~/kubeadm-init.log
```

init 失败后重试前，先清理上一次的残留：

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d $HOME/.kube
```

输出 `Your Kubernetes control-plane has initialized successfully!` 即成功。末尾的 `kubeadm join` 命令单机用不到，以后要加 node 时可以用 `sudo kubeadm token create --print-join-command` 重新生成。

### 4. 配置 kubectl

把管理员凭证复制到当前账号目录，之后 kubectl 不需要 sudo：

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

校验：

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

成功标准：`k8s-master` 状态为 `NotReady`（还没装网络插件，正常）；`etcd`、`kube-apiserver`、`kube-controller-manager`、`kube-scheduler` 为 `Running`，`coredns` 为 `Pending`（等网络插件）。

`admin.conf` / `~/.kube/config` 是集群最高权限凭证，不要提交到仓库或发到聊天工具里。

### 5. 去掉 control-plane 污点（单机关键步骤）

kubeadm 默认给 master 打上 `node-role.kubernetes.io/control-plane:NoSchedule` 污点，业务 Pod 不会调度到 master。单机没有其他 node，必须去掉：

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

校验：

```bash
kubectl describe node k8s-master | grep -A2 Taints
```

成功标准：`Taints` 只剩 `node.kubernetes.io/not-ready:NoSchedule`（装完网络插件后会自动消失）或 `<none>`，没有 `control-plane`。

可选：同时打上 worker 角色标签，`kubectl get nodes` 的 `ROLES` 列显示 `control-plane,worker`：

```bash
kubectl label node k8s-master node-role.kubernetes.io/worker=
```

### 6. 部署 Calico 网络插件

国内服务器要注意：`raw.githubusercontent.com` 可能下载不了；Calico 镜像在 Docker Hub，要换成第二节第 3 步的加速地址。所以先下载清单、改网段、换镜像地址并试拉，确认没问题再 apply。

**1）下载 calico.yaml**

```bash
cd ~
curl -fsSLO https://raw.githubusercontent.com/projectcalico/calico/v3.29.4/manifests/calico.yaml
ls -lh calico.yaml
```

成功标准：文件存在，大小为几百 KB（不是 0 字节，打开不是 HTML 报错页）。

下载超时时，在能访问 GitHub 的开发机上下载，再传到服务器：

```bash
# 开发机上执行：改成服务器的登录账号和 IP
SERVER_USER=k8s
SERVER_IP=10.0.0.10
curl -fsSLO https://raw.githubusercontent.com/projectcalico/calico/v3.29.4/manifests/calico.yaml
scp calico.yaml $SERVER_USER@$SERVER_IP:~/
```

**2）Pod 网段写入清单**

把 `CALICO_IPV4POOL_CIDR` 显式设成与 `kubeadm init` 的 `--pod-network-cidr` 相同的值（不依赖 Calico 自动识别，Pod 网段为 `10.244.0.0/16` 时尤其要改）：

```bash
echo $POD_CIDR      # 为空说明换了终端，按第 1 步重新设置变量
sed -i -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' \
       -e "s|#   value: \"192.168.0.0/16\"|  value: \"$POD_CIDR\"|" calico.yaml
grep -n -A1 "CALICO_IPV4POOL_CIDR" calico.yaml
```

成功标准：输出的两行前面都没有 `#`，值与 `$POD_CIDR` 一致：

```text
- name: CALICO_IPV4POOL_CIDR
  value: "10.244.0.0/16"
```

**3）镜像地址换成加速地址，并试拉**

```bash
echo $DOCKER_HUB_MIRROR      # 为空时按第二节第 3 步重新赋值
sed -i "s#docker.io/#$DOCKER_HUB_MIRROR/#g" calico.yaml
grep "image:" calico.yaml | sort -u
sudo crictl pull $DOCKER_HUB_MIRROR/calico/node:v3.29.4
```

成功标准：`image:` 都是 `$DOCKER_HUB_MIRROR/calico/...`（国内为 `docker.m.daocloud.io/calico/...`）；`crictl pull` 输出 `Image is up to date for ...`。拉取失败时按第二节第 3 步换一个加速地址，重新给 `DOCKER_HUB_MIRROR` 赋值后，用 `sed -i "s#docker.m.daocloud.io/#$DOCKER_HUB_MIRROR/#g" calico.yaml` 替换（把旧地址换成新地址）。

**4）部署**

```bash
kubectl apply -f calico.yaml
```

- 服务器有多块网卡时，Calico 可能选错网卡，在 `calico-node` 的环境变量中加 `IP_AUTODETECTION_METHOD=interface=eth0`（换成内网的网卡名）。
- 升级 Calico 前到 <https://github.com/projectcalico/calico/releases> 确认与当前 K8s 版本兼容。

校验：

```bash
kubectl get pods -n kube-system -w      # Ctrl+C 退出
kubectl get nodes
```

第一次部署要拉镜像，`calico-node` 停在 `Init:0/3` 一两分钟属于正常，之后依次经过 `Init:1/3`、`Init:2/3`、`PodInitializing`、`Running`；calico-node 就绪后 `calico-kube-controllers`、`coredns` 才从 `Pending` 开始创建。超过 3 分钟仍是 `Init:0/3` 时，用 `kubectl describe pod -n kube-system -l k8s-app=calico-node | tail -15` 查看是否拉镜像失败。

成功标准：`calico-node`、`calico-kube-controllers`、`coredns` 全部 `Running`；`k8s-master` 变为 `Ready`。

## 五、最终验证

### 1. 节点与系统 Pod

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

成功标准：

```text
NAME         STATUS   ROLES                  AGE   VERSION   INTERNAL-IP   ...   OS-IMAGE             CONTAINER-RUNTIME
k8s-master   Ready    control-plane,worker   10m   v1.36.2   10.0.0.10     ...   Ubuntu 24.04 LTS     containerd://x.x.x
```

节点 `Ready`、版本 `v1.36.2`；`kube-system` 下所有 Pod `Running`，没有 `CrashLoopBackOff`、`Error`。

### 2. 调度、网络与 DNS 测试

```bash
echo $DOCKER_HUB_MIRROR      # 为空时按第二节第 3 步重新赋值
kubectl create deployment test-nginx --image=$DOCKER_HUB_MIRROR/library/nginx --replicas=2
kubectl expose deployment test-nginx --port=80 --type=NodePort
# 等待两个 Pod 就绪（比 get pods -w 直观，成功输出 successfully rolled out）
kubectl rollout status deployment/test-nginx --timeout=120s
kubectl get pods -o wide -l app=test-nginx
kubectl get svc test-nginx                       # PORT(S) 列 80:3xxxx 中的 3xxxx 就是 NodePort

NODE_IP=$(hostname -I | awk '{print $1}')      # 本机 IP，用于访问 NodePort
curl -s http://$NODE_IP:$(kubectl get svc test-nginx -o jsonpath='{.spec.ports[0].nodePort}') | grep title

# DNS 测试（不用 -it：第一次要拉镜像，交互模式会一直等待像卡住一样，Ctrl+C 后 Pod 还会残留）
kubectl delete pod dns-test --ignore-not-found
# 用完整域名：busybox 新版 nslookup 不使用 search 域，查短名 kubernetes.default 会报 NXDOMAIN
kubectl run dns-test --image=$DOCKER_HUB_MIRROR/library/busybox:1.36 --restart=Never -- nslookup kubernetes.default.svc.cluster.local
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/dns-test --timeout=60s
kubectl logs dns-test
kubectl delete pod dns-test

# 清理
kubectl delete svc,deployment test-nginx
```

成功标准：两个 nginx Pod 都 `Running` 并调度到 `k8s-master`（一直 `Pending` 说明污点没去掉，回到第四节第 5 步）；`rollout status` 输出 `successfully rolled out`；`curl` 输出 `<title>Welcome to nginx!</title>`；`kubectl logs dns-test` 输出 `Name: kubernetes.default.svc.cluster.local` 和 `Address: 10.96.0.1`。

## 六、默认 StorageClass

本仓库的清单用 PVC 存数据，并依赖**默认 StorageClass**（Docker Desktop 自带，kubeadm 集群没有）。单机用 local-path-provisioner 正合适，数据存在本机 `/opt/local-path-provisioner`：

下载清单（下载超时时和 `calico.yaml` 一样，在开发机上下载后 `scp` 过来）：

```bash
LOCAL_PATH_VERSION=v0.0.32   # 到 https://github.com/rancher/local-path-provisioner/releases 确认版本
cd ~
curl -fsSLO https://raw.githubusercontent.com/rancher/local-path-provisioner/$LOCAL_PATH_VERSION/deploy/local-path-storage.yaml
```

镜像（`rancher/local-path-provisioner`、辅助 Pod 用的 `busybox`）换成加速地址：

```bash
echo $DOCKER_HUB_MIRROR      # 为空时按第二节第 3 步重新赋值
sed -i -e "s#image: rancher/#image: $DOCKER_HUB_MIRROR/rancher/#" \
       -e "s#image: busybox#image: $DOCKER_HUB_MIRROR/library/busybox#" local-path-storage.yaml
grep -n "image:" local-path-storage.yaml
```

确认两处 `image:` 都以 `$DOCKER_HUB_MIRROR/` 开头后部署，并设为默认：

```bash
kubectl apply -f local-path-storage.yaml
kubectl -n local-path-storage rollout status deployment/local-path-provisioner --timeout=120s
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

校验：

```bash
kubectl get storageclass
```

成功标准：`rollout status` 输出 `successfully rolled out`；`local-path` 后面带 `(default)`。`rollout status` 超时时，用 `kubectl -n local-path-storage describe pod | tail -10` 查看是否拉镜像失败（`image:` 没换成加速地址）。

验证能创建存储卷。`VOLUMEBINDINGMODE` 是 `WaitForFirstConsumer`，PVC 要等有 Pod 使用时才会真正创建，所以用一个 Pod 来测。先把测试清单写成文件（`EOF` 不加引号，`$DOCKER_HUB_MIRROR` 会被替换成实际地址），确认后再 apply：

```bash
echo $DOCKER_HUB_MIRROR      # 为空时按第二节第 3 步重新赋值
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
grep image ~/test-pvc.yaml
```

确认 `image:` 是加速地址（国内为 `docker.m.daocloud.io/library/busybox:1.36`）后创建：

```bash
kubectl apply -f ~/test-pvc.yaml
kubectl wait --for=condition=Ready pod/test-pvc-pod --timeout=120s
kubectl get pvc test-pvc
sudo ls /opt/local-path-provisioner/
```

成功标准：`wait` 输出 `condition met`；PVC 的 `STATUS` 为 `Bound`；`sudo ls /opt/local-path-provisioner/` 能看到 `pvc-xxxx_default_test-pvc` 目录。

清理（删除 PVC 后，local-path 会自动删除对应目录）：

```bash
kubectl delete -f ~/test-pvc.yaml
rm ~/test-pvc.yaml
```

PVC 一直 `Pending`：`kubectl describe pvc test-pvc` 查看事件；`no persistent volumes available` / 没有 provisioner 相关事件时，检查 `local-path` 是否为 `(default)`、`local-path-provisioner` Pod 是否 `Running`。

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

集群装好后才发现 Docker Hub 镜像拉不下来（Pod `ImagePullBackOff`），或者某个加速地址失效需要更换时，按下面的步骤处理（服务器上执行第 1~3 步）。

**1. 确认 containerd 读取 certs.d**

```bash
grep -n "config_path" /etc/containerd/config.toml
```

两处 `config_path` 是 `''` 时先改：

```bash
sudo sed -i "s#config_path = ''#config_path = '/etc/containerd/certs.d'#" /etc/containerd/config.toml
```

**2. 写入（或修改）加速地址并重启 containerd**

```bash
sudo mkdir -p /etc/containerd/certs.d/docker.io
sudo tee /etc/containerd/certs.d/docker.io/hosts.toml > /dev/null <<'EOF'
server = "https://docker.m.daocloud.io"

[host."https://docker.m.daocloud.io"]
  capabilities = ["pull", "resolve"]

[host."https://docker.1ms.run"]
  capabilities = ["pull", "resolve"]

[host."https://docker.1panel.live"]
  capabilities = ["pull", "resolve"]

[host."https://docker.xuanyuan.me"]
  capabilities = ["pull", "resolve"]
EOF
sudo systemctl restart containerd
systemctl is-active containerd
```

重启 containerd 不影响已经在运行的 Pod；`kubectl` 短暂连不上时等十几秒即可。

**3. 用加速地址试拉**

```bash
DOCKER_HUB_MIRROR=docker.m.daocloud.io
sudo crictl pull $DOCKER_HUB_MIRROR/library/nginx:latest
```

成功标准：输出 `Image is up to date for ...`。失败时用第二节第 3 步的 `curl` 命令检查地址，换成可用的地址后回到第 2 步。

**4. 让拉取失败的 Pod 重新拉取（在 master 上执行）**

镜像地址已经是 `$DOCKER_HUB_MIRROR/...` 的，删除 Pod 让控制器重建即可：

```bash
kubectl delete pod <Pod名> -n <命名空间>
```

镜像地址还是 `docker.io/...` 或不带仓库前缀（如 `nginx`）的，把镜像改成加速地址（Deployment 会自动滚动重建 Pod）：

```bash
kubectl set image deployment/<Deployment名> <容器名>=$DOCKER_HUB_MIRROR/library/nginx -n <命名空间>
```

`<容器名>` 用 `kubectl get deployment <Deployment名> -n <命名空间> -o jsonpath='{.spec.template.spec.containers[*].name}'` 查看。以第五节的 nginx 测试为例，容器名就是 `nginx`：

```bash
kubectl set image deployment/test-nginx nginx=$DOCKER_HUB_MIRROR/library/nginx
kubectl rollout status deployment/test-nginx --timeout=120s
kubectl get pods -o wide -l app=test-nginx
kubectl get deployment test-nginx -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

成功标准：`rollout status` 输出 `successfully rolled out`；Pod 名中间那段（ReplicaSet 哈希）变成新的、状态 `1/1 Running`；镜像为 `docker.m.daocloud.io/library/nginx`。

更新过程中旧 Pod（名字里是旧的哈希）会短暂显示 `Completed` / `Terminating` 后消失，属于正常。用 `get pods -w` 观察时只会打印状态变化的行，容易只看到旧 Pod，用 `rollout status` 更直观。镜像仍是旧地址时，多半是执行 `set image` 时 `$DOCKER_HUB_MIRROR` 为空（换了终端），重新赋值后再执行。

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
解决：containerd 的 pause 镜像换成阿里云（第二节第 3 步）；`IMAGE_REPO=registry.aliyuncs.com/google_containers` 后重新拉取；init 已经执行过的先 `sudo kubeadm reset -f`。

### init 报 `wait-control-plane ... dial tcp <IP>:6443: connect: connection refused`

原因：控制平面容器没有启动。国内服务器最常见的是 containerd 的 pause 镜像仍是 `registry.k8s.io/pause`（漏了第二节第 3 步），`sudo journalctl -u kubelet --no-pager -n 50` 中能看到 `failed to pull image "registry.k8s.io/pause:x.x"`；`kubeadm --image-repository` 只影响控制平面镜像，不影响 containerd 的 pause 镜像。
解决：

```bash
sudo sed -i 's#registry.k8s.io/pause#registry.aliyuncs.com/google_containers/pause#' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d $HOME/.kube
```

然后重新设置变量、执行 init。其他原因用 `sudo crictl ps -a` 看 etcd、kube-apiserver 是否在反复重启，再用 `sudo crictl logs <容器ID>` 看日志。

### `sudo: crictl: command not found`

原因：漏了第三节第 2 步中的 `cri-tools`（新版 kubeadm 不再依赖它，不会自动安装）。
解决：`sudo apt install -y cri-tools`，再执行 `sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock`。

### 执行命令报 `-bash: 本机IP: No such file or directory`

原因：把 `<本机IP>` 这类占位符原样粘贴进了命令，bash 把 `<` 当成了输入重定向。命令没有真正执行。
解决：按文档先给变量赋值（如 `NODE_IP=$(hostname -I | awk '{print $1}')`），`echo` 确认后再执行引用 `$NODE_IP` 的命令。

### 业务 Pod 一直 Pending，事件提示 `untolerated taint {node-role.kubernetes.io/control-plane: }`

原因：没有去掉 control-plane 污点。
解决：执行第四节第 5 步。

### Pod Pending，事件提示 `Insufficient cpu` / `Insufficient memory`

原因：单机资源不够，控制平面和中间件抢资源。
解决：`kubectl describe node k8s-master` 查看 `Allocated resources`；停掉不用的中间件，或给服务器扩容。

### `kubeadm init` 卡在 `[wait-control-plane]` 或报 kubelet 不健康

原因：containerd 与 kubelet 的 cgroup 驱动不一致，或 pause / 控制平面镜像拉不下来。
解决：`sudo journalctl -u kubelet -f` 看具体报错；确认 `/etc/containerd/config.toml` 中 `SystemdCgroup = true`、镜像地址可拉取，`sudo systemctl restart containerd` 后 `sudo kubeadm reset -f` 再重新 init。

### preflight 报 `[ERROR Swap]` / `[ERROR FileContent--proc-sys-net-bridge-bridge-nf-call-iptables]`

原因：swap 未关闭，或 `br_netfilter` 模块未加载。
解决：重新执行第一节第 3、4 步。

### `kubeadm init` 报 `[ERROR IsPrivilegedUser]: user is not running as root`

原因：kubeadm 命令没加 `sudo`。
解决：`kubeadm init`、`kubeadm reset`、`kubeadm config images pull`、`kubeadm certs` 都要加 `sudo`。

### 写配置文件报 `Permission denied`

原因：用了 `sudo echo ... > /etc/xxx` 或 `sudo cat > /etc/xxx <<EOF`，重定向由当前账号的 shell 执行，没有 root 权限。
解决：改成 `echo ... | sudo tee /etc/xxx > /dev/null`，追加用 `sudo tee -a`。

### kubectl 报 `connection to the server localhost:8080 was refused`

原因：当前账号没有 `~/.kube/config`，或者用了 `sudo kubectl`（读的是 root 的 `/root/.kube/config`）。
解决：按第四节第 4 步复制凭证，kubectl 不加 sudo。

### `apt install kubeadm=1.36.2-*` 提示找不到版本

原因：K8s 源的版本目录不对（如写成了 `v1.35`），或镜像源尚未同步该补丁版本。
解决：`cat /etc/apt/sources.list.d/kubernetes.list` 确认是 `v1.36`；`apt-cache madison kubeadm` 查看可用版本。

### 节点一直 NotReady / coredns 一直 Pending

原因：Calico 没起来（镜像拉取失败最常见），或防火墙被开启后拦截了 Pod 网络流量。
解决：`kubectl get pods -n kube-system | grep calico` 找到 Pod，`kubectl describe pod` / `kubectl logs` 看原因；`sudo ufw status` 确认防火墙为 `inactive`。

### Pod 卡在 `ImagePullBackOff`（calico、nginx、busybox 等 Docker Hub 镜像）

原因：拉不到 Docker Hub 镜像（国内最常见，直接访问官方地址时好时坏：Calico 能拉下来，nginx 却失败）。
解决：按第二节第 3 步配置 containerd 的国内加速地址，清单和命令里的镜像写成 `$DOCKER_HUB_MIRROR/...`；已配置仍失败时，用第二节第 3 步的 `curl` 命令逐个检查加速地址，删掉不可用的，`sudo systemctl restart containerd` 后让 Pod 重新拉取，完整步骤见“运维操作 → 补配 / 更换 Docker Hub 加速地址”。`kubectl describe pod <Pod名> | tail -10` 可以看到是哪个镜像拉取失败。

### DNS 测试报 `server can't find kubernetes.default: NXDOMAIN`，`kubectl wait` 一直不返回

原因：busybox 新版本的 `nslookup` 不使用 `/etc/resolv.conf` 的 search 域，短名 `kubernetes.default` 不会补全成 `kubernetes.default.svc.cluster.local`；命令失败后 Pod 为 `Failed`，等待 `Succeeded` 的 `kubectl wait` 会一直等到超时。输出第一行 `Server: 10.96.0.10` 说明 CoreDNS 本身是通的。
解决：`kubectl delete pod dns-test` 后改查完整域名 `kubernetes.default.svc.cluster.local`（第五节第 2 步已是这种写法）。

### Pod 拿到的 IP 不在 Pod 网段内，或与内网 IP 冲突

原因：`calico.yaml` 中 `CALICO_IPV4POOL_CIDR` 没有改，或与 `kubeadm init` 的 `--pod-network-cidr` 不一致。
解决：`kubectl get ippools -o wide` 查看 Calico 实际使用的网段；不一致时重置集群，按文档重新 init 并在 apply 前改好 `calico.yaml`。

### Pod 一直 Pending，提示 `unbound immediate PersistentVolumeClaims`

原因：集群没有默认 StorageClass。
解决：按第六节安装 local-path-provisioner 并设为默认。

### MySQL / PostgreSQL Pod 报 `hostPath type check failed`

原因：清单里的 `hostPath` 仍是 Docker Desktop 路径，服务器上不存在（initdb 目录用的是 `type: Directory`）。
解决：按第七节把 `config/` 放到服务器上并修改 `hostPath.path`。
