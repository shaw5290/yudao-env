@echo off
chcp 936 >nul
REM ================= Nginx（单服务脚本，Kubernetes）=================
REM 用法：nginx.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 清单：nginx.yaml；公共逻辑：..\lib\service.bat；kubectl 上下文默认 docker-desktop（可先 set K8S_CONTEXT=xxx）
setlocal
set "SVC_TITLE=Nginx"
set "SVC_FILE=nginx"
set "SVC_DEPLOYMENTS=nginx"
set "SVC_PVCS="
set "SVC_DEPS="
set "SVC_INFO=Nginx：http://127.0.0.1:80"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
