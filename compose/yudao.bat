@echo off
REM ============ 编码：二选一 ============
chcp 936 >nul
REM chcp 65001 >nul
REM ================= yudao 本地依赖环境：多服务菜单（Docker Compose）=================
REM 使用方案 compose\schemes\all.yaml（引用 compose\services\*.yaml）；单个服务按 profile 启停

setlocal enabledelayedexpansion
REM 以仓库根目录为工作目录（.env、backups 都在根目录）
cd /d "%~dp0.."
REM ---- 修复环境 PATH 缺失 System32 导致 chcp/where 不可用（仅本进程生效，不改系统全局环境） ----
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0\;%PATH%"

set SCHEME=compose\schemes\all.yaml
set "ENV_OPT="
if exist ".env" set "ENV_OPT=--env-file .env"
set CMD=docker compose -f %SCHEME% %ENV_OPT%
REM 核心服务（不带 profile，up -d 默认只启动这些）
set CORE_SERVICES=mysql redis
REM 所有中间件 profile / 服务（新增服务时同步这两行和下面的菜单编号）
set ALL_PROFILES=--profile nginx --profile nacos --profile tdengine --profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel --profile jenkins --profile postgres --profile lgtm --profile elk --profile rabbitmq --profile nora --profile orca-slicer
set MIDDLEWARE_SERVICES=nginx nacos tdengine minio rocketmq-namesrv rocketmq-broker xxl-job-admin seata-server sentinel-dashboard jenkins postgres lgtm elasticsearch logstash kibana rabbitmq nora
REM 数据卷名前缀 = compose 项目名（name: yudao），实际卷名为 yudao_卷名
set VOLUME_PREFIX=yudao
REM ---- 服务元数据（新增服务时加一组，并在菜单和编号表中加一行）----
REM TITLE_名称=显示名；SVCS_名称=compose 服务名；VOLS_名称=命名数据卷（不带 yudao_ 前缀）；DEPS_名称=需要先启动的服务；INFO_名称=启动后提示
set "TITLE_mysql=MySQL"
set "SVCS_mysql=mysql"
set "VOLS_mysql=mysql-data mysql-log"
set "DEPS_mysql="
set "INFO_mysql=MySQL：127.0.0.1:3306，root / .env 的 MYSQL_ROOT_PASSWORD"
set "TITLE_redis=Redis"
set "SVCS_redis=redis"
set "VOLS_redis="
set "DEPS_redis="
set "INFO_redis=Redis：127.0.0.1:6379，密码为 .env 的 REDIS_PASSWORD"
set "TITLE_nginx=Nginx"
set "SVCS_nginx=nginx"
set "VOLS_nginx="
set "DEPS_nginx="
set "INFO_nginx=Nginx：http://127.0.0.1:80"
set "TITLE_nacos=Nacos"
set "SVCS_nacos=nacos"
set "VOLS_nacos=nacos-data nacos-logs nacos-plugins"
set "DEPS_nacos=mysql"
set "INFO_nacos=Nacos 控制台：http://127.0.0.1:8080，客户端地址：127.0.0.1:8848"
set "TITLE_tdengine=TDengine"
set "SVCS_tdengine=tdengine"
set "VOLS_tdengine=tdengine-data tdengine-log"
set "DEPS_tdengine="
set "INFO_tdengine=TDengine REST/WebSocket：127.0.0.1:6041，首次使用需建库，见 config/tdengine/init-tdengine-db.md"
set "TITLE_jenkins=Jenkins"
set "SVCS_jenkins=jenkins"
set "VOLS_jenkins=jenkins-home"
set "DEPS_jenkins="
set "INFO_jenkins=Jenkins：http://127.0.0.1:8089"
set "TITLE_postgres=PostgreSQL"
set "SVCS_postgres=postgres"
set "VOLS_postgres=postgres-data postgres-log"
set "DEPS_postgres="
set "INFO_postgres=PostgreSQL：127.0.0.1:5432，账号见 .env 的 POSTGRES_USER / POSTGRES_PASSWORD"
set "TITLE_minio=MinIO"
set "SVCS_minio=minio"
set "VOLS_minio=minio-data"
set "DEPS_minio="
set "INFO_minio=MinIO 控制台：http://127.0.0.1:9001，API：http://127.0.0.1:9000"
set "TITLE_rocketmq=RocketMQ（namesrv + broker）"
set "SVCS_rocketmq=rocketmq-namesrv rocketmq-broker"
set "VOLS_rocketmq=rocketmq-namesrv-logs rocketmq-broker-logs rocketmq-broker-store"
set "DEPS_rocketmq="
set "INFO_rocketmq=NameServer：127.0.0.1:9876，broker 需要先准备 config/rocketmq/broker/conf/broker.conf"
set "TITLE_rabbitmq=RabbitMQ"
set "SVCS_rabbitmq=rabbitmq"
set "VOLS_rabbitmq=rabbitmq-data"
set "DEPS_rabbitmq="
set "INFO_rabbitmq=管理控制台：http://127.0.0.1:15672（账号为 .env 的 RABBITMQ_USERNAME / RABBITMQ_PASSWORD），AMQP 地址：127.0.0.1:5672"
set "TITLE_nora=NORA 制品仓库"
set "SVCS_nora=nora"
set "VOLS_nora=nora-data"
set "DEPS_nora="
set "INFO_nora=Web UI：http://127.0.0.1:4000/ui/，镜像仓库：localhost:4000，Maven：http://127.0.0.1:4000/maven2/，npm：http://127.0.0.1:4000/npm/"
set "TITLE_orca-slicer=OrcaSlicer 切片服务"
set "SVCS_orca-slicer=orca-slicer"
set "VOLS_orca-slicer="
set "DEPS_orca-slicer="
set "INFO_orca-slicer=切片接口：http://127.0.0.1:8590/health，首次启动会先构建镜像（下载 OrcaSlicer，需要几分钟），自定义预设放在 config\orca-slicer\presets"
set "TITLE_xxl-job=XXL-Job"
set "SVCS_xxl-job=xxl-job-admin"
set "VOLS_xxl-job=xxl-job-logs"
set "DEPS_xxl-job=mysql"
set "INFO_xxl-job=调度中心：http://127.0.0.1:9090/xxl-job-admin"
set "TITLE_seata=Seata Server"
set "SVCS_seata=seata-server"
set "VOLS_seata="
set "DEPS_seata=mysql nacos"
set "INFO_seata=Seata TC：127.0.0.1:8091，注册到 Nacos 的 SEATA_GROUP"
set "TITLE_sentinel=Sentinel Dashboard"
set "SVCS_sentinel=sentinel-dashboard"
set "VOLS_sentinel=sentinel-logs"
set "DEPS_sentinel="
set "INFO_sentinel=Sentinel 控制台：http://127.0.0.1:8858"
set "TITLE_lgtm=Grafana LGTM"
set "SVCS_lgtm=lgtm"
set "VOLS_lgtm=lgtm-data"
set "DEPS_lgtm="
set "INFO_lgtm=Grafana 控制台：http://127.0.0.1:3000（admin / admin），OTLP HTTP 上报地址：http://127.0.0.1:4318"
set "TITLE_elk=ELK（Elasticsearch + Logstash + Kibana）"
set "SVCS_elk=elasticsearch logstash kibana"
set "VOLS_elk=elasticsearch-data"
set "DEPS_elk="
set "INFO_elk=Kibana 控制台：http://127.0.0.1:5601，应用上报地址（Logstash）：127.0.0.1:5044，首次启动需要 1~2 分钟"
REM ---- 菜单编号 → 服务（启动 n，停止 n+10）----
set "START_10=tdengine"
set "STOP_20=tdengine"
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
set "START_18=nacos"
set "STOP_28=nacos"
set "START_19=lgtm"
set "STOP_29=lgtm"
set "START_40=nginx"
set "STOP_50=nginx"
set "START_41=elk"
set "STOP_51=elk"
set "START_42=rabbitmq"
set "STOP_52=rabbitmq"
set "START_43=nora"
set "STOP_53=nora"
set "START_44=orca-slicer"
set "STOP_54=orca-slicer"

