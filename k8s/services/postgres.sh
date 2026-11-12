#!/usr/bin/env bash
# ================= PostgreSQL（单服务脚本，Kubernetes）=================
# 用法：./postgres.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 清单：postgres.yaml；公共逻辑：../lib/service.sh；kubectl 上下文默认 docker-desktop（可先 export K8S_CONTEXT=xxx）
SVC_TITLE="PostgreSQL"
SVC_FILE="postgres"
SVC_DEPLOYMENTS=(postgres)
SVC_PVCS=(postgres-data)
SVC_DEPS=()
SVC_INFO="PostgreSQL：127.0.0.1:5432，账号见 .env 的 POSTGRES_USER / POSTGRES_PASSWORD"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
