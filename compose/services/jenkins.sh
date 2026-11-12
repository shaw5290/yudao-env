#!/usr/bin/env bash
# ================= Jenkins（单服务脚本，Docker Compose）=================
# 用法：./jenkins.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：jenkins.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="Jenkins"
SVC_FILE="jenkins"
SVC_SERVICES=(jenkins)
SVC_DEPS=()
SVC_VOLUMES=(jenkins-home)
SVC_INFO="Jenkins：http://127.0.0.1:8089"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
