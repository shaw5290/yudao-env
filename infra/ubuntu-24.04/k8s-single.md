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

- Pod 网段、Service 网段**不能**与服务器所在网段重叠；服务器内网是 `192.168.x.x` 时，把 Pod 网段换成 `10.244.0.0/16` 等其他私有网段（`kubeadm init` 的 `--pod-network-cidr` 改成同一个值即可，Calico 会自动识别）。
- **先赋值、再执行**：涉及 IP、镜像源的步骤都先给变量赋值并用 `echo` 确认，再执行后面的命令。变量只在当前终端有效，SSH 重连或新开窗口后要重新赋值，否则变量为空，命令会报错。
- **国内 / 海外二选一**：镜像源分两套写法，按服务器位置只执行其中一个代码块。国内服务器访问不了 `registry.k8s.io`、Docker Hub（报 `i/o timeout`），必须用阿里云。
- 文中 `10.0.0.10` 等 IP 只是示例，**不要原样复制**；也不要把 `<xxx>` 这类占位符原样粘贴进命令（bash 会把 `<` 当成重定向，报 `No such file or directory`）。
- 全文用普通账号执行，需要 root 权限的命令都已加 `sudo`。写系统文件统一用 `sudo tee`（`sudo echo ... > 文件` 中的重定向不走 sudo，会报 Permission denied）。不要 `sudo -i` 切到 root 后再执行，否则 `$HOME`、`$USER` 会变成 root 的，kubectl 凭证会放错位置。
- `kubectl` 不加 sudo：它读取的是当前账号的 `~/.kube/config`。
- 和集群版的区别只有三处：hosts 只写本机；不需要 `kubeadm join`；初始化后要**去掉 control-plane 污点**，否则业务 Pod 调度不上来。

## 一、系统前置配置

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

本地部署不开防火墙，服务器**只能放在内网**。要暴露到公网时，用云厂商安全组只放行必要端口（SSH、6443、需要访问的 yudao 服务端口），并限制来源 IP。

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

此时 kubelet 会每隔几秒重启一次（等待 `kubeadm init` 下发配置），属于正常现象。

校验：

```bash
kubeadm version -o short
kubectl version --client
kubelet --version
apt-mark showhold
sudo crictl version
```

成功标准：三个组件版本都是 `v1.36.2`；锁定列表包含 `containerd.io`、`cri-tools`、`kubeadm`、`kubectl`、`kubelet`；`crictl version` 能输出 containerd 的版本。

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

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.4/manifests/calico.yaml
```

- Calico 镜像在 `docker.io` / `quay.io`，国内服务器大概率拉取失败（Pod 卡在 `ImagePullBackOff`），此时替换 `calico.yaml` 中的镜像地址，或用 `sudo ctr -n k8s.io images import <镜像包>.tar` 导入离线镜像。
- 服务器有多块网卡时，Calico 可能选错网卡，在 `calico-node` 的环境变量中加 `IP_AUTODETECTION_METHOD=interface=eth0`（换成内网网卡名）。
- 升级 Calico 前到 <https://github.com/projectcalico/calico/releases> 确认与当前 K8s 版本兼容。

校验：

```bash
kubectl get pods -n kube-system -w      # Ctrl+C 退出
kubectl get nodes
```

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
kubectl create deployment test-nginx --image=nginx --replicas=2
kubectl expose deployment test-nginx --port=80 --type=NodePort
kubectl get pods -o wide -l app=test-nginx
kubectl get svc test-nginx                       # PORT(S) 列 80:3xxxx 中的 3xxxx 就是 NodePort
curl http://$NODE_IP:$(kubectl get svc test-nginx -o jsonpath='{.spec.ports[0].nodePort}')

kubectl run dns-test --rm -it --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default

# 清理
kubectl delete svc,deployment test-nginx
```

成功标准：两个 nginx Pod 都 `Running` 并调度到 `k8s-master`（一直 `Pending` 说明污点没去掉，回到第四节第 5 步）；`curl` 返回 nginx 欢迎页（`Welcome to nginx!`；`NODE_IP` 为空时先按第四节第 1 步赋值）；`nslookup` 能解析出 `kubernetes.default` 的地址。

## 六、默认 StorageClass

本仓库的清单用 PVC 存数据，并依赖**默认 StorageClass**（Docker Desktop 自带，kubeadm 集群没有）。单机用 local-path-provisioner 正合适，数据存在本机 `/opt/local-path-provisioner`：

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

原因：新版 kubeadm 不再依赖 `cri-tools`，不会自动安装 crictl。
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
解决：重新执行第一节第 1、2 步。

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

### Pod 一直 Pending，提示 `unbound immediate PersistentVolumeClaims`

原因：集群没有默认 StorageClass。
解决：按第六节安装 local-path-provisioner 并设为默认。

### MySQL / PostgreSQL Pod 报 `hostPath type check failed`

原因：清单里的 `hostPath` 仍是 Docker Desktop 路径，服务器上不存在（initdb 目录用的是 `type: Directory`）。
解决：按第七节把 `config/` 放到服务器上并修改 `hostPath.path`。
