# AGENTS.md

本文件为 AI 编码助手（Claude Code、Codex、Cursor 等）在 `yudao-env` 仓库工作时的指引，人类开发者也可当作速查手册。

> 回答与提交信息默认使用**中文**。

## Project Overview

`yudao-env` 是芋道 `yudao-cloud` 的**本地开发依赖环境**，只有编排配置、初始化 SQL 和管理脚本，没有业务代码：

- **Docker Compose**：主编排文件 `docker-compose-yudao.yaml`（compose 项目名 `name: yudao`），一键拉起 MySQL、Redis 核心依赖，Nacos、TDengine、Nginx 等其余服务均为按 profile 单独启停的中间件。
- **Kubernetes**：`k8s/` 下是一套等价清单，目标环境是 Docker Desktop 自带的单节点 Kubernetes。
- **Windows 管理脚本**：`toggle-yudao.bat`（Compose 版）和 `toggle-yudao-k8s.bat`（K8s 版），交互式菜单，负责启停、日志、数据库备份还原。
- **数据库初始化**：`mysql/initdb/` 下的 SQL 在 MySQL 空卷首次初始化时自动执行。

独立仓库，远程是 `https://gitee.com/imshaw/yudao-env.git`。它同时作为聚合仓库 `yudao` 的子模块使用（目录 `yudao-env/`）。

### 服务清单（以 `docker-compose-yudao.yaml` 为准）

核心服务（`docker compose up -d` 默认启动，不需要 profile）：

| 服务 | 镜像 | 宿主机端口变量（`.env.temp` 默认值）→ 容器端口 | 卷 |
|---|---|---|---|
| mysql | `mysql:8.0.21` | `MYSQL_PORT`(3306) → 3306 | `mysql-data`、`mysql-log`；绑定挂载 `./mysql/conf`、`./mysql/initdb`（只读） |
| redis | `redis:7` | `REDIS_PORT`(6379) → 6379 | 无（未持久化） |

可选中间件（需要 `--profile <name>`）：

| 服务 | 镜像 | profile | 宿主机端口变量（默认值）→ 容器端口 | 卷 |
|---|---|---|---|---|
| nginx | `nginx:latest` | `nginx` | `NGINX_PORT`(80) → 80 | 无（预留，未配置站点） |
| nacos | `nacos/nacos-server:v3.0.3` | `nacos` | `NACOS_PORT`(8848) → 8848；`NACOS_CONSOLE_PORT`(8080) → 8080；`NACOS_GRPC_PORT`(9848) → 9848；`NACOS_GRPC_PORT_2`(9849) → 9849 | `nacos-logs`、`nacos-plugins`、`nacos-data` |
| tdengine | `tdengine/tdengine:3.3.6.0` | `tdengine` | `TDENGINE_PORT`(6041，缺省也是 6041) → 6041（taosAdapter REST/WebSocket）；6030 → 6030（taosd 原生端口，写死） | `tdengine-data`、`tdengine-log` |
| jenkins | `jenkins/jenkins:lts` | `jenkins` | `JENKINS_PORT`(8089) → 8080（避开 Nacos 控制台的 8080） | `jenkins-home`；绑定挂载 `/var/run/docker.sock`、`/usr/bin/docker` |
| minio | `minio/minio:latest` | `minio` | `MINIO_PORT`(9000) → 9000；`MINIO_CONSOLE_PORT`(9001) → 9001 | `minio-data` |
| rocketmq-namesrv | `apache/rocketmq:5.3.1` | `rocketmq` | `ROCKETMQ_NAMESRV_PORT`(9876) → 9876 | `rocketmq-namesrv-logs` |
| rocketmq-broker | `apache/rocketmq:5.3.1` | `rocketmq` | `ROCKETMQ_BROKER_PORT`(10911) → 10911；`ROCKETMQ_BROKER_VIP_PORT`(10909) → 10909 | `rocketmq-broker-logs`、`rocketmq-broker-store`；绑定挂载 `./rocketmq/broker/conf/broker.conf` |
| xxl-job-admin | `xuxueli/xxl-job-admin:2.4.1` | `xxl-job` | `XXL_JOB_PORT`(8088) → 8080 | `xxl-job-logs` |
| seata-server | `seataio/seata-server:2.0.0` | `seata` | `SEATA_PORT`(8091) → 8091；`SEATA_DASHBOARD_PORT`(7091) → 7091 | 绑定挂载 `./seata/resources` |
| sentinel-dashboard | `bladex/sentinel-dashboard:1.8.8` | `sentinel` | `SENTINEL_PORT`(8858) → 8858 | `sentinel-logs` |
| lgtm | `grafana/otel-lgtm:0.37.0` | `lgtm` | `LGTM_GRAFANA_PORT`(3000) → 3000（Grafana）；`LGTM_OTLP_GRPC_PORT`(4317) → 4317；`LGTM_OTLP_HTTP_PORT`(4318) → 4318 | `lgtm-data` |

