#!/usr/bin/env bash
# ==================== 换网后更新 Gitea 的 ROOT_URL ====================
# 场景：这台机器的 IP 由路由器 DHCP 分配，换场地就变；ROOT_URL 写错会导致页面跳转、HTTP 克隆地址、Actions 回调全错
# 用法：sudo 不需要；在 /opt/yudao/k8s-base 下执行 bash ops/gitea-root-url.sh [IP]
#   不带参数时自动取默认路由的出口地址
# 集群内部（Flux 拉代码）用的是 Service 域名，不受影响，所以只需要改这一处
set -euo pipefail

NS="${NS:-yudao-local}"

if [[ $# -ge 1 ]]; then
  IP="$1"
else
  IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
fi
[[ -n "${IP:-}" ]] || { echo "取不到本机 IP，请手动传入：bash ops/gitea-root-url.sh 192.168.1.102"; exit 1; }

NEW_URL="http://$IP:3000/"
CUR="$(kubectl -n "$NS" get secret yudao-env -o jsonpath='{.data.GITEA__server__ROOT_URL}' | base64 -d)"

if [[ "$CUR" == "$NEW_URL" ]]; then
  echo "ROOT_URL 已经是 $NEW_URL，无需修改"
  exit 0
fi

kubectl -n "$NS" patch secret yudao-env --type merge \
  -p "{\"stringData\":{\"GITEA__server__ROOT_URL\":\"$NEW_URL\"}}"
# Gitea 只在启动时读环境变量生成 app.ini，必须重启才生效
kubectl -n "$NS" rollout restart deploy/gitea
kubectl -n "$NS" rollout status deploy/gitea --timeout=180s

echo "ROOT_URL: $CUR → $NEW_URL"
