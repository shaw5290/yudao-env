#!/usr/bin/env bash
# ================= MinIO（单服务脚本，Kubernetes）=================
# 用法：./minio.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 清单：minio.yaml；公共逻辑：../lib/service.sh；kubectl 上下文默认 docker-desktop（可先 export K8S_CONTEXT=xxx）
SVC_TITLE="MinIO"
SVC_FILE="minio"
SVC_DEPLOYMENTS=(minio)
SVC_PVCS=(minio-data)
SVC_DEPS=()
SVC_INFO="MinIO 控制台：http://127.0.0.1:9001，API：http://127.0.0.1:9000"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
