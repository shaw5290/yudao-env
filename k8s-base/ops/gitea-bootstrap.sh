#!/usr/bin/env bash
# ==================== Gitea 初始化：管理员、组织、仓库、Flux 令牌 ====================
# 在服务器 /opt/yudao/k8s-base 下执行：bash ops/gitea-bootstrap.sh
# 幂等：管理员已存在不会重复创建；令牌生成过就复用 .gitea-token（Gitea 只显示一次，丢了只能删掉重建）
# 注意：gitea 命令行拒绝以 root 运行，容器里必须用 git 用户（uid 1000），所以统一走 su git -c
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="${NS:-yudao-local}"
GITEA_URL="${GITEA_URL:-http://127.0.0.1:3000}"   # hostPort 直连节点本机，不依赖局域网 IP
ADMIN_USER="${ADMIN_USER:-devops}"
ADMIN_PASS="${ADMIN_PASS:-devops123}"
ADMIN_EMAIL="${ADMIN_EMAIL:-devops@yudao.local}"
ORG="${ORG:-yudao}"
REPOS="${REPOS:-yudao-gitops yudao-ui-admin-vben}"
TOKEN_FILE="$DIR/.gitea-token"

# 容器内以 git 用户执行 gitea 子命令，并屏蔽 kubectl 的 "Defaulted container" 提示
gitea_cli() {
  kubectl -n "$NS" exec deploy/gitea -- su git -c "$1" 2>/dev/null
}

echo "===== 1. 等 Gitea 就绪 ====="
for i in $(seq 1 60); do
  if curl -fsS --max-time 3 "$GITEA_URL/api/healthz" >/dev/null 2>&1; then echo "Gitea 已就绪"; break; fi
  if [[ $i -eq 60 ]]; then echo "Gitea 5 分钟未就绪，先看 kubectl -n $NS logs deploy/gitea"; exit 1; fi
  sleep 5
done

echo "===== 2. 管理员 $ADMIN_USER ====="
if gitea_cli "gitea admin user list" | awk 'NR>1 {print $2}' | grep -qx "$ADMIN_USER"; then
  echo "管理员已存在，跳过"
else
  gitea_cli "gitea admin user create --admin --username $ADMIN_USER --password $ADMIN_PASS --email $ADMIN_EMAIL --must-change-password=false"
  echo "已创建管理员：$ADMIN_USER / $ADMIN_PASS"
fi

echo "===== 3. 访问令牌（Flux 拉代码 + 镜像自动更新回写）====="
# 兼容旧版本输出「Access token was successfully created: <token>」：文件里若带前缀先剥掉
if [[ -s "$TOKEN_FILE" ]] && grep -q 'created:' "$TOKEN_FILE"; then
  sed -i 's/.*created: *//' "$TOKEN_FILE"
fi
if [[ -s "$TOKEN_FILE" ]]; then
  echo "复用已有令牌：$TOKEN_FILE"
else
  # write:repository：Flux 只读拉取够用，image-automation 还要把新 Tag 提交回仓库
  raw=$(gitea_cli "gitea admin user generate-access-token --username $ADMIN_USER --token-name flux --scopes write:repository")
  token=$(printf '%s\n' "$raw" | tr -d '\r' | sed -n 's/.*created: *//p' | tail -1)
  [[ -z "$token" ]] && token=$(printf '%s\n' "$raw" | tr -d '\r' | awk 'NF{last=$NF} END{print last}')
  if [[ -z "${token:-}" ]]; then echo "生成令牌失败（同名令牌可能已存在，先在 Gitea 网页删除 token flux 再重跑）"; exit 1; fi
  printf '%s\n' "$token" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  echo "已生成令牌并写入 $TOKEN_FILE"
fi

TOKEN="$(cat "$TOKEN_FILE")"

echo "===== 4. 组织 $ORG ====="
# 建组织 / 建仓库需要 read:organization、write:organization 等权限，Flux 用的 write:repository 令牌不够
# 这里临时生成一个 all 权限令牌专门做引导，结束后立即删除，不给 Flux 留下过大权限
gitea_cli "gitea admin user delete-access-token --username $ADMIN_USER --token-name bootstrap" >/dev/null 2>&1 || true
BOOT_RAW=$(gitea_cli "gitea admin user generate-access-token --username $ADMIN_USER --token-name bootstrap --scopes all")
BOOT_TOKEN=$(printf '%s\n' "$BOOT_RAW" | tr -d '\r' | sed -n 's/.*created: *//p' | tail -1)
[[ -z "$BOOT_TOKEN" ]] && BOOT_TOKEN=$(printf '%s\n' "$BOOT_RAW" | tr -d '\r' | awk 'NF{last=$NF} END{print last}')
[[ -n "$BOOT_TOKEN" ]] || { echo "引导令牌生成失败"; exit 1; }

api() { curl -sS -H "Authorization: token $BOOT_TOKEN" -H 'Content-Type: application/json' "$@"; }

code=$(api -o /dev/null -w '%{http_code}' -X POST -d "{\"username\":\"$ORG\",\"visibility\":\"private\"}" "$GITEA_URL/api/v1/orgs")
case "$code" in
  201) echo "已创建组织 $ORG" ;;
  422) echo "组织 $ORG 已存在，跳过" ;;
  *)   echo "创建组织返回 $code"; api "$GITEA_URL/api/v1/orgs/$ORG" | head -3 ;;
esac

echo "===== 5. 仓库 ====="
for r in $REPOS; do
  code=$(api -o /dev/null -w '%{http_code}' -X POST \
    -d "{\"name\":\"$r\",\"private\":true,\"default_branch\":\"feature/dev\",\"auto_init\":false}" \
    "$GITEA_URL/api/v1/orgs/$ORG/repos")
  case "$code" in
    201) echo "已创建 $ORG/$r" ;;
    409) echo "$ORG/$r 已存在，跳过" ;;
    *)   echo "创建 $ORG/$r 返回 $code" ;;
  esac
done

# 引导令牌用完即删，避免长期留一个 all 权限的令牌
gitea_cli "gitea admin user delete-access-token --username $ADMIN_USER --token-name bootstrap" >/dev/null 2>&1 || true
echo "已删除引导令牌"

echo
echo "===== 完成 ====="
echo "Gitea: $GITEA_URL  （管理员 $ADMIN_USER / $ADMIN_PASS）"
for r in $REPOS; do echo "仓库:  $GITEA_URL/$ORG/$r.git"; done
echo "令牌:  $TOKEN_FILE"
