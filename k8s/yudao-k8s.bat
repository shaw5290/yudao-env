@echo off
REM ============ 编码：二选一 ============
chcp 936 >nul
REM chcp 65001 >nul
REM ================= yudao 本地依赖环境：多服务菜单（Kubernetes）=================
REM 核心 / 全部中间件按方案 k8s\schemes\core、middleware 部署；单个中间件的启停调用 k8s\services\{名称}.bat

setlocal enabledelayedexpansion
REM 以仓库根目录为工作目录（.env、backups 都在根目录）
cd /d "%~dp0.."
REM ---- 修复环境 PATH 缺失 System32 导致 chcp/where 不可用（仅本进程生效，不改系统全局环境） ----
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0\;%PATH%"

set NAMESPACE=yudao
set ENV_FILE=.env
set SCHEMES_DIR=k8s\schemes
set SVC_DIR=k8s\services
REM 所有 kubectl 调用都显式指定上下文，避免误操作当前默认上下文指向的其他集群；用其他集群时先 set K8S_CONTEXT=xxx
if not defined K8S_CONTEXT set K8S_CONTEXT=docker-desktop
set "KC=kubectl --context %K8S_CONTEXT%"
REM NORA 开启鉴权时使用的 htpasswd（不提交），存在时同步为 Secret nora-htpasswd
set NORA_HTPASSWD=config\nora\auth\users.htpasswd
REM 核心 / 中间件 Deployment（与同名 Service 一起启停；新增服务时同步这两行和下面的菜单编号）
set CORE_DEPLOYMENTS=mysql redis nacos tdengine nginx
set MIDDLEWARE_DEPLOYMENTS=jenkins minio rocketmq-namesrv rocketmq-broker xxl-job-admin seata-server sentinel-dashboard postgres lgtm elasticsearch logstash kibana rabbitmq nora
REM 菜单编号 → 单服务脚本 %SVC_DIR%\{名称}.bat（启动 n，停止 n+10）
set "START_11=minio"
set "STOP_21=minio"
set "START_12=rocketmq"
set "STOP_22=rocketmq"
set "START_13=xxl-job"
set "STOP_23=xxl-job"
set "START_14=seata"
set "STOP_24=seata"
set "START_15=sentinel"
set "STOP_25=sentinel"
set "START_16=jenkins"
set "STOP_26=jenkins"
set "START_17=postgres"
set "STOP_27=postgres"
set "START_19=lgtm"
set "STOP_29=lgtm"
set "START_41=elk"
set "STOP_51=elk"
set "START_42=rabbitmq"
set "STOP_52=rabbitmq"
set "START_43=nora"
set "STOP_53=nora"

REM ---- 数据库备份配置 ----
set DB_DEPLOY=deploy/mysql
set DB_USER=root
set DB_PASSWORD=123456
set BACKUP_DIR=backups
REM 默认排除的系统库
set DB_EXCLUDE=information_schema mysql performance_schema sys

REM ---- 前置检查 ----
kubectl version --client >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 kubectl 命令，请确认 Docker Desktop 的 Kubernetes 已启用（设置 → Kubernetes → Enable Kubernetes）。
    goto :end
)
kubectl config get-contexts %K8S_CONTEXT% >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 kubectl 上下文 %K8S_CONTEXT%。请在 Docker Desktop 中启用 Kubernetes；使用其他集群时先 set K8S_CONTEXT=上下文名。
    goto :end
)
if not exist "%ENV_FILE%" (
    echo [错误] 未找到 %ENV_FILE%，请先 copy .env.temp .env 并按需修改
    goto :end
)

