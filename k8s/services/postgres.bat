@echo off
chcp 936 >nul
REM ================= PostgreSQL（单服务脚本，Kubernetes）=================
REM 用法：postgres.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 清单：postgres.yaml；公共逻辑：..\lib\service.bat；kubectl 上下文默认 docker-desktop（可先 set K8S_CONTEXT=xxx）
setlocal
set "SVC_TITLE=PostgreSQL"
set "SVC_FILE=postgres"
set "SVC_DEPLOYMENTS=postgres"
set "SVC_PVCS=postgres-data"
set "SVC_DEPS="
set "SVC_INFO=PostgreSQL：127.0.0.1:5432，账号见 .env 的 POSTGRES_USER / POSTGRES_PASSWORD"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
