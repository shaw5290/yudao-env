@echo off
chcp 936 >nul
REM ================= TDengine（单服务脚本，Docker Compose）=================
REM 用法：tdengine.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 配置：tdengine.yaml；公共逻辑：..\lib\service.bat
setlocal
set "SVC_TITLE=TDengine"
set "SVC_FILE=tdengine"
set "SVC_SERVICES=tdengine"
set "SVC_DEPS="
set "SVC_VOLUMES=tdengine-data tdengine-log"
set "SVC_INFO=TDengine REST/WebSocket：127.0.0.1:6041，首次使用需建库，见 config/tdengine/init-tdengine-db.md"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
