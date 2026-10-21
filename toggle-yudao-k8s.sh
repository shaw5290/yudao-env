#!/usr/bin/env bash
# yudao-cloud Kubernetes 管理脚本（对应 toggle-yudao-k8s.bat）
set -uo pipefail

cd "$(dirname "$0")"

NAMESPACE="yudao"
K8S_DIR="k8s"
ENV_FILE=".env"

# ---- 数据库备份配置 ----
DB_DEPLOY="deploy/mysql"
DB_USER="root"
DB_PASSWORD="123456"
BACKUP_DIR="backups"
# 默认排除的系统库
DB_EXCLUDE=(information_schema mysql performance_schema sys)

CORE_FILES=("$K8S_DIR/01-mysql.yaml" "$K8S_DIR/02-redis.yaml" "$K8S_DIR/03-nacos.yaml" "$K8S_DIR/04-tdengine.yaml" "$K8S_DIR/05-nginx.yaml")

# ---- 前置检查 ----
if ! kubectl version --client >/dev/null 2>&1; then
    echo "[错误] 未找到 kubectl，请确认 Kubernetes 集群可用（如已在 Docker Desktop 中启用 Kubernetes）。"
    exit 1
fi
if [ ! -d "$K8S_DIR" ]; then
    echo "[错误] 未找到 $K8S_DIR 目录"
    exit 1
fi
if [ ! -f "$ENV_FILE" ]; then
    echo "[错误] 未找到 $ENV_FILE，请先 cp .env.temp .env 并按需修改"
    exit 1
fi

pause() { read -rp "按回车键继续..." _; }

confirm() {
    local prompt="$1" ans
    read -rp "$prompt" ans
    [[ "${ans^^}" == "Y" ]]
}

is_excluded() {
    local db="$1" e
    for e in "${DB_EXCLUDE[@]}"; do
        [[ "$db" == "$e" ]] && return 0
    done
    return 1
}

