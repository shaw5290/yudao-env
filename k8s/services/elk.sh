#!/usr/bin/env bash
# ================= ELK（Elasticsearch + Logstash + Kibana）（单服务脚本，Kubernetes）=================
# 用法：./elk.sh [up|down|restart|rebuild|status|logs]，不带参数时进入菜单
# 清单：elk.yaml；公共逻辑：../lib/service.sh；kubectl 上下文默认 docker-desktop（可先 export K8S_CONTEXT=xxx）
SVC_TITLE="ELK（Elasticsearch + Logstash + Kibana）"
SVC_FILE="elk"
SVC_DEPLOYMENTS=(elasticsearch logstash kibana)
SVC_PVCS=(elasticsearch-data)
SVC_DEPS=()
SVC_INFO="Kibana 控制台：http://127.0.0.1:5601，应用上报地址（Logstash）：127.0.0.1:5044，首次启动需要 1~2 分钟"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/service.sh" "$@"