依赖关系：`nacos`、`xxl-job-admin` 依赖 `mysql`；`seata-server` 依赖 `nacos` 和 `mysql`（注册/配置中心都走 Nacos，`SEATA_GROUP`）；`rocketmq-broker` 依赖 `rocketmq-namesrv`。容器名为 `${PROJECT_NAME}-<服务名>`，`PROJECT_NAME` 留空时就是服务名。

### `.env.temp` 变量（只列变量名）

| 分组 | 变量 |
|---|---|
| 项目 | `PROJECT_NAME` |
| 端口 | `NGINX_PORT`、`MYSQL_PORT`、`REDIS_PORT`、`NACOS_PORT`、`NACOS_CONSOLE_PORT`、`NACOS_GRPC_PORT`、`NACOS_GRPC_PORT_2`、`JENKINS_PORT`、`MINIO_PORT`、`MINIO_CONSOLE_PORT`、`ROCKETMQ_NAMESRV_PORT`、`ROCKETMQ_BROKER_PORT`、`ROCKETMQ_BROKER_VIP_PORT`、`XXL_JOB_PORT`、`SEATA_PORT`、`SEATA_DASHBOARD_PORT`、`SENTINEL_PORT`、`TDENGINE_PORT`、`POSTGRES_PORT`、`LGTM_GRAFANA_PORT`、`LGTM_OTLP_GRPC_PORT`、`LGTM_OTLP_HTTP_PORT` |
| MySQL | `MYSQL_ROOT_PASSWORD` |
| Redis | `REDIS_PASSWORD` |
| Nacos 连接 MySQL | `NACOS_DB_NAME`、`NACOS_DB_USER`、`NACOS_DB_PASSWORD` |
| Nacos 鉴权 | `NACOS_AUTH_ENABLE`、`NACOS_AUTH_TOKEN`、`NACOS_AUTH_IDENTITY_KEY`、`NACOS_AUTH_IDENTITY_VALUE` |
| MinIO | `MINIO_ROOT_USER`、`MINIO_ROOT_PASSWORD` |
| RocketMQ | `ROCKETMQ_BROKER_IP`（宿主机 IP，不能写 `127.0.0.1`） |
| XXL-Job | `XXL_JOB_DB_NAME` |
| Seata | `SEATA_IP`（宿主机 IP） |

## Setup Commands

前置条件：Windows + Docker Desktop（WSL2 后端）；使用 K8s 版本时需在 Docker Desktop 里启用 Kubernetes。

```bat
:: 1. 复制环境变量模板，按需修改（.env 不提交）
copy .env.temp .env

:: 2. 交互式管理（Compose 版 / K8s 版），双击或在 cmd 中运行
toggle-yudao.bat
toggle-yudao-k8s.bat
```

必须修改的变量：`MYSQL_ROOT_PASSWORD`、`REDIS_PASSWORD`、`NACOS_DB_PASSWORD`、`NACOS_AUTH_TOKEN`、`MINIO_ROOT_PASSWORD`、`ROCKETMQ_BROKER_IP`、`SEATA_IP`。`NACOS_AUTH_TOKEN` 需要 Base64 编码的 32 字节密钥：

```bash
openssl rand -base64 32
```

不用脚本、直接执行 Compose 命令（与 `toggle-yudao.bat` 内部命令一致）：