sync_secret() {
    kubectl create secret generic yudao-env --from-env-file="$ENV_FILE" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

# ================= 核心 =================
start() {
    echo
    echo "[信息] 启动核心服务..."
    kubectl apply -f "$K8S_DIR/00-namespace.yaml"
    sync_secret
    kubectl apply -f "${CORE_FILES[@]}"
    kubectl get pods -n "$NAMESPACE"
    echo
    pause
}

stop() {
    echo
    if ! confirm "确认停止核心 Deployment/Service（不含数据卷与侧车服务）？(Y/N): "; then
        echo "[取消] 已取消。"
        sleep 1
        return
    fi
    kubectl delete deployment,service --all -n "$NAMESPACE" --ignore-not-found
    echo
    echo "[完成] 已全部停止，PVC 数据卷仍保留。"
    pause
}

wipe_pvc() {
    echo
    echo "[警告] 此操作将删除命名空间 $NAMESPACE 下所有 PVC（mysql-data、nacos-data、minio-data、jenkins-home 等），数据将无法恢复！"
    echo "[提示] 若需保留数据，请先用菜单选项 31 备份数据库。"
    read -rp "请输入 DELETE 以确认清空所有数据卷：" ans
    if [[ "$ans" != "DELETE" ]]; then
        echo "[取消] 已取消。"
        sleep 1
        return
    fi
    kubectl delete pvc --all -n "$NAMESPACE"
    echo
    echo "[完成] 已清空所有数据卷。"
    pause
}

restart() {
    echo
    echo "[信息] 重启核心服务..."
    kubectl rollout restart deployment/mysql deployment/redis deployment/nacos deployment/tdengine deployment/nginx -n "$NAMESPACE"
    kubectl get pods -n "$NAMESPACE"
    echo
    pause
}

status() {
    echo
    echo "[信息] 所有服务状态："
    kubectl get pods,svc -n "$NAMESPACE" -o wide
    echo
    pause
}

logs() {
    echo
    read -rp "请输入 Deployment 名称（如 mysql / nacos / redis / tdengine / nginx，Ctrl+C 退出后回菜单）: " dep
    kubectl logs -n "$NAMESPACE" "deploy/$dep" -f
    echo
    pause
}

rebuild() {
    echo
    echo "[信息] 重新下发所有清单并强制重启..."
    kubectl apply -f "$K8S_DIR/00-namespace.yaml"
    sync_secret
    kubectl apply -f "${CORE_FILES[@]}"
    kubectl rollout restart deployment/mysql deployment/redis deployment/nacos deployment/tdengine deployment/nginx -n "$NAMESPACE"
    kubectl get pods -n "$NAMESPACE"
    echo
    pause
}

start_with_postgres() {
    echo
    echo "[信息] 启动核心服务 + PostgreSQL..."
    kubectl apply -f "$K8S_DIR/00-namespace.yaml"
    sync_secret
    kubectl apply -f "${CORE_FILES[@]}" -f "$K8S_DIR/16-postgres.yaml"
    kubectl get pods -n "$NAMESPACE"
    echo
    pause
}

# ================= 全部侧车 =================
profile_all_up() {
    echo
    echo "[信息] 启动所有侧车服务..."
    kubectl apply -f "$K8S_DIR/10-jenkins.yaml" -f "$K8S_DIR/11-minio.yaml" -f "$K8S_DIR/12-rocketmq.yaml" -f "$K8S_DIR/13-xxljob.yaml" -f "$K8S_DIR/14-seata.yaml" -f "$K8S_DIR/15-sentinel.yaml" -f "$K8S_DIR/16-postgres.yaml" -f "$K8S_DIR/17-lgtm.yaml"
    kubectl get pods -n "$NAMESPACE"
    echo
    pause
}

profile_all_down() {
    echo
    echo "[信息] 正在停止所有侧车服务并清理相关资源..."
    kubectl delete deployment/jenkins service/jenkins deployment/minio service/minio deployment/rocketmq-namesrv service/rocketmq-namesrv deployment/rocketmq-broker service/rocketmq-broker deployment/xxl-job-admin service/xxl-job-admin deployment/seata-server service/seata-server deployment/sentinel-dashboard service/sentinel-dashboard deployment/postgres service/postgres deployment/lgtm service/lgtm -n "$NAMESPACE" --ignore-not-found
    echo
    echo "[完成] 侧车服务全部停止。"
    pause
}

# ================= MinIO =================
minio_up() { echo; echo "[信息] 启动 MinIO..."; kubectl apply -f "$K8S_DIR/11-minio.yaml"; pause; }
minio_down() { echo; echo "[信息] 停止 MinIO..."; kubectl delete deployment/minio service/minio -n "$NAMESPACE" --ignore-not-found; pause; }

# ================= RocketMQ =================
rocketmq_up() { echo; echo "[信息] 启动 RocketMQ (namesrv + broker)..."; kubectl apply -f "$K8S_DIR/12-rocketmq.yaml"; pause; }
rocketmq_down() { echo; echo "[信息] 停止 RocketMQ..."; kubectl delete deployment/rocketmq-namesrv service/rocketmq-namesrv deployment/rocketmq-broker service/rocketmq-broker -n "$NAMESPACE" --ignore-not-found; pause; }

# ================= XXL-Job =================
xxljob_up() { echo; echo "[信息] 启动 XXL-Job..."; kubectl apply -f "$K8S_DIR/13-xxljob.yaml"; pause; }
xxljob_down() { echo; echo "[信息] 停止 XXL-Job..."; kubectl delete deployment/xxl-job-admin service/xxl-job-admin -n "$NAMESPACE" --ignore-not-found; pause; }

# ================= Seata =================
seata_up() { echo; echo "[信息] 启动 Seata..."; kubectl apply -f "$K8S_DIR/14-seata.yaml"; pause; }
seata_down() { echo; echo "[信息] 停止 Seata..."; kubectl delete deployment/seata-server service/seata-server -n "$NAMESPACE" --ignore-not-found; pause; }

# ================= Sentinel =================
sentinel_up() { echo; echo "[信息] 启动 Sentinel Dashboard..."; kubectl apply -f "$K8S_DIR/15-sentinel.yaml"; pause; }
sentinel_down() { echo; echo "[信息] 停止 Sentinel Dashboard..."; kubectl delete deployment/sentinel-dashboard service/sentinel-dashboard -n "$NAMESPACE" --ignore-not-found; pause; }

# ================= Jenkins =================
jenkins_up() { echo; echo "[信息] 启动 Jenkins..."; kubectl apply -f "$K8S_DIR/10-jenkins.yaml"; pause; }
jenkins_down() { echo; echo "[信息] 停止 Jenkins..."; kubectl delete deployment/jenkins service/jenkins -n "$NAMESPACE" --ignore-not-found; pause; }

# ================= PostgreSQL =================
postgres_up() { echo; echo "[信息] 启动 PostgreSQL..."; kubectl apply -f "$K8S_DIR/16-postgres.yaml"; pause; }
postgres_down() { echo; echo "[信息] 停止 PostgreSQL..."; kubectl delete deployment/postgres service/postgres -n "$NAMESPACE" --ignore-not-found; pause; }

# ================= Grafana LGTM =================
lgtm_up() {
    echo; echo "[信息] 启动 Grafana LGTM（OTel Collector + Loki + Tempo + Prometheus + Grafana）..."
    kubectl apply -f "$K8S_DIR/17-lgtm.yaml"
    echo "[信息] Grafana 控制台：http://127.0.0.1:3000（admin / admin），OTLP HTTP 上报地址：http://127.0.0.1:4318"
    pause
}
lgtm_down() { echo; echo "[信息] 停止 Grafana LGTM..."; kubectl delete deployment/lgtm service/lgtm -n "$NAMESPACE" --ignore-not-found; pause; }

# ================= 数据库备份 =================
db_backup() {
    echo
    local running
    running=$(kubectl get deploy/mysql -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    if [[ "$running" != "1" ]]; then
        echo "[错误] mysql Deployment 未就绪或不存在。"
        echo
        echo "当前 Pod 状态："
        kubectl get pods -n "$NAMESPACE"
        pause
        return
    fi

    echo "[信息] 正在获取数据库列表..."
    local db_list=()
    while IFS= read -r db; do
        is_excluded "$db" || db_list+=("$db")
    done < <(kubectl exec -n "$NAMESPACE" "$DB_DEPLOY" -- mysql -u"$DB_USER" -p"$DB_PASSWORD" -N -e "SHOW DATABASES;" 2>/dev/null)

    if [ "${#db_list[@]}" -eq 0 ]; then
        echo "[错误] 未发现任何非默认数据库。"
        pause
        return
    fi

    echo
    echo "  库数据：${db_list[*]}"
    echo

    mkdir -p "$BACKUP_DIR"
    local stamp file
    stamp=$(date +%Y%m%d_%H%M%S)
    file="$BACKUP_DIR/mysql_${stamp}.sql"

    echo "[信息] 正在备份..."
    echo "  Deployment: $DB_DEPLOY"
    echo "  文件: $file"
    echo

    if kubectl exec -n "$NAMESPACE" "$DB_DEPLOY" -- mysqldump \
        -u"$DB_USER" -p"$DB_PASSWORD" \
        --default-character-set=utf8mb4 \
        --single-transaction \
        --routines --triggers --events \
        --databases "${db_list[@]}" > "$file"; then
        echo "[成功] 备份完成，大小 $(stat -c%s "$file" 2>/dev/null || wc -c < "$file") 字节"
        echo "[路径] $(pwd)/$file"
    else
        echo "[错误] 备份失败，请检查 Pod 状态与密码。"
    fi
    echo
    pause
}

# ================= 数据库还原 =================
db_restore() {
    echo
    echo "可用的备份文件："
    ls -t "$BACKUP_DIR"/*.sql 2>/dev/null
    echo
    read -rp "请输入要还原的 SQL 文件路径（如 $BACKUP_DIR/mysql_20260921_120000.sql）: " file

    if [ ! -f "$file" ]; then
        echo "[错误] 文件不存在: $file"
        pause
        return
    fi

    echo
    echo "[警告] 还原会覆盖同名库的数据！"
    if ! confirm "确认还原？(Y/N): "; then
        echo "[取消] 已取消。"
        pause
        return
    fi

    echo
    echo "[信息] 正在还原 $file ..."
    if kubectl exec -i -n "$NAMESPACE" "$DB_DEPLOY" -- mysql -u"$DB_USER" -p"$DB_PASSWORD" < "$file"; then
        echo "[成功] 还原完成。"
    else
        echo "[错误] 还原失败。"
    fi
    echo
    pause
}

# ================= 备份列表 =================
db_list_backups() {
    echo
    echo "备份文件列表（按时间倒序）："
    ls -lt "$BACKUP_DIR"/*.sql 2>/dev/null
    echo
    pause
}

# ================= 查看数据库 =================
db_show() {
    echo
    echo "所有数据库："
    kubectl exec -n "$NAMESPACE" "$DB_DEPLOY" -- mysql -u"$DB_USER" -p"$DB_PASSWORD" -e "SHOW DATABASES;" 2>/dev/null
    echo
    echo "业务数据的（排除系统库 ${DB_EXCLUDE[*]}）："
    while IFS= read -r db; do
        is_excluded "$db" || echo "  $db"
    done < <(kubectl exec -n "$NAMESPACE" "$DB_DEPLOY" -- mysql -u"$DB_USER" -p"$DB_PASSWORD" -N -e "SHOW DATABASES;" 2>/dev/null)
    echo
    pause
}

menu() {
    clear
    cat <<EOF
========================================
  yudao-cloud Kubernetes 管理菜单
  命名空间: $NAMESPACE    清单目录: $K8S_DIR
========================================
  核心服务
    1. 启动核心    (nginx/mysql/redis/nacos/tdengine)
    2. 停止全部    (仅核心，不含侧车与数据卷)
    3. 重启核心    (rollout restart)
    4. 查看状态    (所有 Pod / Service)
    5. 查看日志    (指定 Deployment)
    6. 强制重建    (重新 apply 所有核心清单 + 重启)
    10. 启动核心+PostgreSQL (核心服务再加上 PostgreSQL)

  侧车服务（按需启停）
    11. 启动 MinIO          21. 停止 MinIO
    12. 启动 RocketMQ       22. 停止 RocketMQ
    13. 启动 XXL-Job        23. 停止 XXL-Job
    14. 启动 Seata          24. 停止 Seata
    15. 启动 Sentinel       25. 停止 Sentinel
    16. 启动 Jenkins        26. 停止 Jenkins
    17. 启动 PostgreSQL     27. 停止 PostgreSQL
    19. 启动 Grafana LGTM   29. 停止 Grafana LGTM

    7. 启动全部侧车        8. 停止全部侧车
    9. 清空所有数据卷 (PVC，危险！会删除所有数据)

  数据库（备份 / 还原）
    31. 备份全部库（自动排除系统库）
    32. 还原指定文件
    33. 查看备份列表
    34. 查看当前数据库

    0. 退出
========================================
EOF
    read -rp "请输入选项回车: " choice
}

while true; do
    menu
    case "$choice" in
        1) start ;;
        2) stop ;;
        3) restart ;;
        4) status ;;
        5) logs ;;
        6) rebuild ;;
        10) start_with_postgres ;;
        7) profile_all_up ;;
        8) profile_all_down ;;
        9) wipe_pvc ;;
        11) minio_up ;;
        21) minio_down ;;
        12) rocketmq_up ;;
        22) rocketmq_down ;;
        13) xxljob_up ;;
        23) xxljob_down ;;
        14) seata_up ;;
        24) seata_down ;;
        15) sentinel_up ;;
        25) sentinel_down ;;
        16) jenkins_up ;;
        26) jenkins_down ;;
        17) postgres_up ;;
        27) postgres_down ;;
        19) lgtm_up ;;
        29) lgtm_down ;;
        31) db_backup ;;
        32) db_restore ;;
        33) db_list_backups ;;
        34) db_show ;;
        0) echo; echo "已退出。"; sleep 1; exit 0 ;;
        *) echo; echo "[提示] 无效选项，请重新输入。"; sleep 1 ;;
    esac
done
