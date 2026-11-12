@echo off
chcp 936 >nul
REM ================= Redis（单服务脚本，Docker Compose）=================
REM 用法：redis.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 配置：redis.yaml；公共逻辑：..\lib\service.bat
setlocal
set "SVC_TITLE=Redis"
set "SVC_FILE=redis"
set "SVC_SERVICES=redis"
set "SVC_DEPS="
set "SVC_VOLUMES="
set "SVC_INFO=Redis：127.0.0.1:6379，密码为 .env 的 REDIS_PASSWORD"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
