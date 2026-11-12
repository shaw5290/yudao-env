#!/usr/bin/env bash
# ================= Ubuntu 24.04 单机 K8s 一键安装（master + node 同一台，对应 k8s-single.md）=================
# 用法：
#   bash install-k8s-single.sh                 按顺序执行全部步骤（已完成的步骤可重复执行）
#   bash install-k8s-single.sh calico verify   只执行指定步骤
#   bash install-k8s-single.sh --from calico   从指定步骤开始执行到最后
#   bash install-k8s-single.sh --list          列出全部步骤
# 变量：~/k8s-install.env（不存在时从同目录 k8s-install.env 复制一份，确认后重新运行；可用 K8S_ENV 指定其他路径）
# 用有 sudo 权限的普通账号运行，不要 sudo bash 运行（kubectl 凭证要放到当前账号的 ~/.kube）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${K8S_ENV:-$HOME/k8s-install.env}"
# 步骤顺序与 k8s-single.md 章节一致
STEPS=(apt tools swap kernel hosts time containerd kube pull init kubeconfig taint calico verify storage)

info() { echo -e "\n[信息] $*"; }
ok()   { echo "[成功] $*"; }
die()  { echo "[错误] $*" >&2; exit 1; }

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ---------------- 前置检查与变量 ----------------
precheck() {
  [ "$(id -u)" -ne 0 ] || die "不要用 root 或 sudo bash 运行，用有 sudo 权限的普通账号执行：bash $0"
  sudo -v || die "当前账号没有 sudo 权限"
  # shellcheck disable=SC1091
  . /etc/os-release
  [ "${VERSION_ID:-}" = "24.04" ] || die "仅支持 Ubuntu 24.04，当前为 ${PRETTY_NAME:-未知系统}"
}

load_env() {
  if [ ! -f "$ENV_FILE" ]; then
    cp "$SCRIPT_DIR/k8s-install.env" "$ENV_FILE"
    die "已生成 $ENV_FILE，确认 REGION、NODE_IP 等变量后重新运行"
  fi
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  [ -n "${NODE_IP:-}" ] || die "NODE_IP 为空，在 $ENV_FILE 中手动设置"
  info "变量：REGION=$REGION NODE_NAME=$NODE_NAME NODE_IP=$NODE_IP POD_CIDR=$POD_CIDR"
  info "      K8S_VER=$K8S_VER IMAGE_REPO=$IMAGE_REPO DOCKER_HUB_MIRROR=$DOCKER_HUB_MIRROR"
}

# ---------------- 一、系统前置配置 ----------------
step_apt() {
  if [ "$REGION" = cn ]; then
    [ -f /etc/apt/sources.list.d/ubuntu.sources.bak ] || sudo cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
    sudo sed -i 's#http://\(archive\|security\).ubuntu.com#https://mirrors.aliyun.com#g' /etc/apt/sources.list.d/ubuntu.sources
  fi
  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
}

step_tools() {
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl gnupg apt-transport-https \
    chrony ufw iputils-ping iproute2 \
    conntrack socat ethtool ebtables iptables \
    vim git openssh-client
  local c missing=""
  for c in curl gpg chronyc ufw ping ip conntrack socat iptables vim git scp; do
    command -v "$c" > /dev/null || missing="$missing $c"
  done
  [ -z "$missing" ] || die "缺少命令：$missing"
}

step_swap() {
  sudo swapoff -a
  sudo sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab
  [ "$(tail -n +2 /proc/swaps | wc -l)" -eq 0 ] || die "swap 未关闭：$(cat /proc/swaps)"
}

step_kernel() {
  printf 'overlay\nbr_netfilter\n' | sudo tee /etc/modules-load.d/k8s.conf > /dev/null
  sudo modprobe overlay
  sudo modprobe br_netfilter
  sudo tee /etc/sysctl.d/k8s.conf > /dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
  sudo sysctl --system > /dev/null
  local k
  for k in net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward; do
    [ "$(sysctl -n "$k")" = 1 ] || die "$k 不是 1"
  done
}

step_hosts() {
  sudo hostnamectl set-hostname "$NODE_NAME"
  # 删除旧的同名映射后追加，重复执行不会产生多行
  sudo sed -i "/[[:space:]]$NODE_NAME\$/d" /etc/hosts
  echo "$NODE_IP $NODE_NAME" | sudo tee -a /etc/hosts > /dev/null
  [ "$(getent hosts "$NODE_NAME" | awk '{print $1}')" = "$NODE_IP" ] || die "$NODE_NAME 没有解析到 $NODE_IP，检查 /etc/hosts"
}

step_time() {
  sudo systemctl enable --now chrony
  # 本地部署不启用防火墙
  sudo ufw disable > /dev/null
  systemctl is-active --quiet chrony || die "chrony 未运行"
  sudo ufw status | grep -q inactive || die "ufw 未关闭"
}

