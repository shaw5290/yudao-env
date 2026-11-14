#!/usr/bin/env bash
# ==================== 节点上的 containerd 放行 HTTP 镜像仓库 ====================
# 只在节点（k8s-master）上执行一次：bash bootstrap/containerd-registry.sh
# 原因：registry 是 HTTP，containerd 默认要求 HTTPS，不放行会报
#   failed to do request: http: server gave HTTP response to HTTPS client
# 固定地址 10.10.10.10 由 fixed-ip-k8s 的 dummy0 提供，换网不变，所以这里写死不需要跟着 IP 改
set -euo pipefail

REGISTRY="${REGISTRY:-10.10.10.10:5000}"
CERTS_D="/etc/containerd/certs.d/$REGISTRY"

sudo mkdir -p "$CERTS_D"
sudo tee "$CERTS_D/hosts.toml" >/dev/null <<EOF
# 由 yudao-env/k8s-base/bootstrap/containerd-registry.sh 生成
# 集群内镜像仓库只走 HTTP，且地址是 dummy0 的固定地址，不随换网变化
server = "http://$REGISTRY"

[host."http://$REGISTRY"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF

# config_path 必须是 /etc/containerd/certs.d（kubeadm 默认已经是），否则上面的 hosts.toml 不生效
if ! sudo grep -q "config_path = '/etc/containerd/certs.d'" /etc/containerd/config.toml; then
  echo "警告：/etc/containerd/config.toml 里 config_path 不是 /etc/containerd/certs.d，hosts.toml 不会生效"
  sudo grep -n config_path /etc/containerd/config.toml || true
fi

sudo systemctl restart containerd
sleep 5
sudo systemctl is-active containerd
echo "已放行 HTTP 仓库 $REGISTRY（certs.d 配置见 $CERTS_D/hosts.toml）"
