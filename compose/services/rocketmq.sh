#!/usr/bin/env bash
# ================= RocketMQ（namesrv + broker）（单服务脚本，Docker Compose）=================
# 用法：./rocketmq.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：rocketmq.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="RocketMQ（namesrv + broker）"
SVC_FILE="rocketmq"
SVC_SERVICES=(rocketmq-namesrv rocketmq-broker)
SVC_DEPS=()
SVC_VOLUMES=(rocketmq-namesrv-logs rocketmq-broker-logs rocketmq-broker-store)
SVC_INFO="NameServer：127.0.0.1:9876，broker 需要先准备 config/rocketmq/broker/conf/broker.conf"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
