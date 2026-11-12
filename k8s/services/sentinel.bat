@echo off
chcp 936 >nul
REM ================= Sentinel Dashboard（单服务脚本，Kubernetes）=================
REM 用法：sentinel.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 清单：sentinel.yaml；公共逻辑：..\lib\service.bat；kubectl 上下文默认 docker-desktop（可先 set K8S_CONTEXT=xxx）
setlocal
set "SVC_TITLE=Sentinel Dashboard"
set "SVC_FILE=sentinel"
set "SVC_DEPLOYMENTS=sentinel-dashboard"
set "SVC_PVCS=sentinel-logs"
set "SVC_DEPS="
set "SVC_INFO=Sentinel 控制台：http://127.0.0.1:8858"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