```bash
# 核心服务
docker compose -f docker-compose-yudao.yaml up -d --build
docker compose -f docker-compose-yudao.yaml ps
docker compose -f docker-compose-yudao.yaml logs -f
docker compose -f docker-compose-yudao.yaml up -d --build --force-recreate   # 改了镜像/环境变量后强制重建

# 单个中间件
docker compose -f docker-compose-yudao.yaml --profile minio up -d minio
docker compose -f docker-compose-yudao.yaml --profile minio stop minio
docker compose -f docker-compose-yudao.yaml --profile rocketmq up -d          # namesrv + broker

# 停止全部（含所有 profile，保留数据卷）
docker compose -f docker-compose-yudao.yaml --profile jenkins --profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel down
```

K8s 版（与 `toggle-yudao-k8s.bat` 内部命令一致）：

```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl create secret generic yudao-env --from-env-file=.env -n yudao --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/01-mysql.yaml -f k8s/02-redis.yaml -f k8s/03-nacos.yaml -f k8s/04-tdengine.yaml -f k8s/05-nginx.yaml
kubectl get pods,svc -n yudao -o wide
kubectl apply -f k8s/11-minio.yaml                                           # 单独启动某个中间件
kubectl delete deployment/minio service/minio -n yudao --ignore-not-found    # 停止中间件（不删 PVC）
```

### 管理脚本菜单

两个脚本的菜单编号一致：

| 编号 | `toggle-yudao.bat`（Compose） | `toggle-yudao-k8s.bat`（K8s） |
|---|---|---|
| 1 | 启动核心（mysql/redis），`up -d --build mysql redis` | apply namespace + 同步 Secret `yudao-env` + apply `01`~`05` 清单 |
| 2 | 停止全部（含所有 profile，`down`，保留卷），需 Y 确认 | 删除命名空间内所有 Deployment/Service，保留 PVC，需 Y 确认 |
| 3 | 重启核心（`stop` + `up -d --build`，只作用于 mysql/redis） | `kubectl rollout restart` 核心 Deployment |
| 4 | 查看所有服务状态 | `kubectl get pods,svc -o wide` |
| 5 | 查看核心服务日志（`logs -f`） | 输入 Deployment 名后 `kubectl logs -f` |
| 6 | 强制重建核心（`--force-recreate`） | 重新 apply 核心清单 + rollout restart |
| 7 / 8 | 启动 / 停止全部中间件（`8` 用 `stop`，不影响 mysql/redis） | 同左（apply / delete `10`~`15` 清单的 Deployment、Service） |
| 9 | `down -v` 清空所有数据卷，需输入 `DELETE` | `kubectl delete pvc --all -n yudao`，需输入 `DELETE` |
| 10~19 / 20~29、40 / 50 | 启动 / 停止 TDengine（10/20）、MinIO、RocketMQ、XXL-Job、Seata、Sentinel、Jenkins、PostgreSQL、Nacos（18/28）、Grafana LGTM（19/29）、Nginx（40/50），仅 18/28、10/20、40/50 为 Compose 版独有 | 11~17、19 / 21~27、29 同左 |
| 31 | 备份所有非系统库到 `backups/mysql_<时间戳>.sql` | 同左（`kubectl exec deploy/mysql`） |
| 32 | 从 `backups/` 选择文件还原 | 同左 |
| 33 | 查看备份文件列表 | 同左 |
| 34 | 查看当前数据库列表 | 同左 |
| 0 | 退出 | 退出 |

## Database Commands

### MySQL 初始化

`mysql/initdb/` 挂载到容器的 `/docker-entrypoint-initdb.d`，按文件名顺序执行，**只在 `mysql-data` 卷为空时执行一次**：

| 脚本 | 内容 |
|---|---|
| `01-create-databases.sql` | 建库 `ruoyi-vue-pro`、`nacos`、`xxl_job`、`seata`、`quartz`，创建 Nacos 使用的 MySQL 用户并授权 |
| `02-nacos-schema.sql` | Nacos 表结构，预置 `dev` / `test` / `prod` 命名空间（`tenant_info`） |
| `03-xxl-job-schema.sql` | `USE xxl_job;` XXL-Job 表结构 |
| `04-seata-schema.sql` | `USE seata;` Seata 表结构 |
| `05-yudao-schema.sql` | `USE \`ruoyi-vue-pro\`;` yudao-cloud 业务主库（约 2MB） |
| `06-yudao-quartz.sql` | `USE \`ruoyi-vue-pro\`;` Quartz 表及预置任务 |

