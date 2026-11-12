@echo off
REM ============================================================
REM  单服务公共逻辑（Kubernetes），不要直接运行
REM  由 k8s\services\{服务}.bat 设置以下变量后 call 本脚本：
REM    SVC_TITLE        显示名称
REM    SVC_FILE         服务文件名：k8s\services\{SVC_FILE}.yaml
REM    SVC_DEPLOYMENTS  Deployment 名（与同名 Service 一起启停，空格分隔）
REM    SVC_PVCS         PVC 名（停止时可选删除，空格分隔，可为空）
REM    SVC_DEPS         一起部署的依赖服务文件名（空格分隔，可为空）
REM    SVC_INFO         启动后显示的访问地址（可为空）
REM    SVC_SECRET_NAME / SVC_SECRET_FILE / SVC_SECRET_KEY
REM                     启动前把仓库内文件同步为 Secret（文件不存在则跳过，可为空）
REM  部署方式：生成单服务临时方案 k8s\.render\{SVC_FILE}\kustomization.yaml（依赖 + 本服务 + base），
REM            与 k8s\schemes\* 一样经 kustomize 渲染后 apply，保证与方案部署结果一致
REM  参数：up / down / restart / rebuild / status / logs，不带参数进入菜单
REM  kubectl 上下文默认 docker-desktop，用其他集群时先 set K8S_CONTEXT={上下文名}
REM ============================================================
chcp 936 >nul
setlocal enabledelayedexpansion
REM ---- 修复环境 PATH 缺失 System32 导致 chcp/where 不可用（仅本进程生效，不改系统全局环境） ----
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0\;%PATH%"

REM 仓库根目录 = 本脚本的上两级，.env 放在根目录
for %%i in ("%~dp0..\..") do set "ROOT=%%~fi"
cd /d "%ROOT%"
set NAMESPACE=yudao
set ENV_FILE=.env
if not defined K8S_CONTEXT set K8S_CONTEXT=docker-desktop
REM 所有 kubectl 调用都显式指定上下文，避免误操作当前默认上下文指向的其他集群
set "KC=kubectl --context %K8S_CONTEXT%"
set "LABELS=%SVC_DEPLOYMENTS: =,%"
set "INTERACTIVE="

kubectl version --client >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 kubectl 命令，请确认 Docker Desktop 的 Kubernetes 已启用（设置 → Kubernetes → Enable Kubernetes）。
    exit /b 1
)
kubectl config get-contexts %K8S_CONTEXT% >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 kubectl 上下文 %K8S_CONTEXT%。请在 Docker Desktop 中启用 Kubernetes；使用其他集群时先 set K8S_CONTEXT=上下文名。
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
echo   %SVC_TITLE%（Kubernetes）
echo   清单文件: k8s\services\%SVC_FILE%.yaml    上下文: %K8S_CONTEXT%    命名空间: %NAMESPACE%
echo ========================================
echo     1. 启动          2. 停止（可选删除数据卷 PVC）
echo     3. 重启          4. 强制重建（重新 apply + rollout restart）
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
call :apply
if errorlevel 1 goto :done
if defined SVC_INFO echo [信息] !SVC_INFO!
goto :done

:do_down
echo.
echo [信息] 停止 %SVC_TITLE%...
set "TARGETS="
for %%d in (%SVC_DEPLOYMENTS%) do set "TARGETS=!TARGETS! deployment/%%d service/%%d"
%KC% delete!TARGETS! -n %NAMESPACE% --ignore-not-found
if "%SVC_PVCS%"=="" goto :done
echo [提示] 相关数据卷（PVC）：%SVC_PVCS%
set "rmvol=N"
set /p rmvol=是否同时删除数据卷？删除后数据不可恢复 (y/N，默认 N):
if /i not "!rmvol!"=="Y" (
    echo [完成] 已停止，数据卷已保留。
    goto :done
)
%KC% delete pvc %SVC_PVCS% -n %NAMESPACE% --ignore-not-found
echo [完成] 已停止并删除数据卷。
goto :done

:do_restart
echo.
echo [信息] 重启 %SVC_TITLE%...
set "TARGETS="
for %%d in (%SVC_DEPLOYMENTS%) do set "TARGETS=!TARGETS! deployment/%%d"
%KC% rollout restart!TARGETS! -n %NAMESPACE%
goto :done

:do_rebuild
echo.
call :apply
if errorlevel 1 goto :done
set "TARGETS="
for %%d in (%SVC_DEPLOYMENTS%) do set "TARGETS=!TARGETS! deployment/%%d"
%KC% rollout restart!TARGETS! -n %NAMESPACE%
goto :done

:do_status
echo.
%KC% get deployment,service %SVC_DEPLOYMENTS% -n %NAMESPACE% --ignore-not-found
%KC% get pods -n %NAMESPACE% -l "app in (%LABELS%)" -o wide
goto :done

:do_logs
echo.
echo [信息] %SVC_TITLE% 日志，Ctrl+C 退出。
%KC% logs -f -n %NAMESPACE% -l "app in (%LABELS%)" --prefix --tail 200 --max-log-requests 10
goto :done

REM ---- 下发清单：namespace → Secret → 单服务临时方案（依赖 + 本服务 + base） ----
:apply
if not exist "%ENV_FILE%" (
    echo [错误] 未找到 %ENV_FILE%，请先在仓库根目录 copy .env.temp .env 并按需修改。
    exit /b 1
)
%KC% apply -f k8s\base\namespace.yaml
%KC% create secret generic yudao-env --from-env-file=%ENV_FILE% -n %NAMESPACE% --dry-run=client -o yaml | %KC% apply -f -
if defined SVC_SECRET_NAME if exist "%SVC_SECRET_FILE%" (
    %KC% create secret generic %SVC_SECRET_NAME% --from-file=%SVC_SECRET_KEY%=%SVC_SECRET_FILE% -n %NAMESPACE% --dry-run=client -o yaml | %KC% apply -f -
)
set "RENDER=k8s\.render\%SVC_FILE%"
if not exist "%RENDER%" mkdir "%RENDER%"
(
    echo # 由 k8s\lib\service.bat 自动生成的单服务临时方案，不提交
    echo apiVersion: kustomize.config.k8s.io/v1beta1
    echo kind: Kustomization
    echo resources:
    for %%d in (%SVC_DEPS%) do echo   - ../../services/%%d.yaml
    echo   - ../../services/%SVC_FILE%.yaml
    echo components:
    echo   - ../../base
) > "%RENDER%\kustomization.yaml"
if not "%SVC_DEPS%"=="" echo [信息] 一起部署依赖：%SVC_DEPS%
echo [信息] 部署 %SVC_TITLE%...
%KC% kustomize --load-restrictor LoadRestrictionsNone %RENDER% | %KC% apply -f -
exit /b 0

:done
if defined INTERACTIVE (
    echo.
    pause
    goto :menu
)
exit /b 0
