#!/usr/bin/env bash
# ================= Grafana LGTM（单服务脚本，Kubernetes）=================
# 用法：./lgtm.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 清单：lgtm.yaml；公共逻辑：../lib/service.sh；kubectl 上下文默认 docker-desktop（可先 export K8S_CONTEXT=xxx）
SVC_TITLE="Grafana LGTM"
SVC_FILE="lgtm"
SVC_DEPLOYMENTS=(lgtm)
SVC_PVCS=(lgtm-data)
SVC_DEPS=()
SVC_INFO="Grafana 控制台：http://127.0.0.1:3000（admin / admin），OTLP HTTP 上报地址：http://127.0.0.1:4318"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
