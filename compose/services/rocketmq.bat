@echo off
chcp 936 >nul
REM ================= RocketMQ（namesrv + broker）（单服务脚本，Docker Compose）=================
REM 用法：rocketmq.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 配置：rocketmq.yaml；公共逻辑：..\lib\service.bat
setlocal
set "SVC_TITLE=RocketMQ（namesrv + broker）"
set "SVC_FILE=rocketmq"
set "SVC_SERVICES=rocketmq-namesrv rocketmq-broker"
set "SVC_DEPS="
set "SVC_VOLUMES=rocketmq-namesrv-logs rocketmq-broker-logs rocketmq-broker-store"
set "SVC_INFO=NameServer：127.0.0.1:9876，broker 需要先准备 config/rocketmq/broker/conf/broker.conf"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
