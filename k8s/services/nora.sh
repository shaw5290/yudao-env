#!/usr/bin/env bash
# ================= NORA 制品仓库（单服务脚本，Kubernetes）=================
# 用法：./nora.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 清单：nora.yaml；公共逻辑：../lib/service.sh；kubectl 上下文默认 docker-desktop（可先 export K8S_CONTEXT=xxx）
SVC_TITLE="NORA 制品仓库"
SVC_FILE="nora"
SVC_DEPLOYMENTS=(nora)
SVC_PVCS=(nora-data)
SVC_DEPS=()
SVC_INFO="Web UI：http://127.0.0.1:4000/ui/，镜像仓库：localhost:4000，Maven：http://127.0.0.1:4000/maven2/，npm：http://127.0.0.1:4000/npm/"
# 开启鉴权时的 htpasswd：文件存在则启动前同步为 Secret
SVC_SECRET_NAME="nora-htpasswd"
SVC_SECRET_FILE="config/nora/auth/users.htpasswd"
SVC_SECRET_KEY="users.htpasswd"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
