#!/usr/bin/env bash
# ================= Nacos（单服务脚本，Docker Compose）=================
# 用法：./nacos.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：nacos.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="Nacos"
SVC_FILE="nacos"
SVC_SERVICES=(nacos)
SVC_DEPS=(mysql)
SVC_VOLUMES=(nacos-data nacos-logs nacos-plugins)
SVC_INFO="Nacos 控制台：http://127.0.0.1:8080，客户端地址：127.0.0.1:8848"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
