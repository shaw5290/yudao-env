@echo off
REM ============ 编码：二选一 ============
chcp 936 >nul
REM chcp 65001 >nul

setlocal enabledelayedexpansion
cd /d %~dp0
REM ---- 修复环境 PATH 缺失 System32 导致 chcp/where 不可用（仅本进程生效，不改系统全局环境） ----
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0\;%PATH%"

set NAMESPACE=yudao
set K8S_DIR=k8s
set ENV_FILE=.env

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
if not exist "%K8S_DIR%" (
    echo [错误] 未找到 %K8S_DIR% 目录
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
echo   命名空间: %NAMESPACE%    清单目录: %K8S_DIR%
echo ========================================
echo   核心服务：
echo     1. 启动核心    (nginx/mysql/redis/nacos/tdengine)
echo     2. 停止全部    (含所有已启用中间件，保留数据卷)
echo     3. 重启核心    (rollout restart)
echo     4. 查看状态    (所有 Pod / Service)
echo     5. 查看日志    (输入 Deployment 名)
echo     6. 强制重建    (重新 apply 全部核心清单 + 重启)
echo.
echo   中间件（单独启停）：
echo     11. 启动 MinIO          21. 停止 MinIO
echo     12. 启动 RocketMQ       22. 停止 RocketMQ
echo     13. 启动 XXL-Job        23. 停止 XXL-Job
echo     14. 启动 Seata          24. 停止 Seata
echo     15. 启动 Sentinel       25. 停止 Sentinel
echo     16. 启动 Jenkins        26. 停止 Jenkins
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
if "%choice%"=="11" goto :minio_up
if "%choice%"=="21" goto :minio_down
if "%choice%"=="12" goto :rocketmq_up
if "%choice%"=="22" goto :rocketmq_down
if "%choice%"=="13" goto :xxljob_up
if "%choice%"=="23" goto :xxljob_down
if "%choice%"=="14" goto :seata_up
if "%choice%"=="24" goto :seata_down
if "%choice%"=="15" goto :sentinel_up
if "%choice%"=="25" goto :sentinel_down
if "%choice%"=="16" goto :jenkins_up
if "%choice%"=="26" goto :jenkins_down
if "%choice%"=="31" goto :db_backup
if "%choice%"=="32" goto :db_restore
if "%choice%"=="33" goto :db_list
if "%choice%"=="34" goto :db_show
if "%choice%"=="0" goto :quit

echo.
echo [提示] 无效选项，请重新输入。
timeout /t 1 >nul
goto :menu

REM ================= 核心 =================
:sync_secret
kubectl create secret generic yudao-env --from-env-file=%ENV_FILE% -n %NAMESPACE% --dry-run=client -o yaml | kubectl apply -f -
exit /b

:start
echo.
echo [信息] 正在启动核心服务...
kubectl apply -f %K8S_DIR%\00-namespace.yaml
call :sync_secret
kubectl apply -f %K8S_DIR%\01-mysql.yaml -f %K8S_DIR%\02-redis.yaml -f %K8S_DIR%\03-nacos.yaml -f %K8S_DIR%\04-tdengine.yaml -f %K8S_DIR%\05-nginx.yaml
kubectl get pods -n %NAMESPACE%
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
kubectl delete deployment,service --all -n %NAMESPACE% --ignore-not-found
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
kubectl delete pvc --all -n %NAMESPACE%
echo.
echo [完成] 已清空所有数据卷。
pause
goto :menu

:restart
echo.
echo [信息] 正在重启核心服务...
kubectl rollout restart deployment/mysql deployment/redis deployment/nacos deployment/tdengine deployment/nginx -n %NAMESPACE%
kubectl get pods -n %NAMESPACE%
echo.
pause
goto :menu

:status
echo.
echo [信息] 所有服务状态：
kubectl get pods,svc -n %NAMESPACE% -o wide
echo.
pause
goto :menu

:logs
echo.
set /p dep=请输入 Deployment 名（如 mysql / nacos / redis / tdengine / nginx，Ctrl+C 退出后回菜单）:
kubectl logs -n %NAMESPACE% deploy/%dep% -f
echo.
pause
goto :menu

:rebuild
echo.
echo [信息] 重新下发核心清单并强制重启...
kubectl apply -f %K8S_DIR%\00-namespace.yaml
call :sync_secret
kubectl apply -f %K8S_DIR%\01-mysql.yaml -f %K8S_DIR%\02-redis.yaml -f %K8S_DIR%\03-nacos.yaml -f %K8S_DIR%\04-tdengine.yaml -f %K8S_DIR%\05-nginx.yaml
kubectl rollout restart deployment/mysql deployment/redis deployment/nacos deployment/tdengine deployment/nginx -n %NAMESPACE%
kubectl get pods -n %NAMESPACE%
echo.
pause
goto :menu

REM ================= 全部中间件 =================
:profile_all_up
echo.
echo [信息] 正在启动所有中间件...
kubectl apply -f %K8S_DIR%\10-jenkins.yaml -f %K8S_DIR%\11-minio.yaml -f %K8S_DIR%\12-rocketmq.yaml -f %K8S_DIR%\13-xxljob.yaml -f %K8S_DIR%\14-seata.yaml -f %K8S_DIR%\15-sentinel.yaml
kubectl get pods -n %NAMESPACE%
echo.
pause
goto :menu

:profile_all_down
echo.
echo [信息] 正在停止所有中间件（保留数据卷）...
kubectl delete deployment/jenkins service/jenkins deployment/minio service/minio deployment/rocketmq-namesrv service/rocketmq-namesrv deployment/rocketmq-broker service/rocketmq-broker deployment/xxl-job-admin service/xxl-job-admin deployment/seata-server service/seata-server deployment/sentinel-dashboard service/sentinel-dashboard -n %NAMESPACE% --ignore-not-found
echo.
echo [完成] 中间件已全部停止。
pause
goto :menu

REM ================= MinIO =================
:minio_up
echo.
echo [信息] 启动 MinIO...
kubectl apply -f %K8S_DIR%\11-minio.yaml
pause
goto :menu

:minio_down
echo.
echo [信息] 停止 MinIO...
kubectl delete deployment/minio service/minio -n %NAMESPACE% --ignore-not-found
pause
goto :menu

REM ================= RocketMQ =================
:rocketmq_up
echo.
echo [信息] 启动 RocketMQ (namesrv + broker)...
kubectl apply -f %K8S_DIR%\12-rocketmq.yaml
pause
goto :menu

:rocketmq_down
echo.
echo [信息] 停止 RocketMQ...
kubectl delete deployment/rocketmq-namesrv service/rocketmq-namesrv deployment/rocketmq-broker service/rocketmq-broker -n %NAMESPACE% --ignore-not-found
pause
goto :menu

REM ================= XXL-Job =================
:xxljob_up
echo.
echo [信息] 启动 XXL-Job...
kubectl apply -f %K8S_DIR%\13-xxljob.yaml
pause
goto :menu

:xxljob_down
echo.
echo [信息] 停止 XXL-Job...
kubectl delete deployment/xxl-job-admin service/xxl-job-admin -n %NAMESPACE% --ignore-not-found
pause
goto :menu

REM ================= Seata =================
:seata_up
echo.
echo [信息] 启动 Seata...
kubectl apply -f %K8S_DIR%\14-seata.yaml
pause
goto :menu

:seata_down
echo.
echo [信息] 停止 Seata...
kubectl delete deployment/seata-server service/seata-server -n %NAMESPACE% --ignore-not-found
pause
goto :menu

REM ================= Sentinel =================
:sentinel_up
echo.
echo [信息] 启动 Sentinel Dashboard...
kubectl apply -f %K8S_DIR%\15-sentinel.yaml
pause
goto :menu

:sentinel_down
echo.
echo [信息] 停止 Sentinel Dashboard...
kubectl delete deployment/sentinel-dashboard service/sentinel-dashboard -n %NAMESPACE% --ignore-not-found
pause
goto :menu

REM ================= Jenkins =================
:jenkins_up
echo.
echo [信息] 启动 Jenkins...
kubectl apply -f %K8S_DIR%\10-jenkins.yaml
pause
goto :menu

:jenkins_down
echo.
echo [信息] 停止 Jenkins...
kubectl delete deployment/jenkins service/jenkins -n %NAMESPACE% --ignore-not-found
pause
goto :menu

REM ================= 数据库备份 =================
:db_backup
echo.
REM 检查 mysql Deployment 是否有可用 Pod
set RUNNING=
for /f "delims=" %%s in ('kubectl get deploy/mysql -n %NAMESPACE% -o jsonpath^="{.status.readyReplicas}" 2^>nul') do set RUNNING=%%s
if not "!RUNNING!"=="1" (
    echo [错误] mysql Deployment 未就绪或不存在。
    echo.
    echo 当前 Pod 状态：
    kubectl get pods -n %NAMESPACE%
    pause
    goto :menu
)

REM 获取所有非默认数据库
echo [信息] 正在获取数据库列表...
set DB_LIST=
for /f "delims=" %%d in ('kubectl exec -n %NAMESPACE% %DB_DEPLOY% -- mysql -u%DB_USER% -p%DB_PASSWORD% -N -e "SHOW DATABASES;" 2^>nul') do (
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

kubectl exec -n %NAMESPACE% %DB_DEPLOY% -- mysqldump ^
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
kubectl exec -i -n %NAMESPACE% %DB_DEPLOY% -- mysql -u%DB_USER% -p%DB_PASSWORD% < "%FILE%"

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
kubectl exec -n %NAMESPACE% %DB_DEPLOY% -- mysql -u%DB_USER% -p%DB_PASSWORD% -e "SHOW DATABASES;" 2>nul
echo.
echo 将要备份的（排除系统库 %DB_EXCLUDE%）：
for /f "delims=" %%d in ('kubectl exec -n %NAMESPACE% %DB_DEPLOY% -- mysql -u%DB_USER% -p%DB_PASSWORD% -N -e "SHOW DATABASES;" 2^>nul') do (
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