# ---------------- 二、安装 containerd ----------------
step_containerd() {
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL "$DOCKER_MIRROR/linux/ubuntu/gpg" -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] $DOCKER_MIRROR/linux/ubuntu $VERSION_CODENAME stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y containerd.io

  # 只在未配置过时生成默认配置，避免重复执行时覆盖已有修改
  sudo mkdir -p /etc/containerd
  if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml 2> /dev/null; then
    containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  fi
  grep -q 'SystemdCgroup = true' /etc/containerd/config.toml \
    || die "config.toml 中没有 SystemdCgroup = true，用 sudo vi 在 runc 的 options 段手动加上后重新运行"

  if [ "$REGION" = cn ]; then
    sudo sed -i "s#registry.k8s.io/pause#$IMAGE_REPO/pause#" /etc/containerd/config.toml
    sudo sed -i "s#config_path = ''#config_path = '/etc/containerd/certs.d'#" /etc/containerd/config.toml
    sudo mkdir -p /etc/containerd/certs.d/docker.io
    {
      echo "server = \"https://$DOCKER_HUB_MIRROR\""
      local m
      for m in $DOCKER_HUB_MIRRORS; do
        printf '\n[host."https://%s"]\n  capabilities = ["pull", "resolve"]\n' "$m"
      done
    } | sudo tee /etc/containerd/certs.d/docker.io/hosts.toml > /dev/null
    grep -q "$IMAGE_REPO/pause" /etc/containerd/config.toml || die "pause 镜像未替换"
    grep -q "config_path = '/etc/containerd/certs.d'" /etc/containerd/config.toml || die "config_path 未修改"
  fi

  sudo systemctl enable containerd
  sudo systemctl restart containerd
  systemctl is-active --quiet containerd || die "containerd 未运行"
}

# ---------------- 三、安装 kubeadm、kubelet、kubectl ----------------
step_kube() {
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL "$K8S_MIRROR/$K8S_MINOR/deb/Release.key" | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] $K8S_MIRROR/$K8S_MINOR/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
  sudo apt-get update
  apt-cache madison kubeadm | grep -q "$K8S_VER-" || die "软件源中没有 kubeadm $K8S_VER，apt-cache madison kubeadm 查看可用版本后修改 K8S_VER"
  sudo apt-get install -y --allow-change-held-packages \
    "kubeadm=$K8S_VER-*" "kubelet=$K8S_VER-*" "kubectl=$K8S_VER-*" cri-tools
  sudo apt-mark hold kubelet kubeadm kubectl cri-tools containerd.io > /dev/null
  sudo systemctl enable --now kubelet
  sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock
  [ "$(kubeadm version -o short)" = "v$K8S_VER" ] || die "kubeadm 版本不是 v$K8S_VER"
}

step_pull() {
  sudo crictl pull "$DOCKER_HUB_MIRROR/library/busybox:1.36" \
    || die "拉取 Docker Hub 镜像失败，检查 /etc/containerd/certs.d/docker.io/hosts.toml 中的加速地址"
}

# ---------------- 四、初始化集群 ----------------
step_init() {
  if [ -f /etc/kubernetes/admin.conf ]; then
    info "集群已初始化（/etc/kubernetes/admin.conf 已存在），跳过；需要重装先执行 sudo kubeadm reset -f"
    return
  fi
  sudo kubeadm config images pull --kubernetes-version="v$K8S_VER" --image-repository="$IMAGE_REPO"
  sudo kubeadm init \
    --apiserver-advertise-address="$NODE_IP" \
    --kubernetes-version="v$K8S_VER" \
    --pod-network-cidr="$POD_CIDR" \
    --image-repository="$IMAGE_REPO" | tee "$HOME/kubeadm-init.log" \
    || die "kubeadm init 失败，查看 sudo journalctl -u kubelet --no-pager -n 50；重试前先 sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d \$HOME/.kube"
}

step_kubeconfig() {
  mkdir -p "$HOME/.kube"
  sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
  sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  kubectl get nodes
}

step_taint() {
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2> /dev/null || true
  kubectl label node "$NODE_NAME" node-role.kubernetes.io/worker= --overwrite
  if kubectl get node "$NODE_NAME" -o jsonpath='{.spec.taints[*].key}' | grep -q control-plane; then
    die "control-plane 污点未去掉"
  fi
}

