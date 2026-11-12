#!/usr/bin/env bash
# ================= Sentinel Dashboard（单服务脚本，Docker Compose）=================
# 用法：./sentinel.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：sentinel.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="Sentinel Dashboard"
SVC_FILE="sentinel"
SVC_SERVICES=(sentinel-dashboard)
SVC_DEPS=()
SVC_VOLUMES=(sentinel-logs)
SVC_INFO="Sentinel 控制台：http://127.0.0.1:8858"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
