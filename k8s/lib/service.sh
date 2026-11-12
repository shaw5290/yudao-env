#!/usr/bin/env bash
# ============================================================
#  单服务公共逻辑（Kubernetes），不要直接运行
#  由 k8s/services/<服务>.sh 设置以下变量后 source 本脚本：
#    SVC_TITLE        显示名称
#    SVC_FILE         服务文件名：k8s/services/<SVC_FILE>.yaml
#    SVC_DEPLOYMENTS  Deployment 名（与同名 Service 一起启停，数组）
#    SVC_PVCS         PVC 名（停止时可选删除，数组，可为空）
#    SVC_DEPS         一起部署的依赖服务文件名（数组，可为空）
#    SVC_INFO         启动后显示的访问地址（可为空）
#    SVC_SECRET_NAME / SVC_SECRET_FILE / SVC_SECRET_KEY
#                     启动前把仓库内文件同步为 Secret（文件不存在则跳过，可为空）
#  部署方式：生成单服务临时方案 k8s/.render/<SVC_FILE>/kustomization.yaml（依赖 + 本服务 + base），
#            与 k8s/schemes/* 一样经 kustomize 渲染后 apply，保证与方案部署结果一致
#  参数：up / down / restart / rebuild / status / logs，不带参数进入菜单
#  kubectl 上下文默认 docker-desktop，用其他集群时先 export K8S_CONTEXT=<上下文名>
#  WSL 中可指定 KUBECTL="/mnt/c/Program Files/Docker/Docker/resources/bin/kubectl.exe"
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1
NAMESPACE="yudao"
ENV_FILE=".env"
K8S_CONTEXT="${K8S_CONTEXT:-docker-desktop}"
KUBECTL="${KUBECTL:-kubectl}"
# 所有 kubectl 调用都显式指定上下文，避免误操作当前默认上下文指向的其他集群
KC=("$KUBECTL" --context "$K8S_CONTEXT")
LABELS="$(IFS=,; echo "${SVC_DEPLOYMENTS[*]}")"
SVC_SECRET_NAME="${SVC_SECRET_NAME:-}"
SVC_SECRET_FILE="${SVC_SECRET_FILE:-}"
SVC_SECRET_KEY="${SVC_SECRET_KEY:-}"
INTERACTIVE=""

if ! "$KUBECTL" version --client >/dev/null 2>&1; then
    echo "[错误] 未找到 kubectl 命令，请确认 Docker Desktop 的 Kubernetes 已启用（WSL 中可设置 KUBECTL 指向 kubectl.exe）。"
    exit 1
fi
if ! "$KUBECTL" config get-contexts "$K8S_CONTEXT" >/dev/null 2>&1; then
    echo "[错误] 未找到 kubectl 上下文 $K8S_CONTEXT。请在 Docker Desktop 中启用 Kubernetes；使用其他集群时先 export K8S_CONTEXT=上下文名。"
    exit 1
fi

pause() { read -rp "按回车键继续..." _; }

# 下发清单：namespace → Secret → 单服务临时方案（依赖 + 本服务 + base）
apply_all() {
    if [ ! -f "$ENV_FILE" ]; then
        echo "[错误] 未找到 $ENV_FILE，请先在仓库根目录 cp .env.temp .env 并按需修改。"
        return 1
    fi
    "${KC[@]}" apply -f k8s/base/namespace.yaml
    "${KC[@]}" create secret generic yudao-env --from-env-file="$ENV_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | "${KC[@]}" apply -f -
    if [ -n "$SVC_SECRET_NAME" ] && [ -f "$SVC_SECRET_FILE" ]; then
        "${KC[@]}" create secret generic "$SVC_SECRET_NAME" --from-file="$SVC_SECRET_KEY=$SVC_SECRET_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | "${KC[@]}" apply -f -
    fi
    local render="k8s/.render/$SVC_FILE" d
    mkdir -p "$render"
    {
        echo "# 由 k8s/lib/service.sh 自动生成的单服务临时方案，不提交"
        echo "apiVersion: kustomize.config.k8s.io/v1beta1"
        echo "kind: Kustomization"
        echo "resources:"
        for d in "${SVC_DEPS[@]}"; do echo "  - ../../services/$d.yaml"; done
        echo "  - ../../services/$SVC_FILE.yaml"
        echo "components:"
        echo "  - ../../base"
    } > "$render/kustomization.yaml"
    [ "${#SVC_DEPS[@]}" -gt 0 ] && echo "[信息] 一起部署依赖：${SVC_DEPS[*]}"
    echo "[信息] 部署 $SVC_TITLE..."
    "${KC[@]}" kustomize --load-restrictor LoadRestrictionsNone "$render" | "${KC[@]}" apply -f -
}

deployments() { local d; for d in "${SVC_DEPLOYMENTS[@]}"; do echo "deployment/$d"; done; }

do_up() {
    echo
    apply_all || return
    [ -n "$SVC_INFO" ] && echo "[信息] $SVC_INFO"
}

do_down() {
    echo
    echo "[信息] 停止 $SVC_TITLE..."
    local targets=() d
    for d in "${SVC_DEPLOYMENTS[@]}"; do targets+=("deployment/$d" "service/$d"); done
    "${KC[@]}" delete "${targets[@]}" -n "$NAMESPACE" --ignore-not-found
    [ "${#SVC_PVCS[@]}" -eq 0 ] && return
    echo "[提示] 相关数据卷（PVC）：${SVC_PVCS[*]}"
    local rmvol
    read -rp "是否同时删除数据卷？删除后数据不可恢复 (y/N，默认 N): " rmvol
    if [[ "${rmvol^^}" != "Y" ]]; then
        echo "[完成] 已停止，数据卷已保留。"
        return
    fi
    "${KC[@]}" delete pvc "${SVC_PVCS[@]}" -n "$NAMESPACE" --ignore-not-found
    echo "[完成] 已停止并删除数据卷。"
}

do_restart() { echo; echo "[信息] 重启 $SVC_TITLE..."; "${KC[@]}" rollout restart $(deployments) -n "$NAMESPACE"; }
do_rebuild() { echo; apply_all || return; "${KC[@]}" rollout restart $(deployments) -n "$NAMESPACE"; }
do_status() {
    echo
    "${KC[@]}" get deployment,service "${SVC_DEPLOYMENTS[@]}" -n "$NAMESPACE" --ignore-not-found
    "${KC[@]}" get pods -n "$NAMESPACE" -l "app in ($LABELS)" -o wide
}
do_logs() {
    echo
    echo "[信息] $SVC_TITLE 日志，Ctrl+C 退出。"
    trap ':' INT   # Ctrl+C 只结束日志跟随，不退出脚本
    "${KC[@]}" logs -f -n "$NAMESPACE" -l "app in ($LABELS)" --prefix --tail 200 --max-log-requests 10
    trap - INT
}

menu() {
    INTERACTIVE=1
    while true; do
        clear
        echo "========================================"
        echo "  $SVC_TITLE（Kubernetes）"
        echo "  清单文件: k8s/services/$SVC_FILE.yaml    上下文: $K8S_CONTEXT    命名空间: $NAMESPACE"
        echo "========================================"
        echo "    1. 启动          2. 停止（可选删除数据卷 PVC）"
        echo "    3. 重启          4. 强制重建（重新 apply + rollout restart）"
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
