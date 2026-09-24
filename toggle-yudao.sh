#!/usr/bin/env bash
# yudao-cloud Docker 管理脚本（对应 toggle-yudao.bat）
set -uo pipefail

cd "$(dirname "$0")"

COMPOSE_FILE="docker-compose-yudao.yaml"
CMD=(docker compose -f "$COMPOSE_FILE")

# ---- 数据库备份配置 ----
DB_CONTAINER="yudao-mysql"
DB_USER="root"
DB_PASSWORD="123456"
BACKUP_DIR="backups"
# 默认排除的系统库
DB_EXCLUDE=(information_schema mysql performance_schema sys)

ALL_PROFILES=(--profile jenkins --profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel --profile postgres)
SIDE_PROFILES=(--profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel --profile jenkins --profile postgres)

# ---- 前置检查 ----
if ! command -v docker >/dev/null 2>&1; then
    echo "[错误] 未找到 docker，请确认已安装并加入 PATH。"
    exit 1
fi
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "[错误] 未找到配置文件 $COMPOSE_FILE"
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

# ================= 核心 =================
start() {
    echo
    echo "[信息] 启动核心服务..."
    "${CMD[@]}" up -d --build
    "${CMD[@]}" ps
    echo
    pause
}

stop() {
    echo
    if ! confirm "确认停止并移除核心服务及所有侧车服务？(Y/N): "; then
        echo "[取消] 已取消。"
        sleep 1
        return
    fi
    docker compose -f "$COMPOSE_FILE" "${ALL_PROFILES[@]}" down
    echo
    echo "[完成] 已全部停止。"
    pause
}

stop_v() {
    echo
    echo "[警告] 此操作将停止并删除所有容器，同时删除所有数据卷（mysql-data、nacos-data、minio-data、jenkins-home 等），数据将无法恢复！"
    echo "[提示] 若需保留数据，请先用菜单选项 31 备份数据库。"
    read -rp "请输入 DELETE 以确认执行 down -v：" ans
    if [[ "$ans" != "DELETE" ]]; then
        echo "[取消] 已取消。"
        sleep 1
        return
    fi
    docker compose -f "$COMPOSE_FILE" "${ALL_PROFILES[@]}" down -v
    echo
    echo "[完成] 已停止并清空数据卷。"
    pause
}

restart() {
    echo
    echo "[信息] 重启核心服务..."
    "${CMD[@]}" down
    "${CMD[@]}" up -d --build
    "${CMD[@]}" ps
    echo
    pause
}

status() {
    echo
    echo "[信息] 所有服务状态："
    docker compose -f "$COMPOSE_FILE" "${ALL_PROFILES[@]}" ps
    echo
    pause
}

logs() {
    echo
    echo "[信息] 核心服务日志（Ctrl+C 退出后回菜单）："
    "${CMD[@]}" logs -f
    echo
    pause
}

rebuild() {
    echo
    echo "[信息] 强制重建核心服务..."
    "${CMD[@]}" up -d --build --force-recreate
    "${CMD[@]}" ps
    echo
    pause
}

start_with_postgres() {
    echo
    echo "[信息] 启动核心服务 + PostgreSQL..."
    docker compose -f "$COMPOSE_FILE" --profile postgres up -d --build
    docker compose -f "$COMPOSE_FILE" --profile postgres ps
    echo
    pause
}

# ================= 全部侧车 =================
profile_all_up() {
    echo
    echo "[信息] 启动所有侧车服务..."
    docker compose -f "$COMPOSE_FILE" "${SIDE_PROFILES[@]}" up -d
    docker compose -f "$COMPOSE_FILE" "${ALL_PROFILES[@]}" ps
    echo
    pause
}

profile_all_down() {
    echo
    echo "[信息] 正在停止所有侧车服务..."
    docker compose -f "$COMPOSE_FILE" "${SIDE_PROFILES[@]}" down
    echo
    echo "[完成] 侧车服务全部停止。"
    pause
}

# ================= MinIO =================
minio_up() { echo; echo "[信息] 启动 MinIO..."; "${CMD[@]}" --profile minio up -d minio; pause; }
minio_down() { echo; echo "[信息] 停止 MinIO..."; "${CMD[@]}" --profile minio stop minio; pause; }

# ================= RocketMQ =================
rocketmq_up() { echo; echo "[信息] 启动 RocketMQ (namesrv + broker)..."; "${CMD[@]}" --profile rocketmq up -d; pause; }
rocketmq_down() { echo; echo "[信息] 停止 RocketMQ..."; "${CMD[@]}" --profile rocketmq stop; pause; }

# ================= XXL-Job =================
xxljob_up() { echo; echo "[信息] 启动 XXL-Job..."; "${CMD[@]}" --profile xxl-job up -d xxl-job-admin; pause; }
xxljob_down() { echo; echo "[信息] 停止 XXL-Job..."; "${CMD[@]}" --profile xxl-job stop xxl-job-admin; pause; }