REM ---- 数据库备份配置 ----
set DB_CONTAINER=yudao-mysql
set DB_USER=root
set DB_PASSWORD=123456
set BACKUP_DIR=backups
REM 默认排除的系统库
set DB_EXCLUDE=information_schema mysql performance_schema sys

REM ---- 前置检查 ----
where docker >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 docker 命令，请确认 Docker Desktop 已启动并加入 PATH。
    goto :end
)
if not exist "%SCHEME%" (
    echo [错误] 未找到配置方案 %SCHEME%
    goto :end
)

:menu
cls
echo ========================================
echo   yudao-cloud Docker 管理菜单
echo   配置方案: %SCHEME%
echo ========================================
echo   核心服务：
echo     1. 启动核心    (mysql/redis)
echo     2. 停止全部    (核心 + 所有中间件)
echo     3. 重启核心
echo     4. 查看状态    (所有服务)
echo     5. 查看日志    (核心服务)
echo     6. 强制重建    (核心服务)
echo.
echo   中间件（单独启停）：
echo     10. 启动 TDengine       20. 停止 TDengine
echo     11. 启动 MinIO          21. 停止 MinIO
echo     12. 启动 RocketMQ       22. 停止 RocketMQ
echo     13. 启动 XXL-Job        23. 停止 XXL-Job
echo     14. 启动 Seata          24. 停止 Seata
echo     15. 启动 Sentinel       25. 停止 Sentinel
echo     16. 启动 Jenkins        26. 停止 Jenkins
echo     17. 启动 PostgreSQL     27. 停止 PostgreSQL
echo     18. 启动 Nacos          28. 停止 Nacos
echo     19. 启动 Grafana LGTM   29. 停止 Grafana LGTM
echo     40. 启动 Nginx          50. 停止 Nginx
echo     41. 启动 ELK            51. 停止 ELK
echo     42. 启动 RabbitMQ       52. 停止 RabbitMQ
echo     43. 启动 NORA           53. 停止 NORA
echo     44. 启动 OrcaSlicer     54. 停止 OrcaSlicer（切片服务，不在「全部中间件」中）
echo     （停止中间件时会询问是否同时删除数据卷，默认 N 保留数据）
echo.
echo     7. 启动全部中间件       8. 停止全部中间件 (保留核心)
echo     9. 停止全部并清空数据卷 (down -v，危险！会删除所有数据)
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
if "%choice%"=="9" goto :stop_v
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

