#!/usr/bin/env bash
# ================= MySQL（单服务脚本，Docker Compose）=================
# 用法：./mysql.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：mysql.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="MySQL"
SVC_FILE="mysql"
SVC_SERVICES=(mysql)
SVC_DEPS=()
SVC_VOLUMES=(mysql-data mysql-log)
SVC_INFO="MySQL：127.0.0.1:3306，root / .env 的 MYSQL_ROOT_PASSWORD"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
