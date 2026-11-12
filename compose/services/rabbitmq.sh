#!/usr/bin/env bash
# ================= RabbitMQ（单服务脚本，Docker Compose）=================
# 用法：./rabbitmq.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：rabbitmq.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="RabbitMQ"
SVC_FILE="rabbitmq"
SVC_SERVICES=(rabbitmq)
SVC_DEPS=()
SVC_VOLUMES=(rabbitmq-data)
SVC_INFO="管理控制台：http://127.0.0.1:15672（账号为 .env 的 RABBITMQ_USERNAME / RABBITMQ_PASSWORD），AMQP 地址：127.0.0.1:5672"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
