@echo off
chcp 936 >nul
REM ================= RocketMQ（namesrv + broker）（单服务脚本，Kubernetes）=================
REM 用法：rocketmq.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 清单：rocketmq.yaml；公共逻辑：..\lib\service.bat；kubectl 上下文默认 docker-desktop（可先 set K8S_CONTEXT=xxx）
setlocal
set "SVC_TITLE=RocketMQ（namesrv + broker）"
set "SVC_FILE=rocketmq"
set "SVC_DEPLOYMENTS=rocketmq-namesrv rocketmq-broker"
set "SVC_PVCS=rocketmq-namesrv-logs rocketmq-broker-logs rocketmq-broker-store"
set "SVC_DEPS="
set "SVC_INFO=NameServer：127.0.0.1:9876，broker 需要先准备 config/rocketmq/broker/conf/broker.conf"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
