@echo off
REM ============ 编码：二选一 ============
chcp 936 >nul
REM chcp 65001 >nul
REM ================= yudao 本地依赖环境：多服务菜单（Kubernetes）=================
REM 核心 / 全部中间件按方案 k8s\schemes\core、middleware 部署；单个服务生成临时方案部署（见 :svc_up）

setlocal enabledelayedexpansion
REM 以仓库根目录为工作目录（.env、backups 都在根目录）
cd /d "%~dp0.."
REM ---- 修复环境 PATH 缺失 System32 导致 chcp/where 不可用（仅本进程生效，不改系统全局环境） ----
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0\;%PATH%"

set NAMESPACE=yudao
set ENV_FILE=.env
set SCHEMES_DIR=k8s\schemes
REM 所有 kubectl 调用都显式指定上下文，避免误操作当前默认上下文指向的其他集群；用其他集群时先 set K8S_CONTEXT=xxx
if not defined K8S_CONTEXT set K8S_CONTEXT=docker-desktop
set "KC=kubectl --context %K8S_CONTEXT%"
REM NORA 开启鉴权时使用的 htpasswd（不提交），存在时同步为 Secret nora-htpasswd
set NORA_HTPASSWD=config\nora\auth\users.htpasswd
REM 核心 / 中间件 Deployment（与同名 Service 一起启停；新增服务时同步这两行和下面的菜单编号）
set CORE_DEPLOYMENTS=mysql redis nacos tdengine nginx
set MIDDLEWARE_DEPLOYMENTS=jenkins minio rocketmq-namesrv rocketmq-broker xxl-job-admin seata-server sentinel-dashboard postgres lgtm elasticsearch logstash kibana rabbitmq nora
REM ---- 服务元数据（新增服务时加一组，并在菜单和编号表中加一行）----
REM TITLE_名称=显示名；DEPLOYS_名称=Deployment（与同名 Service 一起启停）；DEPS_名称=一起部署的依赖服务；INFO_名称=启动后提示
set "TITLE_mysql=MySQL"
set "DEPLOYS_mysql=mysql"
set "DEPS_mysql="
set "INFO_mysql=MySQL：127.0.0.1:3306，root / .env 的 MYSQL_ROOT_PASSWORD"
set "TITLE_redis=Redis"
set "DEPLOYS_redis=redis"
set "DEPS_redis="
set "INFO_redis=Redis：127.0.0.1:6379，密码为 .env 的 REDIS_PASSWORD"
set "TITLE_nginx=Nginx"
set "DEPLOYS_nginx=nginx"
set "DEPS_nginx="
set "INFO_nginx=Nginx：http://127.0.0.1:80"
set "TITLE_nacos=Nacos"
set "DEPLOYS_nacos=nacos"
set "DEPS_nacos=mysql"
set "INFO_nacos=Nacos 控制台：http://127.0.0.1:8080，客户端地址：127.0.0.1:8848"
set "TITLE_tdengine=TDengine"
set "DEPLOYS_tdengine=tdengine"
set "DEPS_tdengine="
set "INFO_tdengine=TDengine REST/WebSocket：127.0.0.1:6041，首次使用需建库，见 config/tdengine/init-tdengine-db.md"
set "TITLE_jenkins=Jenkins"
set "DEPLOYS_jenkins=jenkins"
set "DEPS_jenkins="
set "INFO_jenkins=Jenkins：http://127.0.0.1:8089"
set "TITLE_postgres=PostgreSQL"
set "DEPLOYS_postgres=postgres"
set "DEPS_postgres="
set "INFO_postgres=PostgreSQL：127.0.0.1:5432，账号见 .env 的 POSTGRES_USER / POSTGRES_PASSWORD"
set "TITLE_minio=MinIO"
set "DEPLOYS_minio=minio"
set "DEPS_minio="
set "INFO_minio=MinIO 控制台：http://127.0.0.1:9001，API：http://127.0.0.1:9000"
set "TITLE_rocketmq=RocketMQ（namesrv + broker）"
set "DEPLOYS_rocketmq=rocketmq-namesrv rocketmq-broker"
set "DEPS_rocketmq="
set "INFO_rocketmq=NameServer：127.0.0.1:9876，broker 需要先准备 config/rocketmq/broker/conf/broker.conf"
set "TITLE_rabbitmq=RabbitMQ"
set "DEPLOYS_rabbitmq=rabbitmq"
set "DEPS_rabbitmq="
set "INFO_rabbitmq=管理控制台：http://127.0.0.1:15672（账号为 .env 的 RABBITMQ_USERNAME / RABBITMQ_PASSWORD），AMQP 地址：127.0.0.1:5672"
set "TITLE_nora=NORA 制品仓库"
set "DEPLOYS_nora=nora"
set "DEPS_nora="
set "INFO_nora=Web UI：http://127.0.0.1:4000/ui/，镜像仓库：localhost:4000，Maven：http://127.0.0.1:4000/maven2/，npm：http://127.0.0.1:4000/npm/"
set "TITLE_orca-slicer=OrcaSlicer 切片服务"
set "DEPLOYS_orca-slicer=orca-slicer"
set "DEPS_orca-slicer="
set "INFO_orca-slicer=切片接口：http://127.0.0.1:8590/health，镜像需先用 Compose 构建：docker compose -f compose/services/orca-slicer.yaml --env-file .env --profile orca-slicer build"
set "TITLE_xxl-job=XXL-Job"
set "DEPLOYS_xxl-job=xxl-job-admin"
set "DEPS_xxl-job=mysql"
set "INFO_xxl-job=调度中心：http://127.0.0.1:9090/xxl-job-admin"
set "TITLE_seata=Seata Server"
set "DEPLOYS_seata=seata-server"
set "DEPS_seata=mysql nacos"
set "INFO_seata=Seata TC：127.0.0.1:8091，注册到 Nacos 的 SEATA_GROUP"
set "TITLE_sentinel=Sentinel Dashboard"
set "DEPLOYS_sentinel=sentinel-dashboard"
set "DEPS_sentinel="
set "INFO_sentinel=Sentinel 控制台：http://127.0.0.1:8858"
set "TITLE_lgtm=Grafana LGTM"
set "DEPLOYS_lgtm=lgtm"
set "DEPS_lgtm="
set "INFO_lgtm=Grafana 控制台：http://127.0.0.1:3000（admin / admin），OTLP HTTP 上报地址：http://127.0.0.1:4318"
set "TITLE_elk=ELK（Elasticsearch + Logstash + Kibana）"
set "DEPLOYS_elk=elasticsearch logstash kibana"
set "DEPS_elk="
set "INFO_elk=Kibana 控制台：http://127.0.0.1:5601，应用上报地址（Logstash）：127.0.0.1:5044，首次启动需要 1~2 分钟"
REM ---- 菜单编号 → 服务（启动 n，停止 n+10）----
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
set "START_44=orca-slicer"
set "STOP_54=orca-slicer"

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
echo     44. 启动 OrcaSlicer     54. 停止 OrcaSlicer（切片服务，不在「全部中间件」中）
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

