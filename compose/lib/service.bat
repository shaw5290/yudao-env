@echo off
REM ============================================================
REM  单服务公共逻辑（Docker Compose），不要直接运行
REM  由 compose\services\{服务}.bat 设置以下变量后 call 本脚本：
REM    SVC_TITLE     显示名称
REM    SVC_FILE      服务文件名：compose\services\{SVC_FILE}.yaml，同时也是 profile 名
REM    SVC_SERVICES  compose 服务名（空格分隔）
REM    SVC_DEPS      需要先启动的其他服务文件名（空格分隔，可为空）
REM    SVC_VOLUMES   命名数据卷，不带 yudao_ 前缀（空格分隔，可为空）
REM    SVC_INFO      启动后显示的访问地址（可为空）
REM  参数：up / down / restart / rebuild / status / logs，不带参数进入菜单
REM ============================================================
chcp 936 >nul
setlocal enabledelayedexpansion
REM ---- 修复环境 PATH 缺失 System32 导致 chcp/where 不可用（仅本进程生效，不改系统全局环境） ----
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0\;%PATH%"

REM 仓库根目录 = 本脚本的上两级，.env 放在根目录
for %%i in ("%~dp0..\..") do set "ROOT=%%~fi"
cd /d "%ROOT%"
REM 数据卷名前缀 = compose 项目名（服务文件中的 name: yudao），实际卷名为 yudao_卷名
set VOLUME_PREFIX=yudao
set "ENV_OPT="
if exist ".env" set "ENV_OPT=--env-file .env"
set "CMD=docker compose -f compose\services\%SVC_FILE%.yaml %ENV_OPT% --profile %SVC_FILE%"
set "INTERACTIVE="

where docker >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 docker 命令，请确认 Docker Desktop 已启动并加入 PATH。
    exit /b 1
)

set "ACTION=%~1"
if "%ACTION%"=="" goto :menu
for %%a in (up down restart rebuild status logs) do if /i "%ACTION%"=="%%a" goto :do_%%a
echo [错误] 未知操作：%ACTION%（可用：up down restart rebuild status logs）
exit /b 1

:menu
set "INTERACTIVE=1"
cls
echo ========================================
echo   %SVC_TITLE%（Docker Compose）
echo   配置文件: compose\services\%SVC_FILE%.yaml
echo ========================================
echo     1. 启动          2. 停止（可选删除数据卷）
echo     3. 重启          4. 强制重建（改了镜像 / 环境变量后用）
echo     5. 查看状态      6. 查看日志（Ctrl+C 退出）
echo     0. 退出
echo ========================================
set "choice="
set /p choice=请输入选项并回车:
if "%choice%"=="1" goto :do_up
if "%choice%"=="2" goto :do_down
if "%choice%"=="3" goto :do_restart
if "%choice%"=="4" goto :do_rebuild
if "%choice%"=="5" goto :do_status
if "%choice%"=="6" goto :do_logs
if "%choice%"=="0" exit /b 0
echo [提示] 无效选项，请重新输入。
timeout /t 1 >nul
goto :menu

:do_up
echo.
for %%d in (%SVC_DEPS%) do (
    echo [信息] 先启动依赖：%%d
    docker compose -f compose\services\%%d.yaml %ENV_OPT% --profile %%d up -d
)
echo [信息] 启动 %SVC_TITLE%...
%CMD% up -d %SVC_SERVICES%
if defined SVC_INFO echo [信息] !SVC_INFO!
goto :done

:do_down
echo.
echo [信息] 停止 %SVC_TITLE%...
if "%SVC_VOLUMES%"=="" (
    %CMD% stop %SVC_SERVICES%
    goto :done
)
echo [提示] 相关数据卷：%SVC_VOLUMES%
set "rmvol=N"
set /p rmvol=是否同时删除容器和数据卷？删除后数据不可恢复 (y/N，默认 N):
if /i not "!rmvol!"=="Y" (
    %CMD% stop %SVC_SERVICES%
    echo [完成] 已停止，数据卷已保留。
    goto :done
)
%CMD% rm -s -f %SVC_SERVICES%
for %%v in (%SVC_VOLUMES%) do (
    docker volume inspect %VOLUME_PREFIX%_%%v >nul 2>nul && docker volume rm %VOLUME_PREFIX%_%%v
)
echo [完成] 已停止并删除容器和数据卷。
goto :done

:do_restart
echo.
echo [信息] 重启 %SVC_TITLE%...
%CMD% restart %SVC_SERVICES%
goto :done

:do_rebuild
echo.
echo [信息] 强制重建 %SVC_TITLE%...
%CMD% up -d --force-recreate %SVC_SERVICES%
goto :done

:do_status
echo.
%CMD% ps -a %SVC_SERVICES%
goto :done

:do_logs
echo.
echo [信息] %SVC_TITLE% 日志，Ctrl+C 退出。
%CMD% logs -f --tail 200 %SVC_SERVICES%
goto :done

:done
if defined INTERACTIVE (
    echo.
    pause
    goto :menu
)
exit /b 0
