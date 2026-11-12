#!/usr/bin/env bash
# ================= Redis（单服务脚本，Docker Compose）=================
# 用法：./redis.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：redis.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="Redis"
SVC_FILE="redis"
SVC_SERVICES=(redis)
SVC_DEPS=()
SVC_VOLUMES=()
SVC_INFO="Redis：127.0.0.1:6379，密码为 .env 的 REDIS_PASSWORD"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
