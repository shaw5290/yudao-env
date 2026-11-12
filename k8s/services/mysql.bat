@echo off
chcp 936 >nul
REM ================= MySQL（单服务脚本，Kubernetes）=================
REM 用法：mysql.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 清单：mysql.yaml；公共逻辑：..\lib\service.bat；kubectl 上下文默认 docker-desktop（可先 set K8S_CONTEXT=xxx）
setlocal
set "SVC_TITLE=MySQL"
set "SVC_FILE=mysql"
set "SVC_DEPLOYMENTS=mysql"
set "SVC_PVCS=mysql-data mysql-log"
set "SVC_DEPS="
set "SVC_INFO=MySQL：127.0.0.1:3306，root / .env 的 MYSQL_ROOT_PASSWORD"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