:menu
cls
echo ========================================
echo   yudao-cloud Kubernetes 管理菜单
echo   上下文: %K8S_CONTEXT%    命名空间: %NAMESPACE%    方案: %SCHEMES_DIR%\core / middleware
echo ========================================
echo   核心服务：
echo     1. 启动核心    (nginx/mysql/redis/nacos/tdengine)
echo     2. 停止全部    (含所有已启用中间件，保留数据卷)
echo     3. 重启核心    (rollout restart)
echo     4. 查看状态    (所有 Pod / Service)
echo     5. 查看日志    (输入 Deployment 名)
echo     6. 强制重建    (重新 apply 全部核心清单 + 重启)
echo     10. 启动核心+PostgreSQL (核心服务再加上 PostgreSQL)
echo.
echo   中间件（单独启停）：
echo     11. 启动 MinIO          21. 停止 MinIO
echo     12. 启动 RocketMQ       22. 停止 RocketMQ
echo     13. 启动 XXL-Job        23. 停止 XXL-Job
echo     14. 启动 Seata          24. 停止 Seata
echo     15. 启动 Sentinel       25. 停止 Sentinel
echo     16. 启动 Jenkins        26. 停止 Jenkins
echo     17. 启动 PostgreSQL     27. 停止 PostgreSQL
echo     19. 启动 Grafana LGTM   29. 停止 Grafana LGTM
echo     41. 启动 ELK            51. 停止 ELK
echo     42. 启动 RabbitMQ       52. 停止 RabbitMQ
echo     43. 启动 NORA           53. 停止 NORA
echo.
echo     7. 启动全部中间件       8. 停止全部中间件
echo     9. 清空所有数据卷 (PVC，危险！会删除所有数据)
echo.
echo   数据库（备份 / 还原）：
echo     31. 备份全部库（自动排除系统库）
echo     32. 还原指定文件
echo     33. 查看备份列表
echo     34. 查看当前数据库
echo.
echo     0. 退出
echo ========================================
set "choice="
set /p choice=请输入选项并回车:

if "%choice%"=="1" goto :start
if "%choice%"=="2" goto :stop
if "%choice%"=="3" goto :restart
if "%choice%"=="4" goto :status
if "%choice%"=="5" goto :logs
if "%choice%"=="6" goto :rebuild
if "%choice%"=="7" goto :profile_all_up
if "%choice%"=="8" goto :profile_all_down
if "%choice%"=="9" goto :wipe_pvc
if "%choice%"=="10" goto :start_with_postgres
if "%choice%"=="31" goto :db_backup
if "%choice%"=="32" goto :db_restore
if "%choice%"=="33" goto :db_list
if "%choice%"=="34" goto :db_show
if "%choice%"=="0" goto :quit
if defined START_%choice% goto :svc_start
if defined STOP_%choice% goto :svc_stop

echo.
echo [提示] 无效选项，请重新输入。
timeout /t 1 >nul
goto :menu

REM ================= 方案部署：namespace → Secret → kustomize 渲染 → apply =================
REM 方案引用了目录外的 services\*.yaml，必须加 --load-restrictor LoadRestrictionsNone，所以不用 apply -k
:apply_scheme
%KC% apply -f k8s\base\namespace.yaml
%KC% create secret generic yudao-env --from-env-file=%ENV_FILE% -n %NAMESPACE% --dry-run=client -o yaml | %KC% apply -f -
if exist "%NORA_HTPASSWD%" (
    %KC% create secret generic nora-htpasswd --from-file=users.htpasswd=%NORA_HTPASSWD% -n %NAMESPACE% --dry-run=client -o yaml | %KC% apply -f -
)
%KC% kustomize --load-restrictor LoadRestrictionsNone %SCHEMES_DIR%\%~1 | %KC% apply -f -
exit /b

REM ================= 核心 =================
:start
echo.
echo [信息] 正在启动核心服务...
call :apply_scheme core
%KC% get pods -n %NAMESPACE%
echo.
pause
goto :menu

:stop
echo.
set /p confirm=确认停止所有 Deployment/Service（保留数据卷，含中间件）？(Y/N):
if /i not "%confirm%"=="Y" (
    echo [取消] 已取消。
    timeout /t 1 >nul
    goto :menu
)
%KC% delete deployment,service --all -n %NAMESPACE% --ignore-not-found
echo.
echo [完成] 已全部停止（PVC 数据卷仍保留）。
pause
goto :menu

