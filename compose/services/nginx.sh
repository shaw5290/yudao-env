#!/usr/bin/env bash
# ================= Nginx（单服务脚本，Docker Compose）=================
# 用法：./nginx.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：nginx.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="Nginx"
SVC_FILE="nginx"
SVC_SERVICES=(nginx)
SVC_DEPS=()
SVC_VOLUMES=()
SVC_INFO="Nginx：http://127.0.0.1:80"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
