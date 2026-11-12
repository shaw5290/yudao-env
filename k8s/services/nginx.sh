#!/usr/bin/env bash
# ================= Nginx（单服务脚本，Kubernetes）=================
# 用法：./nginx.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 清单：nginx.yaml；公共逻辑：../lib/service.sh；kubectl 上下文默认 docker-desktop（可先 export K8S_CONTEXT=xxx）
SVC_TITLE="Nginx"
SVC_FILE="nginx"
SVC_DEPLOYMENTS=(nginx)
SVC_PVCS=()
SVC_DEPS=()
SVC_INFO="Nginx：http://127.0.0.1:80"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
