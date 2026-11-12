#!/usr/bin/env bash
# ================= Sentinel Dashboard（单服务脚本，Kubernetes）=================
# 用法：./sentinel.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 清单：sentinel.yaml；公共逻辑：../lib/service.sh；kubectl 上下文默认 docker-desktop（可先 export K8S_CONTEXT=xxx）
SVC_TITLE="Sentinel Dashboard"
SVC_FILE="sentinel"
SVC_DEPLOYMENTS=(sentinel-dashboard)
SVC_PVCS=(sentinel-logs)
SVC_DEPS=()
SVC_INFO="Sentinel 控制台：http://127.0.0.1:8858"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
