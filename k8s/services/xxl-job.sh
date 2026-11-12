#!/usr/bin/env bash
# ================= XXL-Job（单服务脚本，Kubernetes）=================
# 用法：./xxl-job.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 清单：xxl-job.yaml；公共逻辑：../lib/service.sh；kubectl 上下文默认 docker-desktop（可先 export K8S_CONTEXT=xxx）
SVC_TITLE="XXL-Job"
SVC_FILE="xxl-job"
SVC_DEPLOYMENTS=(xxl-job-admin)
SVC_PVCS=(xxl-job-logs)
SVC_DEPS=(mysql)
SVC_INFO="调度中心：http://127.0.0.1:9090/xxl-job-admin"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