业务主库名是 **`ruoyi-vue-pro`**（不是 `yudao`）；`quartz` 库是历史遗留，当前不使用。

需要重新执行 initdb 时（会删除所有数据，先备份）：

```bash
docker compose -f docker-compose-yudao.yaml --profile jenkins --profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel down -v
docker compose -f docker-compose-yudao.yaml up -d
```

### 备份与还原

推荐用脚本菜单 `31`~`34`。脚本内部等价于：

```bat
:: 备份（排除 information_schema mysql performance_schema sys）
docker exec yudao-mysql mysqldump -uroot -p<密码> --default-character-set=utf8mb4 --single-transaction --routines --triggers --events --databases <库列表> > backups\mysql_<时间戳>.sql

:: 还原
docker exec -i yudao-mysql mysql -uroot -p<密码> < backups\mysql_<时间戳>.sql
```

- 脚本开头写死了 `DB_CONTAINER=yudao-mysql`、`DB_USER`、`DB_PASSWORD`、`BACKUP_DIR=backups`；`DB_CONTAINER` 依赖 `PROJECT_NAME=yudao`，`DB_PASSWORD` 必须与 `.env` 的 `MYSQL_ROOT_PASSWORD` 一致，否则备份失败。
- K8s 版用 `kubectl exec -n yudao deploy/mysql` 代替 `docker exec`，两个脚本生成的备份文件可以互相还原。
- `backups/` 目录已提交了一份完整备份 `mysql_20260921_529.sql`；新备份是否提交由用户决定。

### TDengine（IoT 模块）

IoT 模块只建超级表，不会自动建库，容器首次启动后手动执行一次（数据持久化在 `tdengine-data` 卷）：

```bash
docker exec -it yudao-tdengine taos -s "CREATE DATABASE IF NOT EXISTS ruoyi_vue_pro;"
```

应用侧还需要在 `yudao-cloud` 的 `yudao-module-iot-server` 的 `application-local.yaml` 中取消注释 `spring.datasource.dynamic.datasource.tdengine`，IoT 模块通过 `jdbc:TAOS-WS://` 连接 6041 端口。

### Redis / Nacos

- Redis 用 `--requirepass ${REDIS_PASSWORD}` 启动，未挂载数据卷，容器重建后数据丢失。
- Nacos 以 `standalone` 模式持久化到 MySQL 的 `${NACOS_DB_NAME}` 库，健康检查地址为容器内 `http://localhost:8080/nacos/actuator/health`。

## Code Style Guidelines

本仓库没有程序代码，以下是各类文件的编写约定，以现有文件为准。

### Docker Compose（`docker-compose-yudao.yaml`）

- 2 空格缩进；服务顺序为核心服务在前，可选中间件放在 `# ==================== 以下均需 --profile 才启动 ====================` 分隔注释之后。
- 每个服务都写 `container_name: ${PROJECT_NAME:+${PROJECT_NAME}-}<服务名>` 和 `restart: always`。
- 端口一律用 `.env` 变量映射：`"${XXX_PORT}:<容器端口>"`，带引号；新增端口时同步在 `.env.temp` 的端口区加变量和默认值，并同步 `k8s/` 对应清单的 `hostPort`。
- 敏感信息只通过 `${VAR}` 引用，不在 compose 中写字面量。
- 运行时数据用**命名卷**（`<服务>-data` / `<服务>-logs` 等），并在文件末尾 `volumes:` 中声明；只有需要挂载仓库内真实文件的配置/脚本才用 `./` 相对路径绑定挂载。
- 除 mysql/redis 外的服务都用 `profiles: ["<name>"]`，profile 名与服务名对应（`nginx`、`nacos`、`tdengine`、`jenkins`、`minio`、`rocketmq`、`xxl-job`、`seata`、`sentinel`、`postgres`、`lgtm`）；新增 profile 时同步更新 `toggle-yudao.bat` 开头的 `ALL_PROFILES` / `MIDDLEWARE_SERVICES` 和菜单，以及 `toggle-yudao-k8s.bat`。
- 分节注释格式：`# ==================== 标题 ====================`；需要说明的端口用行尾中文注释。
- 时区统一 `TZ: Asia/Shanghai`；JVM 参数写在 `JAVA_OPTS` / `JAVA_OPT_EXT`，多行时用 `>-`。