REM ================= 方案部署：namespace → Secret → kustomize 渲染 → apply（用法：call :apply_dir 方案目录）=================
REM 方案引用了目录外的 services\*.yaml，必须加 --load-restrictor LoadRestrictionsNone，所以不用 apply -k
:apply_dir
%KC% apply -f k8s\base\namespace.yaml
%KC% create secret generic yudao-env --from-env-file=%ENV_FILE% -n %NAMESPACE% --dry-run=client -o yaml | %KC% apply -f -
if exist "%NORA_HTPASSWD%" (
    %KC% create secret generic nora-htpasswd --from-file=users.htpasswd=%NORA_HTPASSWD% -n %NAMESPACE% --dry-run=client -o yaml | %KC% apply -f -
)
%KC% kustomize --load-restrictor LoadRestrictionsNone %~1 | %KC% apply -f -
exit /b

REM ================= 核心 =================
:start
echo.
echo [信息] 正在启动核心服务...
call :apply_dir %SCHEMES_DIR%\core
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
call :apply_dir %SCHEMES_DIR%\core
%KC% rollout restart deployment/mysql deployment/redis deployment/nacos deployment/tdengine deployment/nginx -n %NAMESPACE%
%KC% get pods -n %NAMESPACE%
echo.
pause
goto :menu

:start_with_postgres
echo.
echo [信息] 正在启动核心服务 + PostgreSQL...
call :apply_dir %SCHEMES_DIR%\core
call :svc_up postgres
%KC% get pods -n %NAMESPACE%
echo.
pause
goto :menu

REM ================= 全部中间件 =================
:profile_all_up
echo.
echo [信息] 正在启动所有中间件...
call :apply_dir %SCHEMES_DIR%\middleware
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

REM ================= 单服务启停 =================
:svc_start
call :svc_up !START_%choice%!
echo.
pause
goto :menu

:svc_stop
call :svc_down !STOP_%choice%!
echo.
pause
goto :menu

REM 用法：call :svc_up 名称
REM 生成单服务临时方案 k8s\.render\名称\kustomization.yaml（DEPS_名称 + 本服务 + base），与方案部署走同一流程
REM 临时方案中只写 ASCII：bat 以 GBK 输出，kustomize 按 UTF-8 解析，中文会导致 invalid UTF-8 报错
:svc_up
set "S=%~1"
set "RENDER=k8s\.render\%S%"
if not exist "%RENDER%" mkdir "%RENDER%"
(
    echo # generated by k8s\yudao-k8s.bat, do not edit or commit
    echo apiVersion: kustomize.config.k8s.io/v1beta1
    echo kind: Kustomization
    echo resources:
    for %%d in (!DEPS_%S%!) do echo   - ../../services/%%d.yaml
    echo   - ../../services/%S%.yaml
    echo components:
    echo   - ../../base
) > "%RENDER%\kustomization.yaml"
if not "!DEPS_%S%!"=="" echo [信息] 一起部署依赖：!DEPS_%S%!
echo [信息] 部署 !TITLE_%S%!...
call :apply_dir %RENDER%
if defined INFO_%S% echo [信息] !INFO_%S%!
exit /b

REM 用法：call :svc_down 名称（只删 Deployment / Service，保留 PVC 数据卷）
:svc_down
set "S=%~1"
echo [信息] 停止 !TITLE_%S%!（保留数据卷）...
set "TARGETS="
for %%d in (!DEPLOYS_%S%!) do set "TARGETS=!TARGETS! deployment/%%d service/%%d"
%KC% delete!TARGETS! -n %NAMESPACE% --ignore-not-found
exit /b

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
