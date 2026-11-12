@echo off
chcp 936 >nul
REM ================= MySQL（单服务脚本，Docker Compose）=================
REM 用法：mysql.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 配置：mysql.yaml；公共逻辑：..\lib\service.bat
setlocal
set "SVC_TITLE=MySQL"
set "SVC_FILE=mysql"
set "SVC_SERVICES=mysql"
set "SVC_DEPS="
set "SVC_VOLUMES=mysql-data mysql-log"
set "SVC_INFO=MySQL：127.0.0.1:3306，root / .env 的 MYSQL_ROOT_PASSWORD"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
