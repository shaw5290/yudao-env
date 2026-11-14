#!/bin/sh
# ==================== act_runner 容器启动脚本 ====================
# 由 ../kustomization.yaml 的 configMapGenerator 挂到 /config/entrypoint.sh
# 只做三件事：等 dind 可用 → 首次启动时注册 runner（结果写 PVC）→ 前台跑 daemon
set -e

mkdir -p /data/work

echo "等待 dind (tcp://127.0.0.1:2375) 就绪 ..."
i=0
until /docker-bin/docker info >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge 90 ]; then
    echo "dind 180 秒未就绪，查看 kubectl logs deploy/act-runner -c dind"
    exit 1
  fi
  sleep 2
done
echo "dind 已就绪"

# /data/.runner 存在说明已经注册过，PVC 保留了注册凭证，不能重复注册
if [ ! -f /data/.runner ]; then
  echo "首次启动，向 Gitea 注册 runner：$RUNNER_NAME"
  act_runner register \
    --no-interactive \
    --instance "$GITEA_URL" \
    --token "$RUNNER_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "ubuntu-latest:host" \
    --config /config/config.yaml
else
  echo "已有注册信息，跳过注册"
fi

exec act_runner daemon --config /config/config.yaml
