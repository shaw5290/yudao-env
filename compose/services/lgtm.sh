#!/usr/bin/env bash
# ================= Grafana LGTM（单服务脚本，Docker Compose）=================
# 用法：./lgtm.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：lgtm.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="Grafana LGTM"
SVC_FILE="lgtm"
SVC_SERVICES=(lgtm)
SVC_DEPS=()
SVC_VOLUMES=(lgtm-data)
SVC_INFO="Grafana 控制台：http://127.0.0.1:3000（admin / admin），OTLP HTTP 上报地址：http://127.0.0.1:4318"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
