@echo off
chcp 936 >nul
REM ================= MinIO（单服务脚本，Kubernetes）=================
REM 用法：minio.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 清单：minio.yaml；公共逻辑：..\lib\service.bat；kubectl 上下文默认 docker-desktop（可先 set K8S_CONTEXT=xxx）
setlocal
set "SVC_TITLE=MinIO"
set "SVC_FILE=minio"
set "SVC_DEPLOYMENTS=minio"
set "SVC_PVCS=minio-data"
set "SVC_DEPS="
set "SVC_INFO=MinIO 控制台：http://127.0.0.1:9001，API：http://127.0.0.1:9000"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
