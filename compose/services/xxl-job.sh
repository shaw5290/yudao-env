#!/usr/bin/env bash
# ================= XXL-Job（单服务脚本，Docker Compose）=================
# 用法：./xxl-job.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：xxl-job.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="XXL-Job"
SVC_FILE="xxl-job"
SVC_SERVICES=(xxl-job-admin)
SVC_DEPS=(mysql)
SVC_VOLUMES=(xxl-job-logs)
SVC_INFO="调度中心：http://127.0.0.1:9090/xxl-job-admin"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
