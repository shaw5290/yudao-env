@echo off
REM ============ 编码：二选一 ============
chcp 936 >nul
REM chcp 65001 >nul

setlocal enabledelayedexpansion
cd /d %~dp0

set COMPOSE_FILE=docker-compose-yudao.yaml
set CMD=docker compose -f %COMPOSE_FILE%

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
REM 带所有 profile 的 down 才能把 profile 容器一并清掉
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