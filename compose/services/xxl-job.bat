@echo off
chcp 936 >nul
REM ================= XXL-Job（单服务脚本，Docker Compose）=================
REM 用法：xxl-job.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 配置：xxl-job.yaml；公共逻辑：..\lib\service.bat
setlocal
set "SVC_TITLE=XXL-Job"
set "SVC_FILE=xxl-job"
set "SVC_SERVICES=xxl-job-admin"
set "SVC_DEPS=mysql"
set "SVC_VOLUMES=xxl-job-logs"
set "SVC_INFO=调度中心：http://127.0.0.1:9090/xxl-job-admin"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