### 环境变量模板（`.env.temp`）

- 分组标题格式：`# ================= 分组 =================`，每组上方用中文注释说明用途和约束。
- 变量名全大写下划线；端口变量统一 `XXX_PORT` 结尾，集中放在端口区。
- 模板里的密码/Token 只是占位示例，不要把真实值写进模板；新增变量时同步 README 和本文件。

### Kubernetes 清单（`k8s/`）

- 文件名两位数字前缀：`00` Namespace，`01`~`05` 核心服务，`10`~`15` 可选中间件；每个文件包含该服务的 PVC、Deployment、Service，用 `---` 分隔。
- 所有资源 `namespace: yudao`，资源名与 compose 服务名一致（`mysql`、`nacos`、`xxl-job-admin`、`seata-server` 等），标签 `app: <名称>`。
- Deployment 固定 `replicas: 1`，有 PVC 的用 `strategy.type: Recreate`。
- 端口用 `hostPort` 字面量（K8s 不支持变量替换），写 `.env.temp` 的默认值，并在行尾注释对应的 `.env` 变量，例如 `hostPort: 3306   # 对应 .env 的 MYSQL_PORT，冲突时改这里`。
- 敏感值通过 Secret `yudao-env`（由脚本从 `.env` 生成）注入：整体用 `envFrom.secretRef`，单个用 `secretKeyRef: { name: yudao-env, key: XXX }`。
- 数据卷用 PVC（走 Docker Desktop 默认 StorageClass）；挂载仓库文件用 `hostPath`，路径格式 `/run/desktop/mnt/host/<盘符小写>/<路径>`。
- 服务间互访用 Service 名（如 `mysql`、`nacos:8848`、`rocketmq-namesrv:9876`），并加注释 `# k8s Service 名`。

### Windows 批处理（`toggle-yudao*.bat`）

- 文件编码 **GBK（ANSI）**，开头 `chcp 936 >nul`；换行符 **CRLF**。不要转成 UTF-8 或 LF。
- 固定开头：`@echo off`、`setlocal enabledelayedexpansion`、`cd /d %~dp0`、修复 PATH（补回 `%SystemRoot%\System32` 等）。
- 可调参数集中在开头用 `set` 定义（`COMPOSE_FILE`、`CMD`、`NAMESPACE`、`K8S_DIR`、`DB_*`、`BACKUP_DIR`）。
- 菜单项用 `if "%choice%"=="N" goto :label` 分发，每个功能一个 `:label` 段，以 `pause` + `goto :menu` 结束；标签命名为小写下划线（如 `:minio_up`、`:db_backup`）。
- 用 `REM ================= 分组 =================` 分隔功能段；提示信息前缀 `[信息]`、`[错误]`、`[警告]`、`[取消]`、`[完成]`、`[成功]`。
- 危险操作必须二次确认：一般操作要求输入 `Y`，删除数据卷要求输入 `DELETE`。
- 两个脚本的菜单编号保持一一对应，改一个时同步另一个。

### SQL（`mysql/initdb/`）

- 文件名两位数字前缀决定执行顺序；建库、建用户集中在 `01-create-databases.sql`，其余脚本第一行 `USE <库名>;`。
- 建库统一 `DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`，使用 `IF NOT EXISTS`。
- `05-yudao-schema.sql`、`06-yudao-quartz.sql` 来自 `yudao-cloud/sql/mysql/`，更新时从上游整体同步，不要手工零散修改。

### 换行符与编码现状

- 现有 YAML、SQL、`.env.temp`、`README.md` 均为 **CRLF**，bat 为 **GBK + CRLF**。修改已有文件时保持原换行符，避免整个文件出现在 diff 里；本文件（`AGENTS.md`）为 LF + UTF-8。
- 本仓库没有自己的 `.editorconfig`；作为聚合仓库子模块打开时会继承上层 `.editorconfig`（`end_of_line = lf`、`charset = utf-8`），编辑器可能自动改写 bat 的编码和换行，需特别注意。

## Project Structure

