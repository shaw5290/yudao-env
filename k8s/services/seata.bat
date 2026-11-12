@echo off
chcp 936 >nul
REM ================= Seata Server（单服务脚本，Kubernetes）=================
REM 用法：seata.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 清单：seata.yaml；公共逻辑：..\lib\service.bat；kubectl 上下文默认 docker-desktop（可先 set K8S_CONTEXT=xxx）
setlocal
set "SVC_TITLE=Seata Server"
set "SVC_FILE=seata"
set "SVC_DEPLOYMENTS=seata-server"
set "SVC_PVCS="
set "SVC_DEPS=mysql nacos"
set "SVC_INFO=Seata TC：127.0.0.1:8091，注册到 Nacos 的 SEATA_GROUP"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
