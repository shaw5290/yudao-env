#!/usr/bin/env bash
# ================= TDengine（单服务脚本，Kubernetes）=================
# 用法：./tdengine.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 清单：tdengine.yaml；公共逻辑：../lib/service.sh；kubectl 上下文默认 docker-desktop（可先 export K8S_CONTEXT=xxx）
SVC_TITLE="TDengine"
SVC_FILE="tdengine"
SVC_DEPLOYMENTS=(tdengine)
SVC_PVCS=(tdengine-data tdengine-log)
SVC_DEPS=()
SVC_INFO="TDengine REST/WebSocket：127.0.0.1:6041，首次使用需建库，见 config/tdengine/init-tdengine-db.md"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
