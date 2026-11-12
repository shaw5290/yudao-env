@echo off
chcp 936 >nul
REM ================= RabbitMQ（单服务脚本，Docker Compose）=================
REM 用法：rabbitmq.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 配置：rabbitmq.yaml；公共逻辑：..\lib\service.bat
setlocal
set "SVC_TITLE=RabbitMQ"
set "SVC_FILE=rabbitmq"
set "SVC_SERVICES=rabbitmq"
set "SVC_DEPS="
set "SVC_VOLUMES=rabbitmq-data"
set "SVC_INFO=管理控制台：http://127.0.0.1:15672（账号为 .env 的 RABBITMQ_USERNAME / RABBITMQ_PASSWORD），AMQP 地址：127.0.0.1:5672"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
