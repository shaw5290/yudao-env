#!/usr/bin/env bash
# ================= Jenkins（单服务脚本，Kubernetes）=================
# 用法：./jenkins.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 清单：jenkins.yaml；公共逻辑：../lib/service.sh；kubectl 上下文默认 docker-desktop（可先 export K8S_CONTEXT=xxx）
SVC_TITLE="Jenkins"
SVC_FILE="jenkins"
SVC_DEPLOYMENTS=(jenkins)
SVC_PVCS=(jenkins-home)
SVC_DEPS=()
SVC_INFO="Jenkins：http://127.0.0.1:8089"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
