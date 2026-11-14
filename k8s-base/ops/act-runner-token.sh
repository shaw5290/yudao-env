#!/usr/bin/env bash
# ==================== 生成 Gitea runner 注册令牌并写入 Secret ====================
# 在服务器 /opt/yudao/k8s-base 下执行：bash ops/act-runner-token.sh
# 每次执行都会让 Gitea 生成一个新的注册令牌（旧的立即失效），但已注册 runner 的凭证在 /data/.runner 里，不受影响
set -euo pipefail

NS="${NS:-yudao-local}"

echo "从 Gitea 生成 runner 注册令牌 ..."
RAW="$(kubectl -n "$NS" exec deploy/gitea -- su git -c 'gitea actions generate-runner-token' 2>/dev/null || true)"
TOKEN="$(printf '%s\n' "$RAW" | tr -d '\r' | grep -E '^[A-Za-z0-9]{40}$' | tail -1 || true)"
if [[ -z "$TOKEN" ]]; then
  echo "没取到令牌，原始输出："
  printf '%s\n' "$RAW" | tail -5
  exit 1
fi

kubectl -n "$NS" create secret generic gitea-runner-token \
  --from-literal=token="$TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "Secret gitea-runner-token 已更新（不打印令牌）"

if kubectl -n "$NS" get deploy act-runner >/dev/null 2>&1; then
  kubectl -n "$NS" rollout restart deploy/act-runner
  echo "已重启 act-runner（已有注册信息时不会重复注册）"
fi
