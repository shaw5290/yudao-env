#!/usr/bin/env bash
# ================= 01 建立 dummy0 固定地址（控制面身份 10.10.10.10/32）=================
# 作用：给本机加一块永不变化的虚拟网卡，集群的 apiserver / etcd / kubelet 节点地址都绑它，
#       局域网 IP（ens18 的 DHCP 地址）怎么变都不影响集群。
# 幂等：可重复执行。
# 用法：bash 01-dummy0.sh              # 交互式 sudo（先 sudo -v）
#       SUDO_PASS=xxx bash 01-dummy0.sh # 无人值守
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$SCRIPT_DIR/../config"

info() { echo -e "\n[信息] $*"; }
ok()   { echo "[成功] $*"; }
die()  { echo "[错误] $*" >&2; exit 1; }
s()    { if [ -n "${SUDO_PASS:-}" ]; then echo "$SUDO_PASS" | sudo -S -p '' "$@"; else sudo "$@"; fi; }

[ "$(id -u)" -ne 0 ] || die "不要用 root 运行，用有 sudo 权限的普通账号"
[ -f "$CONF_DIR/k8s-dummy0.service" ] || die "找不到 $CONF_DIR/k8s-dummy0.service"
[ -f "$CONF_DIR/k8s-dummy.conf" ] || die "找不到 $CONF_DIR/k8s-dummy.conf"

info "安装 dummy 内核模块加载项与 systemd 单元"
s cp "$CONF_DIR/k8s-dummy0.service" /etc/systemd/system/k8s-dummy0.service
s cp "$CONF_DIR/k8s-dummy.conf" /etc/modules-load.d/k8s-dummy.conf
s chmod 644 /etc/systemd/system/k8s-dummy0.service /etc/modules-load.d/k8s-dummy.conf
s systemctl daemon-reload
s systemctl enable --now k8s-dummy0.service

info "校验"
s systemctl is-enabled k8s-dummy0.service | sed 's/^/  enabled: /'
s systemctl is-active k8s-dummy0.service | sed 's/^/  active:  /'
ip -4 -o addr show dummy0 | awk '{print "  地址: "$4}'

ip -4 -o addr show dummy0 2>/dev/null | grep -q '10\.10\.10\.10' \
  || die "dummy0 上没有 10.10.10.10/32，检查 journalctl -u k8s-dummy0"

# dummy 网卡不回 ICMP，ping 不通是正常现象；只要路由表把它识别为本机地址即可
ip route get 10.10.10.10 | grep -q 'local 10.10.10.10' \
  && ok "10.10.10.10 已被识别为本机地址（dummy 不回 ping，属正常）" \
  || die "路由表里没有 10.10.10.10 的 local 路由"
