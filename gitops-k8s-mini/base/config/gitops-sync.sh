#!/bin/sh
# GitOps 同步脚本：由 CronJob gitops-sync 执行（../services/gitops-sync.yaml）
# 【已停用】GitOps 改用 Flux CD + Gitee（见 ../../clusters/），configMapGenerator 中已注释掉本文件，保留备查
# 从 Gitea 浅克隆 GITOPS_BRANCH，对仓库内 GITOPS_PATH 目录执行 kubectl apply -k
# kubectl 使用 Pod 的 ServiceAccount gitops-sync（权限见 ../../bootstrap/gitops-sync-rbac.yaml）
set -eu

if [ -z "${GITOPS_REPO_URL:-}" ]; then
  echo "[跳过] Secret yudao-env 未配置 GITOPS_REPO_URL，本次不同步"
  exit 0
fi

BRANCH="${GITOPS_BRANCH:-main}"
TARGET="${GITOPS_PATH:-.}"
WORK=/work/repo

# Token 通过 HTTP 头传给 git，不拼进 URL，避免出现在日志和进程列表中
if [ -n "${GITOPS_GIT_TOKEN:-}" ]; then
  AUTH=`printf '%s:%s' "${GITOPS_GIT_USERNAME:-gitops}" "$GITOPS_GIT_TOKEN" | base64 | tr -d '\n'`
  set -- -c "http.extraHeader=Authorization: Basic $AUTH"
fi

git "$@" clone --quiet --depth 1 --branch "$BRANCH" "$GITOPS_REPO_URL" "$WORK"
echo "[信息] 同步 $BRANCH@`git -C "$WORK" rev-parse --short HEAD`，目录 $TARGET"

kubectl apply -k "$WORK/$TARGET"
echo "[完成] 同步结束"
