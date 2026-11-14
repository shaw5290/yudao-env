#!/usr/bin/env bash
# ================= 02 备份并重置旧集群 =================
# 作用：备份 /etc/kubernetes、/etc/cni、/var/lib/kubelet 等；kubeadm reset 并清理
#       CNI 配置、残留虚拟网卡、iptables 里的 KUBE/cali 链、etcd 数据。
# 注意：会删除旧集群，只在「重建」时执行；备份在 /root/k8s-backup-<时间戳>/
# 用法：bash 02-backup-reset.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS=$(date +%Y%m%d-%H%M%S)
BK=/root/k8s-backup-$TS

info() { echo -e "\n[信息] $*"; }
ok()   { echo "[成功] $*"; }
die()  { echo "[错误] $*" >&2; exit 1; }
s()    { if [ -n "${SUDO_PASS:-}" ]; then echo "$SUDO_PASS" | sudo -S -p '' "$@"; else sudo "$@"; fi; }

[ "$(id -u)" -ne 0 ] || die "不要用 root 运行，用有 sudo 权限的普通账号"

info "备份旧状态到 $BK"
s mkdir -p "$BK"
if [ -d /etc/kubernetes ]; then
  s tar czf "$BK/etc-kubernetes.tar.gz" --warning=no-file-changed /etc/kubernetes 2>/dev/null
fi
s tar czf "$BK/others.tar.gz" --warning=no-file-changed \
  --exclude='pods' --exclude='plugins' \
  /etc/cni /var/lib/kubelet /root/.kube 2>/dev/null
s ls -lh "$BK"

info "停止 kubelet 并 reset"
s systemctl stop kubelet 2>/dev/null
s kubeadm reset -f --cri-socket unix:///run/containerd/containerd.sock 2>&1 | tail -5

info "清理残留（CNI 配置、虚拟网卡、iptables、etcd 数据）"
for l in cni0 tunl0 vxlan.calico flannel.1; do s ip link del "$l" 2>/dev/null; done
s rm -rf /var/lib/cni /var/lib/calico /var/lib/etcd /etc/cni/net.d /etc/kubernetes/pki /etc/kubernetes/manifests
s mkdir -p /etc/cni/net.d
s rm -rf /var/lib/kubelet/*
s sh -c "iptables-save 2>/dev/null | grep -vE 'KUBE|cali' | iptables-restore 2>/dev/null" || true
s sh -c "ip6tables-save 2>/dev/null | grep -vE 'KUBE|cali' | ip6tables-restore 2>/dev/null" || true

info "校验清理结果"
echo "  /etc/kubernetes: $(ls -A /etc/kubernetes 2>/dev/null | wc -l) 项"
echo "  /etc/cni/net.d : $(ls -A /etc/cni/net.d 2>/dev/null | wc -l) 项"
echo -n "  残留网卡       : "; ip -o link show | grep -E 'cni0|tunl0|vxlan|flannel' || echo "无"
echo -n "  KUBE 链数量    : "; s sh -c "iptables -t nat -L -n 2>/dev/null | grep -c KUBE" || echo 0

ip -4 -o addr show dummy0 | grep -q '10\.10\.10\.10' \
  && ok "dummy0 正常（10.10.10.10/32 未受影响）" \
  || die "dummy0 上 10.10.10.10 丢了，先执行 01-dummy0.sh"
ok "重置完成，可以执行 03-kernel-init.sh"
