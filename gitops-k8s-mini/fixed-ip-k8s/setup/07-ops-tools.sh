#!/usr/bin/env bash
# ================= 07 安装运维脚本与开机自适应单元 =================
# 作用：
#   /usr/local/bin/k8s-info.sh        一屏看集群与网络状态
#   /usr/local/bin/k8s-allow-ip.sh    把当前（或指定）局域网 IP 加入 apiserver 证书 SAN
#   k8s-ip-autoadapt.service          开机自动执行上面那个，换路由器后 LAN 直连免手工
# 幂等：可重复执行。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$SCRIPT_DIR/../config"
OPS_DIR="$SCRIPT_DIR/../ops"

info() { echo -e "\n[信息] $*"; }
ok()   { echo "[成功] $*"; }
die()  { echo "[错误] $*" >&2; exit 1; }
s()    { if [ -n "${SUDO_PASS:-}" ]; then echo "$SUDO_PASS" | sudo -S -p '' "$@"; else sudo "$@"; fi; }

[ "$(id -u)" -ne 0 ] || die "不要用 root 运行，用有 sudo 权限的普通账号"
for f in k8s-info.sh k8s-allow-ip.sh; do
  [ -f "$OPS_DIR/$f" ] || die "找不到 $OPS_DIR/$f"
done
[ -f "$CONF_DIR/k8s-ip-autoadapt.service" ] || die "找不到 $CONF_DIR/k8s-ip-autoadapt.service"

info "安装运维脚本到 /usr/local/bin"
for f in k8s-info.sh k8s-allow-ip.sh; do
  s cp "$OPS_DIR/$f" "/usr/local/bin/$f"
  s chmod 755 "/usr/local/bin/$f"
  echo "  /usr/local/bin/$f"
done

info "安装开机自适应单元"
s cp "$CONF_DIR/k8s-ip-autoadapt.service" /etc/systemd/system/k8s-ip-autoadapt.service
s chmod 644 /etc/systemd/system/k8s-ip-autoadapt.service
s systemctl daemon-reload
s systemctl enable k8s-ip-autoadapt.service > /dev/null 2>&1
s systemctl start k8s-ip-autoadapt.service
s systemctl is-enabled k8s-ip-autoadapt.service | sed 's/^/  enabled: /'

info "当前状态"
s /usr/local/bin/k8s-info.sh
ok "完成"
