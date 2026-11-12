#!/usr/bin/env bash
# ================= MinIO（单服务脚本，Docker Compose）=================
# 用法：./minio.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：minio.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="MinIO"
SVC_FILE="minio"
SVC_SERVICES=(minio)
SVC_DEPS=()
SVC_VOLUMES=(minio-data)
SVC_INFO="MinIO 控制台：http://127.0.0.1:9001，API：http://127.0.0.1:9000"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