```
yudao-env/
├── docker-compose-yudao.yaml   # 主编排文件（compose 项目名 yudao，核心服务 + profile 中间件）
├── .env.temp                   # 环境变量模板（提交）；复制为 .env 使用（不提交）
├── toggle-yudao.bat            # Compose 版管理菜单：启停 / 日志 / 中间件 / 备份还原
├── toggle-yudao-k8s.bat        # K8s 版管理菜单，编号与上面一致
├── README.md                   # 使用说明
├── .gitignore                  # 忽略运行时数据、日志、.env 等
├── mysql/
│   └── initdb/                 # MySQL 首次初始化脚本（01 建库建用户 ~ 06 Quartz）
├── backups/                    # 数据库备份输出目录（mysql_<时间戳>.sql）
└── k8s/
    ├── 00-namespace.yaml       # Namespace yudao
    ├── 01-mysql.yaml           # PVC + Deployment + Service（hostPath 挂载 mysql/conf、mysql/initdb）
    ├── 02-redis.yaml
    ├── 03-nacos.yaml
    ├── 04-tdengine.yaml
    ├── 05-nginx.yaml
    ├── 10-jenkins.yaml         # 10~15 为可选中间件，默认不 apply
    ├── 11-minio.yaml
    ├── 12-rocketmq.yaml        # namesrv + broker
    ├── 13-xxljob.yaml
    ├── 14-seata.yaml
    ├── 15-sentinel.yaml
    ├── 16-postgres.yaml
    └── 17-lgtm.yaml            # Grafana LGTM（OTel Collector + Loki + Tempo + Prometheus + Grafana）
```

compose 引用但**当前仓库中不存在**的路径（`.gitignore` 已放行，需要时自行创建）：

- `mysql/conf/`：MySQL 自定义配置（可选）。
- `rocketmq/broker/conf/broker.conf`：RocketMQ broker 配置（启用 `rocketmq` profile 前必须准备）。
- `seata/resources/`：Seata 配置（启用 `seata` profile 前需要准备）。

<!-- TODO: 补充 broker.conf 与 seata/resources 的参考配置或获取方式 -->

## Testing Instructions

### CI 现状

<!-- TODO: 补充 CI 配置；当前仓库没有任何 CI 流水线文件 -->

### 变更验证

不要为了验证而实际启动容器或修改正在运行的环境，优先用静态校验：

```bash
# 校验 compose 语法和变量替换（用模板，不依赖 .env；--quiet 不输出含密码的展开结果）
docker compose -f docker-compose-yudao.yaml --env-file .env.temp config --quiet

# 列出所有 profile 下的服务，确认新增/改名的服务和 profile 生效
docker compose -f docker-compose-yudao.yaml --env-file .env.temp --profile jenkins --profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel config --services

# 列出命名卷
docker compose -f docker-compose-yudao.yaml --env-file .env.temp config --volumes

# K8s 清单客户端校验（不提交到集群）
kubectl apply --dry-run=client -f k8s/
```

- 在 WSL 中如果提示 `docker` 找不到（Docker Desktop 未开启 WSL integration），可直接调用 Windows 侧的可执行文件，例如 `"/mnt/c/Program Files/Docker/Docker/resources/bin/docker.exe"`，同目录下也有 `kubectl.exe`。
- bat 脚本无法静态校验：修改后用 `file toggle-yudao.bat` 确认仍是 `CRLF line terminators`，并在 Windows cmd 中实际打开菜单检查中文显示和跳转。
- 改端口/变量时，用 `grep` 交叉核对 `docker-compose-yudao.yaml`、`.env.temp`、`k8s/*.yaml`、两个 bat 脚本、`README.md` 是否一致。
- 改 initdb 脚本时，可在一次性的空卷环境中验证；不要对用户现有的 `mysql-data` 卷执行 `down -v`。

### 合并前最低要求

1. `docker compose ... config --quiet` 通过（退出码 0）。
2. 改动 `k8s/` 时 `kubectl apply --dry-run=client -f k8s/` 通过。
3. `git diff` 只包含实际改动，没有因换行符或编码变化导致的整文件 diff。
4. compose、`.env.temp`、K8s 清单、bat 菜单、README 中的端口/变量/profile 保持同步。
5. 没有提交 `.env` 或任何真实密码、Token。

## PR Instructions

