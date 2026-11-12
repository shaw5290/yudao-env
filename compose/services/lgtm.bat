@echo off
chcp 936 >nul
REM ================= Grafana LGTM（单服务脚本，Docker Compose）=================
REM 用法：lgtm.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 配置：lgtm.yaml；公共逻辑：..\lib\service.bat
setlocal
set "SVC_TITLE=Grafana LGTM"
set "SVC_FILE=lgtm"
set "SVC_SERVICES=lgtm"
set "SVC_DEPS="
set "SVC_VOLUMES=lgtm-data"
set "SVC_INFO=Grafana 控制台：http://127.0.0.1:3000（admin / admin），OTLP HTTP 上报地址：http://127.0.0.1:4318"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
