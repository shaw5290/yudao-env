#!/usr/bin/env bash
# ================= MySQL（单服务脚本，Kubernetes）=================
# 用法：./mysql.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 清单：mysql.yaml；公共逻辑：../lib/service.sh；kubectl 上下文默认 docker-desktop（可先 export K8S_CONTEXT=xxx）
SVC_TITLE="MySQL"
SVC_FILE="mysql"
SVC_DEPLOYMENTS=(mysql)
SVC_PVCS=(mysql-data mysql-log)
SVC_DEPS=()
SVC_INFO="MySQL：127.0.0.1:3306，root / .env 的 MYSQL_ROOT_PASSWORD"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