- 提交信息采用 Conventional Commits，描述用中文：

  ```
  <type>(<scope>): <中文描述>
  ```

  - `type`：`feat` / `fix` / `docs` / `chore` / `refactor` / `perf` / `test` / `style`
  - `scope` 示例（取自本仓库历史）：`docker-compose`、`k8s`、`tdengine`、`database`、`mysql`、`menu`、`script`、`config`、`backup`、`README`
  - 示例：`fix(tdengine): 更新 TDengine 镜像版本为 3.3.6.0`、`feat(menu): 新增停止全部并清空数据卷选项`
- 提交前确认当前在具体分支上（`git branch --show-current` 有输出），**不要在游离 HEAD 上提交**；作为子模块检出时默认是游离 HEAD，需先 `git checkout <分支>`。
- 未经用户确认不要 `git push` 到远程。
- 作为聚合仓库子模块时，先在本仓库提交并推送，再由聚合仓库更新子模块指针。
- <!-- TODO: 补充 issue 关联规范 -->
- <!-- TODO: 补充 code review / 合并要求 -->

## Security Notes

- **`.env` 不提交**（已在 `.gitignore` 中，同样忽略 `.env.local`、`docker-compose.override.yml`）。AI 助手不要读取或修改 `.env`。
- **默认口令必须修改**：`.env.temp` 中的密码/Token 只是示例值；另外以下位置存在硬编码口令，修改密码时需要同步：
  - `mysql/initdb/01-create-databases.sql` 中创建 Nacos MySQL 用户的密码，须与 `.env` 的 `NACOS_DB_PASSWORD` 一致；
  - `toggle-yudao.bat`、`toggle-yudao-k8s.bat` 开头的 `DB_PASSWORD`，须与 `MYSQL_ROOT_PASSWORD` 一致。
  - 不要在文档、提交信息或日志中写出任何口令的实际值。
- **端口暴露**：所有服务都把端口映射到宿主机所有网卡（compose 的 `ports` 未绑定 `127.0.0.1`，K8s 用 `hostPort`），只适合本地开发，不要在公网或共享网络中直接使用。
- **Jenkins 权限**：jenkins 以 `user: root` 运行并挂载 `/var/run/docker.sock`，等同于拥有宿主机 Docker 控制权；Nacos 使用 `privileged: true`。
- **Nacos 鉴权**：`NACOS_AUTH_TOKEN` 用 `openssl rand -base64 32` 生成，不要复用模板值。
- **备份文件含业务数据**：`backups/*.sql` 是完整数据库导出，提交前确认不含敏感数据。
- K8s 的 Secret `yudao-env` 由 `.env` 整体生成，包含全部变量，不要导出或提交其 YAML。

## Common Issues

### 修改了 initdb 脚本但没有生效

原因：`/docker-entrypoint-initdb.d` 只在 `mysql-data` 卷为空时执行，重启或重建容器不会重跑。
解决：先用菜单 `31` 备份，再用菜单 `9`（`down -v`，K8s 版为删除 PVC）清空数据卷后重新启动；或者手动在现有库上执行需要的 SQL。

### Nacos 端口冲突 / 与 IDEA 内嵌 Nacos 冲突

原因：docker 化的 Nacos 与 IDEA 运行配置 `NacosServerApplication`（yudao-cloud 内嵌 Nacos）使用相同的端口：服务 8848、控制台 8080（`NACOS_CONSOLE_PORT`）、gRPC 9848 / 9849。两者设计上二选一，同时启动必然端口冲突。Jenkins 默认映射到 8089（`JENKINS_PORT`），不占用 8080；如果本地 `.env` 是从旧模板复制的，可能仍是 `NACOS_CONSOLE_PORT=8081`、`JENKINS_PORT=8080`，需要手工改成 8080、8089。
解决：两套 Nacos 只启动一套；控制台统一访问 `http://127.0.0.1:8080`。

### Nacos 容器启动即退出（exit 255）

原因：`NACOS_AUTH_TOKEN`、`NACOS_AUTH_IDENTITY_KEY`、`NACOS_AUTH_IDENTITY_VALUE` 任意一个为空，镜像启动脚本会直接退出；`NACOS_AUTH_TOKEN` 也必须是 Base64 编码的 32 字节字符串。
解决：三个变量都填值，Token 用 `openssl rand -base64 32` 生成。

### Nacos 连接 MySQL 失败

