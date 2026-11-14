#!/usr/bin/env bash
# ==================== 由 .env 创建 Secret yudao-env ====================
# 在服务器 /opt/yudao/k8s-base 下执行：bash ops/apply-env.sh
# .env 改了之后重跑本脚本，再重启受影响的工作负载（Gitea 读环境变量，不重启不生效）
# 不做 --dry-run 之外的校验：Secret 里多出的键无害，各清单按 secretKeyRef 只取自己的键
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$DIR/.env"
NS="${NS:-yudao-local}"

[[ -f "$ENV_FILE" ]] || { echo "缺少 $ENV_FILE，先执行 cp .env.temp .env 并填写"; exit 1; }
if grep -q CHANGE_ME "$ENV_FILE"; then
  echo "$ENV_FILE 里还有 CHANGE_ME，先填完："
  grep -n CHANGE_ME "$ENV_FILE"
  exit 1
fi

# 命名空间在这里先建，保证「先有 Secret、再 apply 工作负载」的顺序，Pod 不会因缺 Secret 反复重启
kubectl get namespace "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS"

kubectl -n "$NS" create secret generic yudao-env \
  --from-env-file="$ENV_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "--- Secret yudao-env 的键 ---"
kubectl -n "$NS" get secret yudao-env -o jsonpath='{.data}' | tr ',' '\n' | sed 's/[{}"]//g'
echo
echo "键已更新。Gitea 读的是环境变量，改了 ROOT_URL / SECRET_KEY 后需要重启："
echo "  kubectl -n $NS rollout restart deploy/gitea"