# ================= Seata =================
seata_up() { echo; echo "[信息] 启动 Seata..."; "${CMD[@]}" --profile seata up -d seata-server; pause; }
seata_down() { echo; echo "[信息] 停止 Seata..."; "${CMD[@]}" --profile seata stop seata-server; pause; }

# ================= Sentinel =================
sentinel_up() { echo; echo "[信息] 启动 Sentinel Dashboard..."; "${CMD[@]}" --profile sentinel up -d sentinel-dashboard; pause; }
sentinel_down() { echo; echo "[信息] 停止 Sentinel Dashboard..."; "${CMD[@]}" --profile sentinel stop sentinel-dashboard; pause; }

# ================= Jenkins =================
jenkins_up() { echo; echo "[信息] 启动 Jenkins..."; "${CMD[@]}" --profile jenkins up -d jenkins; pause; }
jenkins_down() { echo; echo "[信息] 停止 Jenkins..."; "${CMD[@]}" --profile jenkins stop jenkins; pause; }

# ================= PostgreSQL =================
postgres_up() { echo; echo "[信息] 启动 PostgreSQL..."; "${CMD[@]}" --profile postgres up -d postgres; pause; }
postgres_down() { echo; echo "[信息] 停止 PostgreSQL..."; "${CMD[@]}" --profile postgres stop postgres; pause; }

# ================= 数据库备份 =================
db_backup() {
    echo
    local running
    running=$(docker inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null || true)
    if [[ "$running" != "true" ]]; then
        echo "[错误] 容器 $DB_CONTAINER 未运行或不存在。"
        echo
        echo "当前运行的容器："
        docker ps --format "  {{.Names}}  {{.Status}}"
        pause
        return
    fi

    echo "[信息] 正在获取数据库列表..."
    local db_list=()
    while IFS= read -r db; do
        is_excluded "$db" || db_list+=("$db")
    done < <(docker exec "$DB_CONTAINER" mysql -u"$DB_USER" -p"$DB_PASSWORD" -N -e "SHOW DATABASES;" 2>/dev/null)

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
    echo "  容器: $DB_CONTAINER"
    echo "  文件: $file"
    echo

    if docker exec "$DB_CONTAINER" mysqldump \
        -u"$DB_USER" -p"$DB_PASSWORD" \
        --default-character-set=utf8mb4 \
        --single-transaction \
        --routines --triggers --events \
        --databases "${db_list[@]}" > "$file"; then
        echo "[成功] 备份完成，大小 $(stat -c%s "$file" 2>/dev/null || wc -c < "$file") 字节"
        echo "[路径] $(pwd)/$file"
    else
        echo "[错误] 备份失败，请检查容器与密码。"
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
    if docker exec -i "$DB_CONTAINER" mysql -u"$DB_USER" -p"$DB_PASSWORD" < "$file"; then
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
    docker exec "$DB_CONTAINER" mysql -u"$DB_USER" -p"$DB_PASSWORD" -e "SHOW DATABASES;" 2>/dev/null
    echo
    echo "业务数据的（排除系统库 ${DB_EXCLUDE[*]}）："
    while IFS= read -r db; do
        is_excluded "$db" || echo "  $db"
    done < <(docker exec "$DB_CONTAINER" mysql -u"$DB_USER" -p"$DB_PASSWORD" -N -e "SHOW DATABASES;" 2>/dev/null)
    echo
    pause
}

menu() {
    clear
    cat <<EOF
========================================
  yudao-cloud Docker 管理菜单
  配置文件: $COMPOSE_FILE
========================================
  核心服务
    1. 启动核心    (nginx/mysql/redis/nacos/tdengine)
    2. 停止全部    (含所有 profile)
    3. 重启核心
    4. 查看状态    (所有服务)
    5. 查看日志    (核心服务)
    6. 强制重建    (核心服务)
    10. 启动核心+PostgreSQL (核心服务再加上 PostgreSQL)

  侧车服务（按需启停）
    11. 启动 MinIO          21. 停止 MinIO
    12. 启动 RocketMQ       22. 停止 RocketMQ
    13. 启动 XXL-Job        23. 停止 XXL-Job
    14. 启动 Seata          24. 停止 Seata
    15. 启动 Sentinel       25. 停止 Sentinel
    16. 启动 Jenkins        26. 停止 Jenkins
    17. 启动 PostgreSQL     27. 停止 PostgreSQL

    7. 启动全部侧车        8. 停止全部侧车
    9. 停止全部并清空数据卷 (down -v，危险！会删除所有数据)

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
        9) stop_v ;;
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
        31) db_backup ;;
        32) db_restore ;;
        33) db_list_backups ;;
        34) db_show ;;
        0) echo; echo "已退出。"; sleep 1; exit 0 ;;
        *) echo; echo "[提示] 无效选项，请重新输入。"; sleep 1 ;;
    esac
done
