@echo off
chcp 936 >nul
REM ================= Redis（单服务脚本，Kubernetes）=================
REM 用法：redis.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 清单：redis.yaml；公共逻辑：..\lib\service.bat；kubectl 上下文默认 docker-desktop（可先 set K8S_CONTEXT=xxx）
setlocal
set "SVC_TITLE=Redis"
set "SVC_FILE=redis"
set "SVC_DEPLOYMENTS=redis"
set "SVC_PVCS="
set "SVC_DEPS="
set "SVC_INFO=Redis：127.0.0.1:6379，密码为 .env 的 REDIS_PASSWORD"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
