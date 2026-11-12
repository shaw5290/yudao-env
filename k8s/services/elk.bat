@echo off
chcp 936 >nul
REM ================= ELK（Elasticsearch + Logstash + Kibana）（单服务脚本，Kubernetes）=================
REM 用法：elk.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 清单：elk.yaml；公共逻辑：..\lib\service.bat；kubectl 上下文默认 docker-desktop（可先 set K8S_CONTEXT=xxx）
setlocal
set "SVC_TITLE=ELK（Elasticsearch + Logstash + Kibana）"
set "SVC_FILE=elk"
set "SVC_DEPLOYMENTS=elasticsearch logstash kibana"
set "SVC_PVCS=elasticsearch-data"
set "SVC_DEPS="
set "SVC_INFO=Kibana 控制台：http://127.0.0.1:5601，应用上报地址（Logstash）：127.0.0.1:5044，首次启动需要 1~2 分钟"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