REM ================= 核心 =================
:start
echo.
echo [信息] 正在启动核心服务 (%CORE_SERVICES%)...
%CMD% up -d %CORE_SERVICES%
%CMD% ps %CORE_SERVICES%
echo.
pause
goto :menu

:stop
echo.
set /p confirm=确认停止并移除所有容器（含中间件）？(Y/N):
if /i not "%confirm%"=="Y" (
    echo [取消] 已取消。
    timeout /t 1 >nul
    goto :menu
)
%CMD% %ALL_PROFILES% down
echo.
echo [完成] 已全部停止。
pause
goto :menu

:stop_v
echo.
echo [警告] 此操作将停止并删除所有容器，同时删除所有命名卷（mysql-data、nacos-data、minio-data、jenkins-home 等），数据将被彻底清空且不可恢复！
echo [提示] 如需保留数据，请先用菜单选项 31 备份数据库。
set /p confirm=请输入 DELETE 以确认执行 down -v：
if /i not "%confirm%"=="DELETE" (
    echo [取消] 已取消。
    timeout /t 1 >nul
    goto :menu
)
%CMD% %ALL_PROFILES% down -v
echo.
echo [完成] 已停止并清空所有数据卷。
pause
goto :menu

:restart
echo.
echo [信息] 正在重启核心服务 (%CORE_SERVICES%)...
%CMD% stop %CORE_SERVICES%
%CMD% up -d %CORE_SERVICES%
%CMD% ps %CORE_SERVICES%
echo.
pause
goto :menu

:status
echo.
echo [信息] 所有服务状态：
%CMD% %ALL_PROFILES% ps
echo.
pause
goto :menu

:logs
echo.
echo [信息] 核心服务日志。Ctrl+C 退出后回菜单。
cmd /c "%CMD% logs -f %CORE_SERVICES%"
echo.
pause
goto :menu

:rebuild
echo.
echo [信息] 强制重建核心服务 (%CORE_SERVICES%)...
%CMD% up -d --force-recreate %CORE_SERVICES%
%CMD% ps %CORE_SERVICES%
echo.
pause
goto :menu