:wipe_pvc
echo.
echo [警告] 此操作会删除命名空间 %NAMESPACE% 下所有 PVC（mysql-data、nacos-data、minio-data、jenkins-home 等），数据将被彻底清空且不可恢复！
echo [提示] 如需保留数据，请先用菜单选项 31 备份数据库。
set /p confirm=请输入 DELETE 以确认清空所有数据卷：
if /i not "%confirm%"=="DELETE" (
    echo [取消] 已取消。
    timeout /t 1 >nul
    goto :menu
)
%KC% delete pvc --all -n %NAMESPACE%
echo.
echo [完成] 已清空所有数据卷。
pause
goto :menu

:restart
echo.
echo [信息] 正在重启核心服务...
%KC% rollout restart deployment/mysql deployment/redis deployment/nacos deployment/tdengine deployment/nginx -n %NAMESPACE%
%KC% get pods -n %NAMESPACE%
echo.
pause
goto :menu

:status
echo.
echo [信息] 所有服务状态：
%KC% get pods,svc -n %NAMESPACE% -o wide
echo.
pause
goto :menu

:logs
echo.
set "dep="
set /p dep=请输入 Deployment 名（如 mysql / nacos / redis / tdengine / nginx，Ctrl+C 退出后回菜单）:
%KC% logs -n %NAMESPACE% deploy/%dep% -f
echo.
pause
goto :menu

:rebuild
echo.
echo [信息] 重新下发核心方案并强制重启...
call :apply_scheme core
%KC% rollout restart deployment/mysql deployment/redis deployment/nacos deployment/tdengine deployment/nginx -n %NAMESPACE%
%KC% get pods -n %NAMESPACE%
echo.
pause
goto :menu

:start_with_postgres
echo.
echo [信息] 正在启动核心服务 + PostgreSQL...
call :apply_scheme core
call "%SVC_DIR%\postgres.bat" up
%KC% get pods -n %NAMESPACE%
echo.
pause
goto :menu

REM ================= 全部中间件 =================
:profile_all_up
echo.
echo [信息] 正在启动所有中间件...
call :apply_scheme middleware
%KC% get pods -n %NAMESPACE%
echo.
pause
goto :menu

:profile_all_down
echo.
echo [信息] 正在停止所有中间件（保留数据卷）...
set "TARGETS="
for %%d in (%MIDDLEWARE_DEPLOYMENTS%) do set "TARGETS=!TARGETS! deployment/%%d service/%%d"
%KC% delete!TARGETS! -n %NAMESPACE% --ignore-not-found
echo.
echo [完成] 中间件已全部停止。
pause
goto :menu

REM ================= 单服务启停：调用 services\{名称}.bat =================
:svc_start
call "%SVC_DIR%\!START_%choice%!.bat" up
echo.
pause
goto :menu

:svc_stop
call "%SVC_DIR%\!STOP_%choice%!.bat" down
echo.
pause
goto :menu

REM ================= 数据库备份 =================
:db_backup
echo.
REM 检查 mysql Deployment 是否有可用 Pod
set RUNNING=
for /f "delims=" %%s in ('%KC% get deploy/mysql -n %NAMESPACE% -o jsonpath^="{.status.readyReplicas}" 2^>nul') do set RUNNING=%%s
if not "!RUNNING!"=="1" (
    echo [错误] mysql Deployment 未就绪或不存在。
    echo.
    echo 当前 Pod 状态：
    %KC% get pods -n %NAMESPACE%
    pause
    goto :menu
)

