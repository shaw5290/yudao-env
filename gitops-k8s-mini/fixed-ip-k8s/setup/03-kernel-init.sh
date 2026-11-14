#!/usr/bin/env bash
# ================= 03 内核参数 + kubeadm init =================
# 作用：关闭 swap、加载 overlay/br_netfilter、写 sysctl，用 config/kubeadm-config.yaml
#       初始化集群（advertise/controlPlaneEndpoint 都是 10.10.10.10:6443）。
# 注意：已初始化的机器上不要重复执行（03 只做一次性 init）。
# 用法：bash 03-kernel-init.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$SCRIPT_DIR/../config"

info() { echo -e "\n[信息] $*"; }
ok()   { echo "[成功] $*"; }
die()  { echo "[错误] $*" >&2; exit 1; }
s()    { if [ -n "${SUDO_PASS:-}" ]; then echo "$SUDO_PASS" | sudo -S -p '' "$@"; else sudo "$@"; fi; }

[ "$(id -u)" -ne 0 ] || die "不要用 root 运行，用有 sudo 权限的普通账号"
[ -f "$CONF_DIR/kubeadm-config.yaml" ] || die "找不到 $CONF_DIR/kubeadm-config.yaml"
[ -f /etc/kubernetes/admin.conf ] && die "本机已初始化（/etc/kubernetes/admin.conf 存在），如需重建先执行 02-backup-reset.sh"
ip -4 -o addr show dummy0 2>/dev/null | grep -q '10\.10\.10\.10' || die "dummy0 上没有 10.10.10.10/32，先执行 01-dummy0.sh"

info "内核模块与 sysctl"
printf 'overlay\nbr_netfilter\n' | s tee /etc/modules-load.d/k8s.conf > /dev/null
s tee /etc/sysctl.d/99-k8s.conf > /dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF
s modprobe overlay
s modprobe br_netfilter
s sysctl --system > /dev/null 2>&1
echo "  ip_forward=$(sysctl -n net.ipv4.ip_forward) bridge-nf-call-iptables=$(sysctl -n net.bridge.bridge-nf-call-iptables)"

info "关闭 swap"
if [ "$(free -m | awk '/Swap:/{print $2}')" != "0" ]; then
  s swapoff -a
  s sed -i '/\sswap\s/s/^/#/' /etc/fstab
fi
[ "$(tail -n +2 /proc/swaps | wc -l)" -eq 0 ] || die "swap 未关闭：$(cat /proc/swaps)"

info "放置 kubeadm 配置到 /root/kubeadm-config.yaml（后续 k8s-allow-ip.sh 以此为准）"
s cp "$CONF_DIR/kubeadm-config.yaml" /root/kubeadm-config.yaml
s chmod 600 /root/kubeadm-config.yaml
s kubeadm config images list --config /root/kubeadm-config.yaml 2>&1 | head -8

info "kubeadm init"
s kubeadm init --config /root/kubeadm-config.yaml 2>&1 | tee /tmp/kubeadm-init.log | tail -30
s cp /tmp/kubeadm-init.log /root/kubeadm-init.log

info "校验"
echo -n "  静态 Pod 清单: "; ls /etc/kubernetes/manifests | tr '\n' ' '; echo
echo -n "  证书 SAN     : "
s openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text 2>/dev/null \
  | grep -A1 'Subject Alternative Name' | tail -1 | sed 's/^ *//'
echo -n "  kubeconfig   : "; s grep -h 'server:' /etc/kubernetes/admin.conf | sed 's/^ *//'
echo -n "  kubelet 参数 : "; s cat /var/lib/kubelet/kubeadm-flags.env

ok "初始化完成，接下来执行 04-kubeconfig-cni.sh"
