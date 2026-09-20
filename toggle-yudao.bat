@echo off
REM ============ 编码：二选一 ============
chcp 936 >nul
REM chcp 65001 >nul

setlocal enabledelayedexpansion
cd /d %~dp0

set COMPOSE_FILE=docker-compose-yudao.yaml
set CMD=docker compose -f %COMPOSE_FILE%

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
if not exist "%COMPOSE_FILE%" (
    echo [错误] 未找到配置文件 %COMPOSE_FILE%
    goto :end
)

:menu
cls
echo ========================================
echo   yudao-cloud Docker 管理菜单
echo   配置文件: %COMPOSE_FILE%
echo ========================================
echo   核心服务：
echo     1. 启动核心    (nginx/mysql/redis/nacos)
echo     2. 停止全部    (含所有 profile)
echo     3. 重启核心
echo     4. 查看状态    (所有服务)
echo     5. 查看日志    (核心服务)
echo     6. 强制重建    (核心服务)
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
:start
echo.
echo [信息] 正在启动核心服务...
%CMD% up -d --build
%CMD% ps
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
docker compose -f %COMPOSE_FILE% --profile jenkins --profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel down
echo.
echo [完成] 已全部停止。
pause
goto :menu

:restart
echo.
echo [信息] 正在重启核心服务...
%CMD% down
%CMD% up -d --build
%CMD% ps
echo.
pause
goto :menu

:status
echo.
echo [信息] 所有服务状态：
docker compose -f %COMPOSE_FILE% --profile jenkins --profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel ps
echo.
pause
goto :menu

:logs
echo.
echo [信息] 核心服务日志。Ctrl+C 退出后回菜单。
cmd /c "%CMD% logs -f"
echo.
pause
goto :menu

:rebuild
echo.
echo [信息] 强制重建核心服务...
%CMD% up -d --build --force-recreate
%CMD% ps
echo.
pause
goto :menu

REM ================= 全部中间件 =================
:profile_all_up
echo.
echo [信息] 正在启动所有中间件...
docker compose -f %COMPOSE_FILE% --profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel --profile jenkins up -d
docker compose -f %COMPOSE_FILE% --profile jenkins --profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel ps
echo.
pause
goto :menu

:profile_all_down
echo.
echo [信息] 正在停止所有中间件...
docker compose -f %COMPOSE_FILE% --profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel --profile jenkins down
echo.
echo [完成] 中间件已全部停止。
pause
goto :menu

REM ================= MinIO =================
:minio_up
echo.
echo [信息] 启动 MinIO...
%CMD% --profile minio up -d minio
pause
goto :menu

:minio_down
echo.
echo [信息] 停止 MinIO...
%CMD% --profile minio stop minio
pause
goto :menu

REM ================= RocketMQ =================
:rocketmq_up
echo.
echo [信息] 启动 RocketMQ (namesrv + broker)...
%CMD% --profile rocketmq up -d
pause
goto :menu

:rocketmq_down
echo.
echo [信息] 停止 RocketMQ...
%CMD% --profile rocketmq stop
pause
goto :menu

REM ================= XXL-Job =================
:xxljob_up
echo.
echo [信息] 启动 XXL-Job...
%CMD% --profile xxl-job up -d xxl-job-admin
pause
goto :menu

:xxljob_down
echo.
echo [信息] 停止 XXL-Job...
%CMD% --profile xxl-job stop xxl-job-admin
pause
goto :menu

REM ================= Seata =================
:seata_up
echo.
echo [信息] 启动 Seata...
%CMD% --profile seata up -d seata-server
pause
goto :menu

:seata_down
echo.
echo [信息] 停止 Seata...
%CMD% --profile seata stop seata-server
pause
goto :menu

REM ================= Sentinel =================
:sentinel_up
echo.
echo [信息] 启动 Sentinel Dashboard...
%CMD% --profile sentinel up -d sentinel-dashboard
pause
goto :menu

:sentinel_down
echo.
echo [信息] 停止 Sentinel Dashboard...
%CMD% --profile sentinel stop sentinel-dashboard
pause
goto :menu

REM ================= Jenkins =================
:jenkins_up
echo.
echo [信息] 启动 Jenkins...
%CMD% --profile jenkins up -d jenkins
pause
goto :menu

:jenkins_down
echo.
echo [信息] 停止 Jenkins...
%CMD% --profile jenkins stop jenkins
pause
goto :menu

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