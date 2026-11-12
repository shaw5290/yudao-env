#!/usr/bin/env bash
# ================= Nacos（单服务脚本，Kubernetes）=================
# 用法：./nacos.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 清单：nacos.yaml；公共逻辑：../lib/service.sh；kubectl 上下文默认 docker-desktop（可先 export K8S_CONTEXT=xxx）
SVC_TITLE="Nacos"
SVC_FILE="nacos"
SVC_DEPLOYMENTS=(nacos)
SVC_PVCS=(nacos-data nacos-logs nacos-plugins)
SVC_DEPS=(mysql)
SVC_INFO="Nacos 控制台：http://127.0.0.1:8080，客户端地址：127.0.0.1:8848"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
