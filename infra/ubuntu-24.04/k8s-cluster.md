# Kubernetes 集群安装（Ubuntu 24.04，kubeadm，master + node 两台服务器）

用 kubeadm 在两台 Ubuntu 24.04 服务器上搭建 Kubernetes v1.36.2 集群（容器运行时 containerd，网络插件 Calico），然后用本仓库的 `k8s/` 部署 yudao 依赖环境。

> 参考教程：[Ubuntu 24.04 部署 K8s 1.36.2，单 Master 单 Node](https://www.cnzhuji.com/article/57_191047.html)。
> 只有一台服务器（master 和 node 在同一台）时看 [k8s-single.md](k8s-single.md)。
> Windows 本地开发直接用 Docker Desktop 自带的单节点 Kubernetes 即可，不需要看本文，见根目录 `README.md`。

## 0. 环境信息

| 项目 | 取值 |
|---|---|
| 操作系统 | Ubuntu 24.04 LTS（noble） |
| K8s 版本 | v1.36.2（kubeadm、kubelet、kubectl 版本一致，所有节点一致） |
| 容器运行时 | containerd（`containerd.io`，来自 Docker 官方源） |
| 网络插件 | Calico v3.29.4 |
| Pod 网段 | `192.168.0.0/16`（Calico 默认）；服务器 IP 是 `192.168.x.x` 时自动改用 `10.244.0.0/16` |
| Service 网段 | `10.96.0.0/12`（kubeadm 默认） |
| 操作账号 | 两台节点上同名的普通账号，有 sudo 权限（不直接用 root） |

| 角色 | 主机名 | IP（示例，以实际为准） | 最低配置 |
|---|---|---|---|
| master | `k8s-master` | `10.0.0.10` | 2C4G，40G 磁盘 |
| node | `k8s-node01` | `10.0.0.11` | 4C8G，100G 磁盘；中间件全开建议 8C16G |

- Pod 网段、Service 网段**不能**与服务器所在网段重叠；服务器内网是 `192.168.x.x` 时，把 Pod 网段换成 `10.244.0.0/16` 等其他私有网段（`kubeadm init` 的 `--pod-network-cidr` 改成同一个值即可，Calico 会自动识别）。
- **先赋值、再执行**：涉及 IP、镜像源的步骤都先给变量赋值并用 `echo` 确认，再执行后面的命令。变量只在当前终端有效，SSH 重连或新开窗口后要重新赋值，否则变量为空，命令会报错。
- **国内 / 海外二选一**：镜像源分两套写法，按服务器位置只执行其中一个代码块。国内服务器访问不了 `registry.k8s.io`、Docker Hub（报 `i/o timeout`），必须用阿里云。
- 文中 `10.0.0.10` 等 IP 只是示例，**不要原样复制**；也不要把 `<xxx>` 这类占位符原样粘贴进命令（bash 会把 `<` 当成重定向，报 `No such file or directory`）。
- 两台节点**第一 ~ 三节都要执行**，第四节只在 master 执行，第五节只在 node 执行。
- 全文用普通账号执行，需要 root 权限的命令都已加 `sudo`。写系统文件统一用 `sudo tee`（`sudo echo ... > 文件` 中的重定向不走 sudo，会报 Permission denied）。不要 `sudo -i` 切到 root 后再执行，否则 `$HOME`、`$USER` 会变成 root 的，kubectl 凭证会放错位置。
- `kubectl` 不加 sudo：它读取的是当前账号的 `~/.kube/config`。

## 一、两台节点统一前置配置

### 1. 关闭 Swap（K8s 强制要求）

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

### 2. 加载内核模块、开启 IP 转发

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

### 3. 主机名与 hosts 解析

master 执行：

```bash
sudo hostnamectl set-hostname k8s-master
```

node 执行：

```bash
sudo hostnamectl set-hostname k8s-node01
```

两台都执行。先在每台机器上用 `hostname -I` 查出各自的 IP，然后把两台的**实际 IP** 赋值给变量（下面是示例值，必须改）：

```bash
MASTER_IP=10.0.0.10
NODE01_IP=10.0.0.11
echo "MASTER_IP=$MASTER_IP NODE01_IP=$NODE01_IP"
```

确认无误后写入 hosts：

```bash
printf '%s k8s-master\n%s k8s-node01\n' "$MASTER_IP" "$NODE01_IP" | sudo tee -a /etc/hosts > /dev/null
```

校验：

```bash
hostname
grep k8s /etc/hosts
ping -c 2 k8s-master && ping -c 2 k8s-node01
```

成功标准：`hostname` 输出本机主机名；hosts 中有两条映射；两个主机名都能 ping 通。

### 4. 时间同步与防火墙

```bash
sudo apt update
sudo apt install -y chrony ufw
sudo systemctl enable --now chrony

# 本地部署不启用防火墙（最小化安装的 Ubuntu 没有 ufw，上面一并安装，保持关闭）
sudo ufw disable
```

校验：

```bash
chronyc tracking | grep -E 'Reference|System time'
sudo ufw status
```

成功标准：chrony 有参考时钟、偏差在毫秒级；ufw 为 `Status: inactive`。

本地部署不开防火墙，服务器**只能放在内网**。云服务器要在安全组中放行两台机器之间的 [K8s 端口](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)（master 6443、2379-2380、10250、10257、10259；node 10250、10256、30000-32767；Calico 179/tcp 和 IPIP，IP 协议 4），对公网只放行必要端口并限制来源 IP。

### 5. （可选）更新系统软件包

```bash
sudo apt update && sudo apt upgrade -y
```

Ubuntu 24.04 的源配置在 `/etc/apt/sources.list.d/ubuntu.sources`（不再是 `/etc/apt/sources.list`）。国内服务器可以把其中的 `archive.ubuntu.com`、`security.ubuntu.com` 换成 `mirrors.aliyun.com`：

```bash
sudo cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
sudo sed -i 's#http://\(archive\|security\).ubuntu.com#https://mirrors.aliyun.com#g' /etc/apt/sources.list.d/ubuntu.sources
sudo apt update
```

成功标准：`apt update` 无报错。

## 二、两台节点安装 containerd

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
sudo apt install -y ca-certificates curl gnupg
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

重启生效：

```bash
sudo systemctl restart containerd
sudo systemctl enable containerd
```

校验：

```bash
grep -n SystemdCgroup /etc/containerd/config.toml
grep -n pause /etc/containerd/config.toml
```

成功标准：输出 `SystemdCgroup = true`；国内服务器的 pause 镜像为 `registry.aliyuncs.com/google_containers/pause:x.x`。如果没有 `SystemdCgroup` 这一行（部分 containerd 2.x 的默认配置不带），用 `sudo vi /etc/containerd/config.toml` 在 runc 的 `options` 段手动加上 `SystemdCgroup = true`，再 `sudo systemctl restart containerd`。

## 三、两台节点安装 kubeadm、kubelet、kubectl

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
sudo apt install -y apt-transport-https ca-certificates curl gpg
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

此时 kubelet 会每隔几秒重启一次（等待 `kubeadm init` / `join` 下发配置），属于正常现象。

校验：

```bash
kubeadm version -o short
kubectl version --client
kubelet --version
apt-mark showhold
sudo crictl version
```

成功标准：三个组件版本都是 `v1.36.2`；锁定列表包含 `containerd.io`、`cri-tools`、`kubeadm`、`kubectl`、`kubelet`；`crictl version` 能输出 containerd 的版本（containerd 的 socket 只有 root 能访问，所以 crictl 要加 sudo）。

## 四、仅 master 节点：初始化控制平面

### 1. 设置变量

```bash
# master IP：取本机第一个地址
MASTER_IP=$(hostname -I | awk '{print $1}')
# Pod 网段：本机 IP 是 192.168.x.x 时改用 10.244.0.0/16，避免与内网冲突
if [[ $MASTER_IP == 192.168.* ]]; then POD_CIDR=10.244.0.0/16; else POD_CIDR=192.168.0.0/16; fi
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
echo "MASTER_IP=$MASTER_IP POD_CIDR=$POD_CIDR IMAGE_REPO=$IMAGE_REPO"
```

成功标准：三个值都不为空；`MASTER_IP` 是本机内网 IP（不是 docker0 的 `172.17.0.1` 之类）。不对时用 `ip -4 addr` 找到正确的 IP 手动赋值（如 `MASTER_IP=192.168.1.100`），再重新执行 `POD_CIDR` 那一行。

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
  --apiserver-advertise-address=$MASTER_IP \
  --kubernetes-version=v1.36.2 \
  --pod-network-cidr=$POD_CIDR \
  --image-repository=$IMAGE_REPO | tee ~/kubeadm-init.log
```

init 失败后重试前，先清理上一次的残留：

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d $HOME/.kube
```

成功后输出末尾有 join 命令，**保存下来**，node 加入时使用（`~/kubeadm-init.log` 中也有）：

```text
kubeadm join <master IP>:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:xxxxxxxxxxxxxxxxxxxx
```

token 有效期 24 小时，过期后执行 `sudo kubeadm token create --print-join-command` 重新生成。

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

### 5. 部署 Calico 网络插件

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.4/manifests/calico.yaml
```

- Calico 镜像在 `docker.io` / `quay.io`，国内服务器大概率拉取失败（Pod 卡在 `ImagePullBackOff`），此时替换 `calico.yaml` 中的镜像地址，或在每个节点上用 `sudo ctr -n k8s.io images import <镜像包>.tar` 导入离线镜像。
- 节点有多块网卡时，Calico 可能选错网卡，在 `calico-node` 的环境变量中加 `IP_AUTODETECTION_METHOD=interface=eth0`（换成节点间互通的网卡名）。
- 升级 Calico 前到 <https://github.com/projectcalico/calico/releases> 确认与当前 K8s 版本兼容。

校验：

```bash
kubectl get pods -n kube-system -w      # Ctrl+C 退出
kubectl get nodes
```

成功标准：`calico-node`、`calico-kube-controllers`、`coredns` 全部 `Running`；`k8s-master` 变为 `Ready`。

## 五、仅 node 节点：加入集群

### 1. 执行 join 命令

复制 master 上 `~/kubeadm-init.log` 末尾的**完整 join 命令**（或在 master 上执行 `sudo kubeadm token create --print-join-command` 重新生成），前面加 `sudo` 在 node 上执行。格式如下，不要直接复制这个示例：

```text
sudo kubeadm join 10.0.0.10:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:xxxxxxxxxxxxxxxxxxxx
```

校验（node 上）：

```bash
systemctl status kubelet --no-pager
```

成功标准：kubelet `active (running)`，日志中没有认证或连接错误。

### 2. （可选）在 node 上使用 kubectl

一般只在 master 或开发机上操作集群。确实需要在 node 上执行 kubectl 时，从 master 复制凭证。`/etc/kubernetes/admin.conf` 只有 root 能读，普通账号复制的是第四节第 4 步放到家目录的那份：

```bash
# master 上执行（两台账号同名时 NODE_USER 不用改）
NODE_USER=$USER
scp ~/.kube/config $NODE_USER@k8s-node01:~/admin.conf

# node 上执行
mkdir -p $HOME/.kube
mv ~/admin.conf $HOME/.kube/config
chmod 600 $HOME/.kube/config
kubectl get nodes
```

`admin.conf` 有集群全部权限，复制到的机器越多，泄露风险越大。

## 六、master 上最终验证

### 1. 节点与系统 Pod

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

成功标准：

```text
NAME         STATUS   ROLES           AGE   VERSION   INTERNAL-IP   ...   OS-IMAGE             CONTAINER-RUNTIME
k8s-master   Ready    control-plane   15m   v1.36.2   10.0.0.10     ...   Ubuntu 24.04 LTS     containerd://x.x.x
k8s-node01   Ready    <none>          3m    v1.36.2   10.0.0.11     ...   Ubuntu 24.04 LTS     containerd://x.x.x
```

两个节点都是 `Ready`，版本都是 `v1.36.2`；`kube-system` 下所有 Pod `Running`，没有 `CrashLoopBackOff`、`Error`。

可选：给 node 打上角色标签，`ROLES` 列显示 `worker`：

```bash
kubectl label node k8s-node01 node-role.kubernetes.io/worker=
```

### 2. 调度、网络与 DNS 测试

```bash
kubectl create deployment test-nginx --image=nginx --replicas=2
kubectl expose deployment test-nginx --port=80 --type=NodePort
kubectl get pods -o wide -l app=test-nginx
kubectl get svc test-nginx                       # 浏览器或 curl 访问 节点IP:NodePort

kubectl run dns-test --rm -it --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default

# 清理
kubectl delete svc,deployment test-nginx
```

成功标准：nginx Pod 全部 `Running` 且调度到 `k8s-node01`（master 默认有 `control-plane` 污点，不调度业务 Pod）；NodePort 能访问到 nginx 欢迎页；`nslookup` 能解析出 `kubernetes.default` 的地址。

只有一台机器、不加 node 时，按 [k8s-single.md](k8s-single.md) 部署（需要去掉 master 的污点）。

## 七、默认 StorageClass

本仓库的清单用 PVC 存数据，并依赖**默认 StorageClass**（Docker Desktop 自带，kubeadm 集群没有）。测试/开发集群可以用 local-path-provisioner，数据存在 Pod 所在节点的 `/opt/local-path-provisioner`：

```bash
LOCAL_PATH_VERSION=v0.0.32   # 到 https://github.com/rancher/local-path-provisioner/releases 确认版本
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/$LOCAL_PATH_VERSION/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

校验：

```bash
kubectl get storageclass
```

成功标准：`local-path` 后面带 `(default)`。

local-path 的数据绑定在节点上，节点故障数据就不可用；生产环境换成 NFS、Ceph 或云厂商的 CSI。

## 八、部署 yudao-env 到该集群

### 1. 在开发机上访问集群

把 master 上当前账号的 `~/.kube/config` 复制到开发机，**合并时改一个好认的上下文名**，避免和其他集群混淆：

```bash
# 开发机（WSL / Linux）：改成 master 的登录账号和 IP
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

**每次操作前确认上下文**（`kubectl config current-context`）：开发机上可能同时配置了线上集群，脚本都显式带 `--context`，手动执行 kubectl 时也要带上。

### 2. 清单需要调整的地方

`k8s/services/*.yaml` 是按 Docker Desktop 单节点写的，部署到 kubeadm 集群前要处理：

| 问题 | 涉及清单 | 处理方式 |
|---|---|---|
| `hostPath` 写死为 `/run/desktop/mnt/host/d/...`（Docker Desktop 的 Windows 盘映射） | `mysql.yaml`、`postgres.yaml`、`rocketmq.yaml`、`seata.yaml` | 把本仓库 `config/` 复制到 node 上（如 `sudo mkdir -p /opt/yudao-env` 后放到 `/opt/yudao-env/config`），`hostPath.path` 改成节点路径；有多个 node 时要么每台都复制，要么用 `nodeSelector` 把这些 Pod 固定到一台 node；更规范的做法是改成 ConfigMap |
| `hostPort` 占用节点端口 | 所有服务 | 访问地址是 **Pod 所在节点的 IP**，不再是 `127.0.0.1`；需要固定访问地址时改用 NodePort 或 Ingress |
| Jenkins 挂载 `/var/run/docker.sock`、`/usr/bin/docker` | `jenkins.yaml` | kubeadm 节点只有 containerd，没有 Docker；需要在该 node 上按 [Docker 环境安装](docker.md) 装 docker-ce，或者不部署 Jenkins |
| PVC 依赖默认 StorageClass | 所有带 PVC 的服务 | 按第七节配置 |
| Secret `yudao-env` 由 `.env` 生成 | 所有服务 | 脚本自动同步；`.env` 中的 `ROCKETMQ_BROKER_IP`、`SEATA_IP` 改成对应节点的 IP |

## 九、运维操作

### 移除 node

```bash
# master 上
kubectl drain k8s-node01 --ignore-daemonsets --delete-emptydir-data
kubectl delete node k8s-node01

# 被移除的 node 上
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
rm -rf $HOME/.kube
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
```

### 重置整个集群

先在 node、最后在 master 上执行 `sudo kubeadm reset -f`，并按上面清理 CNI 配置、`~/.kube` 和 iptables；之后可以从第四节重新初始化。**会清空 etcd，集群内所有资源都会丢失。**

### 证书续期

kubeadm 签发的证书有效期 1 年，`kubeadm upgrade` 时会自动续期。不升级的集群要在到期前手动续期（master 上执行）：

```bash
sudo kubeadm certs check-expiration
sudo kubeadm certs renew all
# 续期后重启控制平面组件（静态 Pod）：临时移走再移回清单
sudo mkdir -p /tmp/manifests
sudo sh -c 'mv /etc/kubernetes/manifests/*.yaml /tmp/manifests/ && sleep 20 && mv /tmp/manifests/*.yaml /etc/kubernetes/manifests/'
# 更新当前账号的 kubectl 凭证
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

## 附录：排错

常用命令：

```bash
sudo kubeadm token create --print-join-command    # master：重新生成 join 命令
sudo journalctl -u kubelet -f                     # 查看 kubelet 日志
kubectl describe pod <pod> -n <ns>                # 查看 Pod 事件
sudo kubeadm reset -f && rm -rf $HOME/.kube       # node：加入失败后重置，再重新 join
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

原因：新版 kubeadm 不再依赖 `cri-tools`，不会自动安装 crictl。
解决：`sudo apt install -y cri-tools`，再执行 `sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock`。

### 执行命令报 `-bash: 本机IP: No such file or directory`

原因：把 `<本机IP>` 这类占位符原样粘贴进了命令，bash 把 `<` 当成了输入重定向。命令没有真正执行。
解决：按文档先给变量赋值（如 `MASTER_IP=$(hostname -I | awk '{print $1}')`），`echo` 确认后再执行引用 `$MASTER_IP` 的命令。

### `kubeadm init` 卡在 `[wait-control-plane]` 或报 kubelet 不健康

原因：containerd 与 kubelet 的 cgroup 驱动不一致，或 pause / 控制平面镜像拉不下来。
解决：`sudo journalctl -u kubelet -f` 看具体报错；确认 `/etc/containerd/config.toml` 中 `SystemdCgroup = true`、镜像地址可拉取，`sudo systemctl restart containerd` 后 `sudo kubeadm reset -f` 再重新 init。

### preflight 报 `[ERROR Swap]` / `[ERROR FileContent--proc-sys-net-bridge-bridge-nf-call-iptables]`

原因：swap 未关闭，或 `br_netfilter` 模块未加载。
解决：重新执行第一节第 1、2 步。

### `kubeadm init` 报 `[ERROR IsPrivilegedUser]: user is not running as root`

原因：kubeadm 命令没加 `sudo`。
解决：`kubeadm init`、`kubeadm join`、`kubeadm reset`、`kubeadm config images pull`、`kubeadm token create` 都要加 `sudo`。

### 写配置文件报 `Permission denied`

原因：用了 `sudo echo ... > /etc/xxx` 或 `sudo cat > /etc/xxx <<EOF`，重定向由当前账号的 shell 执行，没有 root 权限。
解决：改成 `echo ... | sudo tee /etc/xxx > /dev/null`，追加用 `sudo tee -a`。

### kubectl 报 `connection to the server localhost:8080 was refused`

原因：当前账号没有 `~/.kube/config`，或者用了 `sudo kubectl`（读的是 root 的 `/root/.kube/config`）。
解决：按第四节第 4 步复制凭证，kubectl 不加 sudo。

### `apt install kubeadm=1.36.2-*` 提示找不到版本

原因：K8s 源的版本目录不对（如写成了 `v1.35`），或镜像源尚未同步该补丁版本。
解决：`cat /etc/apt/sources.list.d/kubernetes.list` 确认是 `v1.36`；`apt-cache madison kubeadm` 查看可用版本。

### node 一直 NotReady

原因：Calico 在该节点没起来（镜像拉取失败最常见），或节点间 BGP 179 / IPIP 被防火墙、安全组拦截。
解决：`kubectl get pods -n kube-system -o wide | grep calico` 找到该节点上的 Pod，`kubectl describe pod` / `kubectl logs` 看原因。

### join 报 `token id ... is invalid` 或 `x509: certificate has expired`

原因：token 过期（默认 24 小时）。
解决：master 上 `sudo kubeadm token create --print-join-command` 生成新命令。

### Pod 一直 Pending，提示 `unbound immediate PersistentVolumeClaims`

原因：集群没有默认 StorageClass。
解决：按第七节安装 local-path-provisioner 并设为默认。

### MySQL / PostgreSQL Pod 报 `hostPath type check failed`

原因：清单里的 `hostPath` 仍是 Docker Desktop 路径，节点上不存在（initdb 目录用的是 `type: Directory`）。
解决：按第八节把 `config/` 复制到节点并修改 `hostPath.path`。
