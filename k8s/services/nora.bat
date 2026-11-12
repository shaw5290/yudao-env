@echo off
chcp 936 >nul
REM ================= NORA 制品仓库（单服务脚本，Kubernetes）=================
REM 用法：nora.bat [up/down/restart/rebuild/status/logs]，不带参数时进入菜单
REM 清单：nora.yaml；公共逻辑：..\lib\service.bat；kubectl 上下文默认 docker-desktop（可先 set K8S_CONTEXT=xxx）
setlocal
set "SVC_TITLE=NORA 制品仓库"
set "SVC_FILE=nora"
set "SVC_DEPLOYMENTS=nora"
set "SVC_PVCS=nora-data"
set "SVC_DEPS="
set "SVC_INFO=Web UI：http://127.0.0.1:4000/ui/，镜像仓库：localhost:4000，Maven：http://127.0.0.1:4000/maven2/，npm：http://127.0.0.1:4000/npm/"
REM 开启鉴权时的 htpasswd：文件存在则启动前同步为 Secret
set "SVC_SECRET_NAME=nora-htpasswd"
set "SVC_SECRET_FILE=config\nora\auth\users.htpasswd"
set "SVC_SECRET_KEY=users.htpasswd"
call "%~dp0..\lib\service.bat" %*
exit /b %errorlevel%
