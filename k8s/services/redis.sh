#!/usr/bin/env bash
# ================= Redis（单服务脚本，Kubernetes）=================
# 用法：./redis.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 清单：redis.yaml；公共逻辑：../lib/service.sh；kubectl 上下文默认 docker-desktop（可先 export K8S_CONTEXT=xxx）
SVC_TITLE="Redis"
SVC_FILE="redis"
SVC_DEPLOYMENTS=(redis)
SVC_PVCS=()
SVC_DEPS=()
SVC_INFO="Redis：127.0.0.1:6379，密码为 .env 的 REDIS_PASSWORD"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
