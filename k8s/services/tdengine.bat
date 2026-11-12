@echo off
chcp 936 >nul
REM ================= TDengine（单服务脚本，Kubernetes）=================
REM 用法：tdengine.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 清单：tdengine.yaml；公共逻辑：..\lib\service.bat；kubectl 上下文默认 docker-desktop（可先 set K8S_CONTEXT=xxx）
setlocal
set "SVC_TITLE=TDengine"
set "SVC_FILE=tdengine"
set "SVC_DEPLOYMENTS=tdengine"
set "SVC_PVCS=tdengine-data tdengine-log"
set "SVC_DEPS="
set "SVC_INFO=TDengine REST/WebSocket：127.0.0.1:6041，首次使用需建库，见 config/tdengine/init-tdengine-db.md"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
