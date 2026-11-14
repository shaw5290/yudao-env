#!/usr/bin/env bash
# ================= 04 kubectl 入口 + 去污点 + 安装 Calico =================
# 作用：
#   1. kubectl 用户配置 ~/.kube/config，server 固定写成 https://127.0.0.1:6443（本机永远可用）
#   2. 去掉单节点的 control-plane:NoSchedule 污点，业务 Pod 才能跑在本机
#   3. 安装 Calico，并锁定节点地址为 dummy0（IP_AUTODETECTION_METHOD=interface=dummy0），
#      避免 Calico 误选 ens18 的 DHCP 地址
# 用量：CALICO_YAML=~/calico.yaml bash 04-kubeconfig-cni.sh
#       不给 CALICO_YAML 时，尝试从 ~/calico.yaml 读；没有则报错并给下载命令
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 优先用随目录附带的离线清单，其次 ~/calico.yaml
if [ -z "${CALICO_YAML:-}" ]; then
  if [ -f "$SCRIPT_DIR/../manifests/calico.yaml" ]; then
    CALICO_YAML="$SCRIPT_DIR/../manifests/calico.yaml"
  else
    CALICO_YAML="$HOME/calico.yaml"
  fi
fi
CALICO_VER="${CALICO_VER:-v3.29.4}"
DOCKER_HUB_MIRROR="${DOCKER_HUB_MIRROR:-docker.m.daocloud.io}"

info() { echo -e "\n[信息] $*"; }
ok()   { echo "[成功] $*"; }
die()  { echo "[错误] $*" >&2; exit 1; }
s()    { if [ -n "${SUDO_PASS:-}" ]; then echo "$SUDO_PASS" | sudo -S -p '' "$@"; else sudo "$@"; fi; }

[ "$(id -u)" -ne 0 ] || die "不要用 root 运行，用有 sudo 权限的普通账号"
[ -f /etc/kubernetes/admin.conf ] || die "还没初始化，先执行 03-kernel-init.sh"

info "配置 kubectl（入口 https://127.0.0.1:6443）"
mkdir -p "$HOME/.kube"
s cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
s chown "$(id -u):$(id -g)" "$HOME/.kube/config"
sed -i 's|server: https://10.10.10.10:6443|server: https://127.0.0.1:6443|' "$HOME/.kube/config"
grep 'server:' "$HOME/.kube/config" | sed 's/^/  /'
export KUBECONFIG="$HOME/.kube/config"
kubectl cluster-info | head -2
kubectl get node

info "去掉 control-plane 污点（单机 master+node）"
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>&1 | tail -2 || true

info "准备 Calico 清单"
if [ ! -f "$CALICO_YAML" ]; then
  cat <<EOF
  找不到 $CALICO_YAML。先下载再执行（国内可用加速地址）：
    curl -fsSL -o ~/calico.yaml \\
      https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VER}/manifests/calico.yaml
    # 然后把镜像地址换成国内加速：
    sed -i "s#docker.io/calico/#${DOCKER_HUB_MIRROR}/calico/#g" ~/calico.yaml
EOF
  die "缺少 Calico 清单"
fi
# 镜像换到加速地址（幂等）
sed -i "s#image: docker.io/calico/#image: ${DOCKER_HUB_MIRROR}/calico/#g" "$CALICO_YAML"
# 锁定节点地址到 dummy0（幂等）
if ! grep -q 'IP_AUTODETECTION_METHOD' "$CALICO_YAML"; then
  sed -i 's|^              value: "autodetect"$|              value: "autodetect"\n            - name: IP_AUTODETECTION_METHOD\n              value: "interface=dummy0"|' "$CALICO_YAML"
fi
grep -A1 'IP_AUTODETECTION_METHOD' "$CALICO_YAML" | sed 's/^/  /'
echo -n "  Pod 网段: "; grep -A1 'CALICO_IPV4POOL_CIDR' "$CALICO_YAML" | tail -1 | sed 's/^ *//'

info "应用 Calico"
kubectl apply -f "$CALICO_YAML" 2>&1 | tail -4

info "等待 Pod 就绪（最多 120s）"
for i in $(seq 1 24); do
  notready=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -vc 'Running')
  run=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c 'Running')
  echo "  ${i}0s: Running=$run 未就绪=$notready"
  [ "$notready" = "0" ] && break
  sleep 5
done
kubectl get pods -A -o wide
kubectl get nodes -o wide

ok "完成，接下来执行 05-storage.sh"
