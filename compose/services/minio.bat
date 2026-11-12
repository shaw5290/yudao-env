@echo off
chcp 936 >nul
REM ================= MinIO（单服务脚本，Docker Compose）=================
REM 用法：minio.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 配置：minio.yaml；公共逻辑：..\lib\service.bat
setlocal
set "SVC_TITLE=MinIO"
set "SVC_FILE=minio"
set "SVC_SERVICES=minio"
set "SVC_DEPS="
set "SVC_VOLUMES=minio-data"
set "SVC_INFO=MinIO 控制台：http://127.0.0.1:9001，API：http://127.0.0.1:9000"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