step_calico() {
  cd "$HOME"
  [ -s calico.yaml ] || curl -fsSLo calico.yaml "https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VER/manifests/calico.yaml" \
    || die "下载 calico.yaml 失败：在能访问 GitHub 的机器上下载后放到 ~/calico.yaml，再执行 bash $0 --from calico"
  sed -i -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' \
         -e "s|#   value: \"192.168.0.0/16\"|  value: \"$POD_CIDR\"|" calico.yaml
  grep -A1 -- '- name: CALICO_IPV4POOL_CIDR' calico.yaml | grep -q "\"$POD_CIDR\"" \
    || die "calico.yaml 中 CALICO_IPV4POOL_CIDR 不是 $POD_CIDR"
  sed -i "s#docker.io/#$DOCKER_HUB_MIRROR/#g" calico.yaml
  sudo crictl pull "$DOCKER_HUB_MIRROR/calico/node:$CALICO_VER"
  kubectl apply -f calico.yaml
  kubectl -n kube-system rollout status daemonset/calico-node --timeout=300s
  kubectl -n kube-system rollout status deployment/calico-kube-controllers --timeout=300s
  kubectl -n kube-system rollout status deployment/coredns --timeout=300s
  kubectl wait --for=condition=Ready "node/$NODE_NAME" --timeout=120s
}

# ---------------- 五、最终验证 ----------------
step_verify() {
  kubectl delete deployment,service test-nginx --ignore-not-found
  kubectl delete pod dns-test --ignore-not-found
  kubectl create deployment test-nginx --image="$DOCKER_HUB_MIRROR/library/nginx" --replicas=2
  kubectl expose deployment test-nginx --port=80 --type=NodePort
  kubectl rollout status deployment/test-nginx --timeout=180s
  local port
  port=$(kubectl get svc test-nginx -o jsonpath='{.spec.ports[0].nodePort}')
  curl -s --max-time 10 "http://$NODE_IP:$port" | grep -q 'Welcome to nginx' || die "NodePort http://$NODE_IP:$port 访问失败"
  ok "NodePort 正常：http://$NODE_IP:$port"

  kubectl run dns-test --image="$DOCKER_HUB_MIRROR/library/busybox:1.36" --restart=Never -- nslookup kubernetes.default.svc.cluster.local
  kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/dns-test --timeout=120s || die "DNS 测试失败：kubectl logs dns-test"
  kubectl logs dns-test | grep -q '10.96.0.1' || die "DNS 解析结果不对：kubectl logs dns-test"
  ok "集群 DNS 正常"

  kubectl delete pod dns-test
  kubectl delete deployment,service test-nginx
}

# ---------------- 六、默认 StorageClass ----------------
step_storage() {
  cd "$HOME"
  [ -s local-path-storage.yaml ] || curl -fsSLO "https://raw.githubusercontent.com/rancher/local-path-provisioner/$LOCAL_PATH_VER/deploy/local-path-storage.yaml" \
    || die "下载 local-path-storage.yaml 失败：在能访问 GitHub 的机器上下载后放到 ~/，再执行 bash $0 --from storage"
  sed -i -e "s#image: rancher/#image: $DOCKER_HUB_MIRROR/rancher/#" \
         -e "s#image: busybox#image: $DOCKER_HUB_MIRROR/library/busybox#" local-path-storage.yaml
  kubectl apply -f local-path-storage.yaml
  kubectl -n local-path-storage rollout status deployment/local-path-provisioner --timeout=180s
  kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

  cat > "$HOME/test-pvc.yaml" <<EOF
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
  kubectl delete -f "$HOME/test-pvc.yaml" --ignore-not-found > /dev/null
  kubectl apply -f "$HOME/test-pvc.yaml"
  kubectl wait --for=condition=Ready pod/test-pvc-pod --timeout=180s || die "PVC 测试失败：kubectl describe pvc test-pvc"
  [ "$(kubectl get pvc test-pvc -o jsonpath='{.status.phase}')" = Bound ] || die "PVC 不是 Bound"
  ok "PVC 正常：$(sudo ls /opt/local-path-provisioner/)"
  kubectl delete -f "$HOME/test-pvc.yaml"
  rm -f "$HOME/test-pvc.yaml"
}

# ---------------- 入口 ----------------
main() {
  local run=()
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --list) printf '%s\n' "${STEPS[@]}"; exit 0 ;;
    --from)
      [ -n "${2:-}" ] || die "--from 后面要跟步骤名，用 --list 查看"
      local s found=0
      for s in "${STEPS[@]}"; do
        [ "$s" = "$2" ] && found=1
        [ "$found" = 1 ] && run+=("$s")
      done
      [ "$found" = 1 ] || die "未知步骤：$2"
      ;;
    "") run=("${STEPS[@]}") ;;
    *) run=("$@") ;;
  esac

  precheck
  load_env
  local s
  for s in "${run[@]}"; do
    declare -F "step_$s" > /dev/null || die "未知步骤：$s，用 --list 查看"
    info "==================== 步骤 $s ===================="
    "step_$s"
    ok "步骤 $s 完成"
  done
  info "全部完成。kubectl get nodes："
  kubectl get nodes -o wide 2> /dev/null || true
}

main "$@"
