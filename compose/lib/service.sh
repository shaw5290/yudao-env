#!/usr/bin/env bash
# ============================================================
#  单服务公共逻辑（Docker Compose），不要直接运行
#  由 compose/services/<服务>.sh 设置以下变量后 source 本脚本：
#    SVC_TITLE     显示名称
#    SVC_FILE      服务文件名：compose/services/<SVC_FILE>.yaml，同时也是 profile 名
#    SVC_SERVICES  compose 服务名（数组）
#    SVC_DEPS      需要先启动的其他服务文件名（数组，可为空）
#    SVC_VOLUMES   命名数据卷，不带 yudao_ 前缀（数组，可为空）
#    SVC_INFO      启动后显示的访问地址（可为空）
#  参数：up / down / restart / rebuild / status / logs，不带参数进入菜单
#  WSL 中未开启 Docker Desktop 集成时，可指定 DOCKER="/mnt/c/Program Files/Docker/Docker/resources/bin/docker.exe"
# ============================================================
set -uo pipefail

# 仓库根目录 = 本脚本的上两级，.env 放在根目录
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1
DOCKER="${DOCKER:-docker}"
# 数据卷名前缀 = compose 项目名（服务文件中的 name: yudao），实际卷名为 yudao_卷名
VOLUME_PREFIX="yudao"
ENV_OPT=()
[ -f .env ] && ENV_OPT=(--env-file .env)
CMD=("$DOCKER" compose -f "compose/services/$SVC_FILE.yaml" "${ENV_OPT[@]}" --profile "$SVC_FILE")
INTERACTIVE=""

if ! command -v "$DOCKER" >/dev/null 2>&1; then
    echo "[错误] 未找到 docker 命令，请确认 Docker 已启动并加入 PATH（WSL 中可设置 DOCKER 指向 docker.exe）。"
    exit 1
fi

pause() { read -rp "按回车键继续..." _; }

do_up() {
    echo
    local d
    for d in "${SVC_DEPS[@]}"; do
        echo "[信息] 先启动依赖：$d"
        "$DOCKER" compose -f "compose/services/$d.yaml" "${ENV_OPT[@]}" --profile "$d" up -d
    done
    echo "[信息] 启动 $SVC_TITLE..."
    "${CMD[@]}" up -d "${SVC_SERVICES[@]}"
    [ -n "$SVC_INFO" ] && echo "[信息] $SVC_INFO"
}

do_down() {
    echo
    echo "[信息] 停止 $SVC_TITLE..."
    if [ "${#SVC_VOLUMES[@]}" -eq 0 ]; then
        "${CMD[@]}" stop "${SVC_SERVICES[@]}"
        return
    fi
    echo "[提示] 相关数据卷：${SVC_VOLUMES[*]}"
    local rmvol
    read -rp "是否同时删除容器和数据卷？删除后数据不可恢复 (y/N，默认 N): " rmvol
    if [[ "${rmvol^^}" != "Y" ]]; then
        "${CMD[@]}" stop "${SVC_SERVICES[@]}"
        echo "[完成] 已停止，数据卷已保留。"
        return
    fi
    "${CMD[@]}" rm -s -f "${SVC_SERVICES[@]}"
    local v
    for v in "${SVC_VOLUMES[@]}"; do
        "$DOCKER" volume inspect "${VOLUME_PREFIX}_$v" >/dev/null 2>&1 && "$DOCKER" volume rm "${VOLUME_PREFIX}_$v"
    done
    echo "[完成] 已停止并删除容器和数据卷。"
}

do_restart() { echo; echo "[信息] 重启 $SVC_TITLE..."; "${CMD[@]}" restart "${SVC_SERVICES[@]}"; }
do_rebuild() { echo; echo "[信息] 强制重建 $SVC_TITLE..."; "${CMD[@]}" up -d --force-recreate "${SVC_SERVICES[@]}"; }
do_status() { echo; "${CMD[@]}" ps -a "${SVC_SERVICES[@]}"; }
do_logs() {
    echo
    echo "[信息] $SVC_TITLE 日志，Ctrl+C 退出。"
    trap ':' INT   # Ctrl+C 只结束日志跟随，不退出脚本
    "${CMD[@]}" logs -f --tail 200 "${SVC_SERVICES[@]}"
    trap - INT
}

menu() {
    INTERACTIVE=1
    while true; do
        clear
        echo "========================================"
        echo "  $SVC_TITLE（Docker Compose）"
        echo "  配置文件: compose/services/$SVC_FILE.yaml"
        echo "========================================"
        echo "    1. 启动          2. 停止（可选删除数据卷）"
        echo "    3. 重启          4. 强制重建（改了镜像 / 环境变量后用）"
        echo "    5. 查看状态      6. 查看日志（Ctrl+C 退出）"
        echo "    0. 退出"
        echo "========================================"
        local choice
        read -rp "请输入选项并回车: " choice
        case "$choice" in
            1) do_up ;;
            2) do_down ;;
            3) do_restart ;;
            4) do_rebuild ;;
            5) do_status ;;
            6) do_logs ;;
            0) exit 0 ;;
            *) echo "[提示] 无效选项，请重新输入。"; sleep 1; continue ;;
        esac
        echo
        pause
    done
}

case "${1:-}" in
    "") menu ;;
    up|down|restart|rebuild|status|logs) "do_$1" ;;
    *) echo "[错误] 未知操作：$1（可用：up down restart rebuild status logs）"; exit 1 ;;
esac
