#!/usr/bin/env bash
# ================= Seata Server（单服务脚本，Docker Compose）=================
# 用法：./seata.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：seata.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="Seata Server"
SVC_FILE="seata"
SVC_SERVICES=(seata-server)
SVC_DEPS=(mysql nacos)
SVC_VOLUMES=()
SVC_INFO="Seata TC：127.0.0.1:8091，注册到 Nacos 的 SEATA_GROUP"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