原因：`NACOS_DB_PASSWORD` 与 `01-create-databases.sql` 中为 Nacos 用户设置的密码不一致，或 MySQL 尚未完成首次初始化（`depends_on` 只保证启动顺序，不等待就绪）。
解决：统一两处密码；首次启动等 MySQL 初始化完成后再重启 nacos。

### CRLF / 编码导致 bat 脚本异常

原因：bat 文件必须是 GBK + CRLF。在 WSL 或上层 `.editorconfig`（LF + UTF-8）影响下被转成 LF 或 UTF-8 后，cmd 可能出现 `goto` 找不到标签、命令被截断、中文乱码等问题。
解决：用 `file toggle-yudao.bat` 检查，应显示 `CRLF line terminators`；编辑时显式选择 GBK 编码和 CRLF 换行；如已损坏，可用 `git checkout -- toggle-yudao.bat` 恢复后重新修改。

### 备份失败或提示容器未运行

原因：脚本写死 `DB_CONTAINER=yudao-mysql`，若 `.env` 的 `PROJECT_NAME` 不是 `yudao`，容器名会不同；或脚本中的 `DB_PASSWORD` 与 `MYSQL_ROOT_PASSWORD` 不一致。
解决：修改脚本开头的 `DB_CONTAINER` / `DB_PASSWORD`。另外备份文件名的时间戳取自 `date /t` 和 `%time%`，格式依赖系统区域设置（如小时不补零），属于已知现象。

### RocketMQ broker 或 Seata 起不来

原因：compose 绑定挂载 `./rocketmq/broker/conf/broker.conf` 和 `./seata/resources`，但这两个路径当前不在仓库中。路径不存在时 Docker 会创建同名**目录**，broker 因读不到配置文件而失败；`ROCKETMQ_BROKER_IP` 在 compose 中没有被引用，需要写进 `broker.conf`（`brokerIP1`）才会生效。
解决：启用 profile 前先准备好 `broker.conf`（如已误建为目录则先删除）和 `seata/resources/` 下的配置。

### K8s 版 hostPath 挂载失败

原因：`k8s/01-mysql.yaml`、`12-rocketmq.yaml`、`14-seata.yaml` 中的 `hostPath` 写死为 `/run/desktop/mnt/host/d/sourceCode/yudao/env/...`，与当前仓库位置不同（如 `D:\workspace\yudao\yudao-env` 对应 `/run/desktop/mnt/host/d/workspace/yudao/yudao-env/...`）。`mysql/initdb` 使用 `type: Directory`，路径不存在时 Pod 无法启动。
解决：把所有 `hostPath.path` 改成实际路径的映射（盘符小写）。

### 改了 `.env` 端口但 K8s 版没有变化

原因：K8s 的 `hostPort` 是字面量，不读 `.env`。
解决：直接修改 `k8s/*.yaml` 中对应的 `hostPort`，行尾注释标明了对应的变量。

### IoT 服务启动失败（TDengine）

原因：TDengine 库未创建，或应用侧 TDengine 数据源被注释，`TDengineTableInitRunner` 初始化失败后进程退出。
解决：执行上文 `CREATE DATABASE IF NOT EXISTS ruoyi_vue_pro;`，并在 IoT 模块的 `application-local.yaml` 中启用 TDengine 数据源；容器名随 `PROJECT_NAME` 变化。

### `chcp` / `where` / `docker` 不是内部或外部命令

原因：系统 PATH 缺少 `C:\Windows\System32`。脚本开头已临时补回，若仍报错说明系统级 PATH 被破坏，或 Docker Desktop 未安装/未启动。
解决：在“编辑系统环境变量”中修复 PATH；确认 Docker Desktop 正在运行。

### WSL 中提示 `docker` 找不到

原因：Docker Desktop 未对当前 WSL 发行版开启集成。
解决：在 Docker Desktop → Settings → Resources → WSL integration 中开启，或直接调用 `"/mnt/c/Program Files/Docker/Docker/resources/bin/docker.exe"`。

### 应用连接的数据库名对不上

原因：主库名是 `ruoyi-vue-pro`，不是 `yudao`。
解决：确认 `yudao-cloud` 各服务 `application-local.yaml` 的数据源 URL 使用 `ruoyi-vue-pro`。
