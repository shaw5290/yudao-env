@echo off
chcp 936 >nul
REM ================= NORA 制品仓库（单服务脚本，Docker Compose）=================
REM 用法：nora.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 配置：nora.yaml；公共逻辑：..\lib\service.bat
setlocal
set "SVC_TITLE=NORA 制品仓库"
set "SVC_FILE=nora"
set "SVC_SERVICES=nora"
set "SVC_DEPS="
set "SVC_VOLUMES=nora-data"
set "SVC_INFO=Web UI：http://127.0.0.1:4000/ui/，镜像仓库：localhost:4000，Maven：http://127.0.0.1:4000/maven2/，npm：http://127.0.0.1:4000/npm/"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