REM ================= 全部中间件 =================
:profile_all_up
echo.
echo [信息] 正在启动所有中间件（连同核心服务，nacos 等依赖 mysql）...
%CMD% %ALL_PROFILES% up -d %CORE_SERVICES% %MIDDLEWARE_SERVICES%
%CMD% %ALL_PROFILES% ps
echo.
pause
goto :menu

:profile_all_down
echo.
echo [信息] 正在停止所有中间件...
%CMD% %ALL_PROFILES% stop %MIDDLEWARE_SERVICES%
echo.
echo [完成] 中间件已全部停止（核心服务保持运行）。
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

REM 用法：call :svc_up 名称（先启动 DEPS_名称 中的依赖）
:svc_up
set "S=%~1"
for %%d in (!DEPS_%S%!) do (
    echo [信息] 先启动依赖：!TITLE_%%d!
    %CMD% --profile %%d up -d !SVCS_%%d!
)
echo [信息] 启动 !TITLE_%S%!...
%CMD% --profile %S% up -d !SVCS_%S%!
if defined INFO_%S% echo [信息] !INFO_%S%!
exit /b

REM 用法：call :svc_down 名称（有命名数据卷时询问是否一起删除，默认 N 保留）
:svc_down
set "S=%~1"
set "MD_SERVICES=!SVCS_%S%!"
set "MD_VOLUMES=!VOLS_%S%!"
echo [信息] 停止 !TITLE_%S%!...
if "%MD_VOLUMES%"=="" (
    %CMD% --profile %S% stop %MD_SERVICES%
    exit /b
)
echo [提示] 相关数据卷：%MD_VOLUMES%
set "rmvol=N"
set /p rmvol=是否同时删除容器和数据卷？删除后数据不可恢复 (y/N，默认 N):
if /i not "!rmvol!"=="Y" (
    %CMD% --profile %S% stop %MD_SERVICES%
    echo [完成] 已停止，数据卷已保留。
    exit /b
)
%CMD% --profile %S% rm -s -f %MD_SERVICES%
for %%v in (%MD_VOLUMES%) do (
    docker volume inspect %VOLUME_PREFIX%_%%v >nul 2>nul && docker volume rm %VOLUME_PREFIX%_%%v
)
echo [完成] 已停止并删除容器和数据卷。
exit /b

REM ================= 数据库备份 =================
:db_backup
echo.
REM 检查容器是否运行
set RUNNING=
for /f "delims=" %%s in ('docker inspect -f "{{.State.Running}}" %DB_CONTAINER% 2^>nul') do set RUNNING=%%s
if /i not "!RUNNING!"=="true" (
    echo [错误] 容器 %DB_CONTAINER% 未运行或不存在。
    echo.
    echo 当前运行的容器：
    docker ps --format "  {{.Names}}  {{.Status}}"
    echo.
    echo 提示：如果 mysql 容器名不是 %DB_CONTAINER%，
    echo       请修改脚本开头的 set DB_CONTAINER=xxx
    pause
    goto :menu
)

REM 获取所有非默认数据库
echo [信息] 正在获取数据库列表...
set DB_LIST=
for /f "delims=" %%d in ('docker exec %DB_CONTAINER% mysql -u%DB_USER% -p%DB_PASSWORD% -N -e "SHOW DATABASES;" 2^>nul') do (
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
echo   容器: %DB_CONTAINER%
echo   文件: %FILE%
echo.

docker exec %DB_CONTAINER% mysqldump ^
  -u%DB_USER% -p%DB_PASSWORD% ^
  --default-character-set=utf8mb4 ^
  --single-transaction ^
  --routines --triggers --events ^
  --databases !DB_LIST! > "%FILE%"

if errorlevel 1 (
    echo [错误] 备份失败，请检查容器、密码。
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
docker exec -i %DB_CONTAINER% mysql -u%DB_USER% -p%DB_PASSWORD% < "%FILE%"

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
docker exec %DB_CONTAINER% mysql -u%DB_USER% -p%DB_PASSWORD% -e "SHOW DATABASES;" 2>nul
echo.
echo 将要备份的（排除系统库 %DB_EXCLUDE%）：
for /f "delims=" %%d in ('docker exec %DB_CONTAINER% mysql -u%DB_USER% -p%DB_PASSWORD% -N -e "SHOW DATABASES;" 2^>nul') do (
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
