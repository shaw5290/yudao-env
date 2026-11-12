#!/usr/bin/env bash
# ================= NORA 制品仓库（单服务脚本，Docker Compose）=================
# 用法：./nora.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 配置：nora.yaml；公共逻辑：../lib/service.sh
SVC_TITLE="NORA 制品仓库"
SVC_FILE="nora"
SVC_SERVICES=(nora)
SVC_DEPS=()
SVC_VOLUMES=(nora-data)
SVC_INFO="Web UI：http://127.0.0.1:4000/ui/，镜像仓库：localhost:4000，Maven：http://127.0.0.1:4000/maven2/，npm：http://127.0.0.1:4000/npm/"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
