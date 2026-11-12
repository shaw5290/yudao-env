#!/usr/bin/env bash
# ================= PostgreSQL（单服务脚本，Docker Compose）=================
# 用法：./postgres.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：postgres.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="PostgreSQL"
SVC_FILE="postgres"
SVC_SERVICES=(postgres)
SVC_DEPS=()
SVC_VOLUMES=(postgres-data postgres-log)
SVC_INFO="PostgreSQL：127.0.0.1:5432，账号见 .env 的 POSTGRES_USER / POSTGRES_PASSWORD"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