REM 获取所有非默认数据库
echo [信息] 正在获取数据库列表...
set DB_LIST=
for /f "delims=" %%d in ('%KC% exec -n %NAMESPACE% %DB_DEPLOY% -- mysql -u%DB_USER% -p%DB_PASSWORD% -N -e "SHOW DATABASES;" 2^>nul') do (
    set DB=%%d
    set SKIP=
    for %%e in (%DB_EXCLUDE%) do (
        if /i "!DB!"=="%%e" set SKIP=1
    )
    if not defined SKIP (
        set DB_LIST=!DB_LIST! !DB!
    )
)

if "!DB_LIST!"=="" (
    echo [错误] 未发现任何非默认数据库。
    pause
    goto :menu
)

echo.
echo   将备份：!DB_LIST!
echo.

REM 生成时间戳
for /f "tokens=1-4 delims=/ " %%a in ('date /t') do set D=%%a%%b%%c
for /f "tokens=1-2 delims=:." %%a in ('echo %time%') do set T=%%a%%b
set STAMP=%D%_%T%

if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"
set FILE=%BACKUP_DIR%\mysql_%STAMP%.sql

echo [信息] 正在备份...
echo   Deployment: %DB_DEPLOY%
echo   文件: %FILE%
echo.

%KC% exec -n %NAMESPACE% %DB_DEPLOY% -- mysqldump ^
  -u%DB_USER% -p%DB_PASSWORD% ^
  --default-character-set=utf8mb4 ^
  --single-transaction ^
  --routines --triggers --events ^
  --databases !DB_LIST! > "%FILE%"

if errorlevel 1 (
    echo [错误] 备份失败，请检查 Pod 状态、密码。
) else (
    for %%F in ("%FILE%") do echo [成功] 备份完成，大小 %%~zF 字节
    echo [路径] %CD%\%FILE%
)
echo.
pause
goto :menu

REM ================= 数据库还原 =================
:db_restore
echo.
echo 可用的备份文件：
dir /b /o-d "%BACKUP_DIR%\*.sql" 2>nul
echo.
set /p FILE=请输入要还原的 SQL 文件路径（如 %BACKUP_DIR%\mysql_20260921_1200.sql）:

if not exist "%FILE%" (
    echo [错误] 文件不存在: %FILE%
    pause
    goto :menu
)

echo.
echo [警告] 还原会覆盖现有同名库的数据！
set /p confirm=确认还原？(Y/N):
if /i not "%confirm%"=="Y" (
    echo [取消] 已取消。
    pause
    goto :menu
)

echo.
echo [信息] 正在还原 %FILE% ...
%KC% exec -i -n %NAMESPACE% %DB_DEPLOY% -- mysql -u%DB_USER% -p%DB_PASSWORD% < "%FILE%"

if errorlevel 1 (
    echo [错误] 还原失败。
) else (
    echo [成功] 还原完成。
)
echo.
pause
goto :menu

REM ================= 备份列表 =================
:db_list
echo.
echo 备份文件列表（按时间倒序）：
dir /o-d "%BACKUP_DIR%\*.sql" 2>nul
echo.
pause
goto :menu

REM ================= 查看数据库 =================
:db_show
echo.
echo 所有数据库：
%KC% exec -n %NAMESPACE% %DB_DEPLOY% -- mysql -u%DB_USER% -p%DB_PASSWORD% -e "SHOW DATABASES;" 2>nul
echo.
echo 将要备份的（排除系统库 %DB_EXCLUDE%）：
for /f "delims=" %%d in ('%KC% exec -n %NAMESPACE% %DB_DEPLOY% -- mysql -u%DB_USER% -p%DB_PASSWORD% -N -e "SHOW DATABASES;" 2^>nul') do (
    set DB=%%d
    set SKIP=
    for %%e in (%DB_EXCLUDE%) do (
        if /i "!DB!"=="%%e" set SKIP=1
    )
    if not defined SKIP echo   !DB!
)
echo.
pause
goto :menu

:quit
echo.
echo 已退出。
timeout /t 1 >nul
exit /b

:end
echo.
echo 按任意键退出...
pause >nul
exit /b
