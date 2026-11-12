@echo off
chcp 936 >nul
REM ================= Nacos（单服务脚本，Kubernetes）=================
REM 用法：nacos.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 清单：nacos.yaml；公共逻辑：..\lib\service.bat；kubectl 上下文默认 docker-desktop（可先 set K8S_CONTEXT=xxx）
setlocal
set "SVC_TITLE=Nacos"
set "SVC_FILE=nacos"
set "SVC_DEPLOYMENTS=nacos"
set "SVC_PVCS=nacos-data nacos-logs nacos-plugins"
set "SVC_DEPS=mysql"
set "SVC_INFO=Nacos 控制台：http://127.0.0.1:8080，客户端地址：127.0.0.1:8848"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
