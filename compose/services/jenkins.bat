@echo off
chcp 936 >nul
REM ================= Jenkins（单服务脚本，Docker Compose）=================
REM 用法：jenkins.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 配置：jenkins.yaml；公共逻辑：..\lib\service.bat
setlocal
set "SVC_TITLE=Jenkins"
set "SVC_FILE=jenkins"
set "SVC_SERVICES=jenkins"
set "SVC_DEPS="
set "SVC_VOLUMES=jenkins-home"
set "SVC_INFO=Jenkins：http://127.0.0.1:8089"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
