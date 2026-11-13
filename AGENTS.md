# AGENTS.md

本文件为 AI 编码助手（Claude Code、Codex、Cursor 等）在 `yudao-env` 仓库工作时的指引，人类开发者也可当作速查手册。

> 回答与提交信息默认使用**中文**。

## Project Overview

`yudao-env` 是芋道 `yudao-cloud` 的**本地开发依赖环境**，只有编排配置、初始化 SQL 和管理脚本，没有业务代码：

- **Docker Compose**（`compose/`）：每个服务一个文件 `compose/services/<服务>.yaml`，都通过 `extends` 引用公共基础配置 `compose/base.yaml`；方案 `compose/schemes/*.yaml` 用 `include` 组合服务文件（菜单使用 `all.yaml`）。compose 项目名统一 `name: yudao`，MySQL、Redis 为核心依赖，其余服务按 profile 单独启停。
- **Kubernetes**（`k8s/`）：等价清单，每个服务一个文件 `k8s/services/<服务>.yaml`；公共基础配置为 Kustomize Component `k8s/base`（namespace、公共标签）；方案 `k8s/schemes/<方案>/kustomization.yaml` 组合服务文件。目标环境是 Docker Desktop 自带的单节点 Kubernetes。
- **Windows 管理菜单**：`compose\yudao.bat`（Compose 版）和 `k8s\yudao-k8s.bat`（K8s 版），交互式菜单，负责启停、日志、数据库备份还原。只维护这两个 bat，不提供 `.sh`。
- **挂载文件**：compose 与 k8s 共用的配置/初始化脚本统一放在 `config/`；`config/mysql/initdb/` 下的 SQL 在 MySQL 空卷首次初始化时自动执行。

独立仓库，远程是 `https://gitee.com/imshaw/yudao-env.git`。它同时作为聚合仓库 `yudao` 的子模块使用（目录 `yudao-env/`）。

### 服务清单（以 `compose/services/*.yaml` 为准）

核心服务（`docker compose up -d` 默认启动，不需要 profile）：

| 服务 | 镜像 | 宿主机端口变量（`.env.temp` 默认值）→ 容器端口 | 卷 |
|---|---|---|---|
| mysql | `mysql:8.0.21` | `MYSQL_PORT`(3306) → 3306 | `mysql-data`、`mysql-log`；绑定挂载 `config/mysql/conf`、`config/mysql/initdb`（只读） |
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
| rocketmq-broker | `apache/rocketmq:5.3.1` | `rocketmq` | `ROCKETMQ_BROKER_PORT`(10911) → 10911；`ROCKETMQ_BROKER_VIP_PORT`(10909) → 10909 | `rocketmq-broker-logs`、`rocketmq-broker-store`；绑定挂载 `config/rocketmq/broker/conf/broker.conf` |
| rabbitmq | `rabbitmq:4.1-management` | `rabbitmq` | `RABBITMQ_PORT`(5672) → 5672（AMQP）；`RABBITMQ_MANAGEMENT_PORT`(15672) → 15672（管理控制台） | `rabbitmq-data`（固定 `hostname: rabbitmq`，数据目录按节点名存放） |
| xxl-job-admin | `xuxueli/xxl-job-admin:2.4.1` | `xxl-job` | `XXL_JOB_PORT`(8088) → 8080 | `xxl-job-logs` |
| seata-server | `apache/seata-server:2.5.0` | `seata` | `SEATA_PORT`(8091) → 8091；`SEATA_DASHBOARD_PORT`(7091) → 7091 | 绑定挂载 `config/seata/resources/application.yml`（只读） |
| sentinel-dashboard | `bladex/sentinel-dashboard:1.8.8` | `sentinel` | `SENTINEL_PORT`(8858) → 8858 | `sentinel-logs` |
| postgres | `postgres:16-alpine` | `postgres` | `POSTGRES_PORT`(5432) → 5432 | `postgres-data`、`postgres-log`；绑定挂载 `config/postgres/initdb`（只读） |
| lgtm | `grafana/otel-lgtm:0.37.0` | `lgtm` | `LGTM_GRAFANA_PORT`(3000) → 3000（Grafana）；`LGTM_OTLP_GRPC_PORT`(4317) → 4317；`LGTM_OTLP_HTTP_PORT`(4318) → 4318 | `lgtm-data` |
| elasticsearch | `docker.elastic.co/elasticsearch/elasticsearch:8.19.23` | `elk` | `ELASTICSEARCH_PORT`(9200) → 9200 | `elasticsearch-data` |
| logstash | `docker.elastic.co/logstash/logstash:8.19.23` | `elk` | `LOGSTASH_TCP_PORT`(5044) → 5044（tcp + json_lines，应用上报日志） | 绑定挂载 `config/elk/logstash/pipeline`（只读） |
| kibana | `docker.elastic.co/kibana/kibana:8.19.23` | `elk` | `KIBANA_PORT`(5601) → 5601 | 无 |
| nora | `ghcr.io/getnora-io/nora:1.4.4` | `nora` | `NORA_PORT`(4000) → 4000（Docker `/v2/`、Maven `/maven2/`、npm `/npm/`、Web UI `/ui/` 共用） | `nora-data`；绑定挂载 `config/nora/auth`（只读，放 `users.htpasswd`，不提交） |

依赖关系：`nacos`、`xxl-job-admin` 依赖 `mysql`；`logstash`、`kibana` 依赖 `elasticsearch`；`seata-server` 依赖 `nacos` 和 `mysql`（注册/配置中心都走 Nacos，`SEATA_GROUP`）；`rocketmq-broker` 依赖 `rocketmq-namesrv`。容器名为 `${PROJECT_NAME}-<服务名>`，`PROJECT_NAME` 未配置或留空时默认 `yudao`。

### `.env.temp` 变量（只列变量名）

| 分组 | 变量 |
|---|---|
| 项目 | `PROJECT_NAME` |
| 端口 | `NGINX_PORT`、`MYSQL_PORT`、`REDIS_PORT`、`NACOS_PORT`、`NACOS_CONSOLE_PORT`、`NACOS_GRPC_PORT`、`NACOS_GRPC_PORT_2`、`JENKINS_PORT`、`MINIO_PORT`、`MINIO_CONSOLE_PORT`、`ROCKETMQ_NAMESRV_PORT`、`ROCKETMQ_BROKER_PORT`、`ROCKETMQ_BROKER_VIP_PORT`、`RABBITMQ_PORT`、`RABBITMQ_MANAGEMENT_PORT`、`XXL_JOB_PORT`、`SEATA_PORT`、`SEATA_DASHBOARD_PORT`、`SENTINEL_PORT`、`TDENGINE_PORT`、`POSTGRES_PORT`、`LGTM_GRAFANA_PORT`、`LGTM_OTLP_GRPC_PORT`、`LGTM_OTLP_HTTP_PORT`、`ELASTICSEARCH_PORT`、`LOGSTASH_TCP_PORT`、`KIBANA_PORT`、`NORA_PORT` |
| MySQL | `MYSQL_ROOT_PASSWORD` |
| Redis | `REDIS_PASSWORD` |
| Nacos 连接 MySQL | `NACOS_DB_NAME`、`NACOS_DB_USER`、`NACOS_DB_PASSWORD` |
| Nacos 鉴权 | `NACOS_AUTH_ENABLE`、`NACOS_AUTH_TOKEN`、`NACOS_AUTH_IDENTITY_KEY`、`NACOS_AUTH_IDENTITY_VALUE` |
| MinIO | `MINIO_ROOT_USER`、`MINIO_ROOT_PASSWORD` |
| RocketMQ | `ROCKETMQ_BROKER_IP`（宿主机 IP，不能写 `127.0.0.1`） |
| RabbitMQ | `RABBITMQ_USERNAME`、`RABBITMQ_PASSWORD`（与 yudao-cloud 同名；只在数据卷首次初始化时生效） |
| NORA | `NORA_PUBLIC_URL`（npm tarball 等下载地址前缀）、`NORA_MAVEN_PROXIES`、`NORA_NPM_PROXY`、`NORA_DOCKER_PROXIES`、`NORA_AUTH_ENABLED`、`NORA_AUTH_ANONYMOUS_READ`、`NORA_AUTH_DOCKER_ANON_PULL` |
| XXL-Job | `XXL_JOB_DB_NAME` |
| Seata | `SEATA_IP`（宿主机 IP） |

## Setup Commands

前置条件：Windows + Docker Desktop（WSL2 后端）；使用 K8s 版本时需在 Docker Desktop 里启用 Kubernetes。

```bat
:: 1. 复制环境变量模板，按需修改（.env 不提交）；不建 .env 时使用 compose 中的本地开发缺省值
copy .env.temp .env

:: 2. 交互式管理（Compose 版 / K8s 版），双击或在 cmd 中运行
compose\yudao.bat
k8s\yudao-k8s.bat
```

必须修改的变量：`MYSQL_ROOT_PASSWORD`、`REDIS_PASSWORD`、`NACOS_DB_PASSWORD`、`NACOS_AUTH_TOKEN`、`MINIO_ROOT_PASSWORD`、`ROCKETMQ_BROKER_IP`、`SEATA_IP`。`NACOS_AUTH_TOKEN` 需要 Base64 编码的 32 字节密钥：

```bash
openssl rand -base64 32
```

不用菜单、直接执行 Compose 命令（在仓库根目录执行，与 `compose\yudao.bat` 内部命令一致）。服务文件在子目录中，Compose 不会自动读取根目录 `.env`，必须显式加 `--env-file .env`：

```bash
# 核心服务（方案 all.yaml 中只有 mysql、redis 没有 profile）
docker compose -f compose/schemes/all.yaml --env-file .env up -d mysql redis
docker compose -f compose/schemes/all.yaml --env-file .env ps
docker compose -f compose/schemes/all.yaml --env-file .env logs -f mysql redis
docker compose -f compose/schemes/all.yaml --env-file .env up -d --force-recreate mysql redis   # 改了镜像/环境变量后强制重建

# 单个中间件（nacos、xxl-job、seata 依赖 mysql，跨文件不写 depends_on，需先启动 mysql）
docker compose -f compose/schemes/all.yaml --env-file .env --profile minio up -d minio
docker compose -f compose/schemes/all.yaml --env-file .env --profile minio stop minio
docker compose -f compose/services/rocketmq.yaml --env-file .env --profile rocketmq up -d   # 也可以只用一个服务文件

# 停止全部（含所有 profile，保留数据卷）
docker compose -f compose/schemes/all.yaml --env-file .env --profile nginx --profile nacos --profile tdengine --profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel --profile jenkins --profile postgres --profile lgtm --profile elk --profile rabbitmq --profile nora down
```

K8s 版（与 `k8s\yudao-k8s.bat` 内部命令一致）。**所有 kubectl 命令都显式加 `--context docker-desktop`**：本机默认上下文可能指向其他集群（如线上 EKS）。方案引用了目录外的 `services/*.yaml`，必须用 `kubectl kustomize --load-restrictor LoadRestrictionsNone` 渲染后再 apply，不能用 `apply -k`：

```bash
K="kubectl --context docker-desktop"
$K apply -f k8s/base/namespace.yaml
$K create secret generic yudao-env --from-env-file=.env -n yudao --dry-run=client -o yaml | $K apply -f -
$K kustomize --load-restrictor LoadRestrictionsNone k8s/schemes/core | $K apply -f -        # 核心方案
$K get pods,svc -n yudao -o wide
$K delete deployment/minio service/minio -n yudao --ignore-not-found                      # 停止中间件（不删 PVC）
```

菜单启动单个服务时，生成临时方案 `k8s/.render/<服务>/kustomization.yaml`（`DEPS_<服务>` 中的依赖 + 本服务 + `../../base`，已在 `.gitignore`），再按上面的方式渲染并 apply。

### 管理脚本菜单

两个脚本的菜单编号一致：

| 编号 | `compose\yudao.bat`（Compose） | `k8s\yudao-k8s.bat`（K8s） |
|---|---|---|
| 1 | 启动核心（mysql/redis），`up -d mysql redis` | apply namespace + 同步 Secret `yudao-env` + 部署方案 `k8s/schemes/core`（mysql、redis、nacos、tdengine、nginx） |
| 2 | 停止全部（含所有 profile，`down`，保留卷），需 Y 确认 | 删除命名空间内所有 Deployment/Service，保留 PVC，需 Y 确认 |
| 3 | 重启核心（`stop` + `up -d`，只作用于 mysql/redis） | `kubectl rollout restart` 核心 Deployment |
| 4 | 查看所有服务状态 | `kubectl get pods,svc -o wide` |
| 5 | 查看核心服务日志（`logs -f`） | 输入 Deployment 名后 `kubectl logs -f` |
| 6 | 强制重建核心（`--force-recreate`） | 重新部署核心方案 + rollout restart |
| 7 / 8 | 启动全部中间件（连同 mysql/redis 一起 `up -d`）/ 停止全部中间件（`stop`，不影响 mysql/redis） | 部署方案 `k8s/schemes/middleware` / 删除中间件的 Deployment、Service（保留 PVC） |
| 9 | `down -v` 清空所有数据卷，需输入 `DELETE` | `kubectl delete pvc --all -n yudao`，需输入 `DELETE` |
| 10~19 / 20~29、40~43 / 50~53 | 启动 / 停止 TDengine（10/20）、MinIO、RocketMQ、XXL-Job、Seata、Sentinel、Jenkins、PostgreSQL、Nacos（18/28）、Grafana LGTM（19/29）、Nginx（40/50）、ELK（41/51）、RabbitMQ（42/52）、NORA（43/53），仅 18/28、10/20、40/50 为 Compose 版独有；启动经子程序 `:svc_up`（先启动 `DEPS_<服务>` 中的依赖），停止经 `:svc_down` 询问是否删除数据卷（默认 N 只 `stop`；`y` 则 `rm -s -f` 后 `docker volume rm yudao_<卷名>`），无命名卷的 Seata、Nginx 直接 `stop` | 11~17、19、41~43 / 21~27、29、51~53 同左；`10` 为启动核心 + PostgreSQL。启动生成单服务临时方案部署，停止只删 Deployment/Service；启动前若存在 `config\nora\auth\users.htpasswd`，同步为 Secret `nora-htpasswd` |
| 31 | 备份所有非系统库到 `backups/mysql_<时间戳>.sql` | 同左（`kubectl exec deploy/mysql`） |
| 32 | 从 `backups/` 选择文件还原 | 同左 |
| 33 | 查看备份文件列表 | 同左 |
| 34 | 查看当前数据库列表 | 同左 |
| 0 | 退出 | 退出 |

## Database Commands

### MySQL 初始化

`config/mysql/initdb/` 挂载到容器的 `/docker-entrypoint-initdb.d`，按文件名顺序执行，**只在 `mysql-data` 卷为空时执行一次**：

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
docker compose -f compose/schemes/all.yaml --env-file .env --profile nginx --profile nacos --profile tdengine --profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel --profile jenkins --profile postgres --profile lgtm --profile elk --profile rabbitmq --profile nora down -v
docker compose -f compose/schemes/all.yaml --env-file .env up -d mysql redis
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

### PostgreSQL 初始化

yudao-cloud 后端设置 `DB_PRIMARY=postgresql` 时使用，默认连接 `127.0.0.1:5432/ruoyi-vue-pro`、`postgres` / `123456`（`PG_HOST`、`PG_PORT`、`PG_DATABASE`、`PG_USERNAME`、`PG_PASSWORD` 可覆盖）。`config/postgres/initdb/` 挂载到容器的 `/docker-entrypoint-initdb.d`，**只在 `postgres-data` 卷为空时执行一次**，由镜像入口用 `psql` 执行：

| 脚本 | 内容 |
|---|---|
| `01-create-databases.sql` | 建库 `ruoyi-vue-pro`（PostgreSQL 没有 `CREATE DATABASE IF NOT EXISTS`，依赖"只执行一次"） |
| `02-yudao-schema.sql` | 首行 `\connect "ruoyi-vue-pro"`，其后为 `yudao-cloud/sql/postgresql/ruoyi-vue-pro.sql` 原文 |
| `03-yudao-quartz.sql` | 首行 `\connect "ruoyi-vue-pro"`，其后为 `yudao-cloud/sql/postgresql/quartz.sql` 原文 |

- 02、03 从上游整体同步：保留首行 `\connect`，其余内容整体替换，不要手工零散修改。
- `POSTGRES_DB`（默认 `postgres`）只是镜像创建的默认库，业务库名固定为 `ruoyi-vue-pro`。
- 重新初始化：`docker compose -f compose/schemes/all.yaml --env-file .env --profile postgres rm -sf postgres` 后 `docker volume rm yudao_postgres-data`，再启动（会丢失数据，先确认）。

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

### Docker Compose（`compose/`）

- **每个服务一个文件** `compose/services/<服务>.yaml`（rocketmq 含 namesrv + broker，elk 含 elasticsearch + logstash + kibana），文件头注释写单独使用的命令；每个文件都写 `name: yudao`，单独使用或被方案引用时容器名、网络、卷名一致。
- 每个服务第一行写 `extends: { file: ../base.yaml, service: base }`，`restart`、`TZ` 等公共配置只写在 `compose/base.yaml`，服务文件中不要重复。
- 方案 `compose/schemes/*.yaml`：`name: yudao` + `include` 引用 `../services/*.yaml`；菜单使用 `all.yaml`，新增服务时加入 `all.yaml` 和相应方案。
- 跨文件的依赖**不写 `depends_on`**（单独使用服务文件时会报 `depends on undefined service`，`required: false` 也不行），在菜单的 `DEPS_<服务>` 中声明，由菜单先启动；同一文件内的依赖可以写。
- 每个服务都写 `container_name: ${PROJECT_NAME:-yudao}-<服务名>`。
- 端口一律用 `.env` 变量映射并带缺省值：`"${XXX_PORT:-<默认端口>}:<容器端口>"`，带引号，缺省值与 `.env.temp` 一致；新增端口时同步在 `.env.temp` 的端口区加变量和默认值，并同步 `k8s/services/` 对应清单的 `hostPort`。
- 所有变量都写成 `${VAR:-<缺省值>}`，保证没有 `.env` 也能直接启动；口令类缺省值只用于本地开发，须与 `compose\yudao.bat` 的 `DB_PASSWORD`、`config/mysql/initdb/01-create-databases.sql` 中的用户口令保持一致。
- 运行时数据用**命名卷**（`<服务>-data` / `<服务>-logs` 等），在服务文件末尾 `volumes:` 中声明；只有需要挂载仓库内真实文件的配置/脚本才绑定挂载，路径写 `../../config/...`（相对服务文件）。
- 除 mysql/redis 外的服务都用 `profiles: ["<name>"]`，profile 名与服务文件名一致（`nginx`、`nacos`、`tdengine`、`jenkins`、`minio`、`rocketmq`、`xxl-job`、`seata`、`sentinel`、`postgres`、`lgtm`、`elk`、`rabbitmq`、`nora`）；新增服务时同步 `compose\yudao.bat` 开头的 `ALL_PROFILES` / `MIDDLEWARE_SERVICES`、服务元数据和菜单编号。
- 分节注释格式：`# ==================== 标题 ====================`；需要说明的端口用行尾中文注释。
- JVM 参数写在 `JAVA_OPTS` / `JAVA_OPT_EXT`，多行时用 `>-`。

### 环境变量模板（`.env.temp`）

- 分组标题格式：`# ================= 分组 =================`，每组上方用中文注释说明用途和约束。
- 变量名全大写下划线；端口变量统一 `XXX_PORT` 结尾，集中放在端口区。
- 模板里的密码/Token 只是占位示例，不要把真实值写进模板；新增变量时同步 README 和本文件。

### Kubernetes 清单（`k8s/`）

- **每个服务一个文件** `k8s/services/<服务>.yaml`，与 compose 服务文件同名；包含该服务的 PVC、Deployment、Service（elk 另有 logstash pipeline 的 ConfigMap），用 `---` 分隔。
- 服务文件**不写 `namespace`**，由公共基础配置 `k8s/base/kustomization.yaml`（`kind: Component`）统一加 namespace `yudao` 和公共标签 `app.kubernetes.io/part-of: yudao-env`（`includeSelectors: false`，不改 selector）。Namespace 资源本身在 `k8s/base/namespace.yaml`，由脚本先单独 apply。
- 方案 `k8s/schemes/<方案>/kustomization.yaml`：`resources` 引用 `../../services/*.yaml`，`components: [../../base]`；现有 `core`、`middleware`、`all`。部署必须用 `kubectl kustomize --load-restrictor LoadRestrictionsNone <方案目录> | kubectl apply -f -`。
- 资源名与 compose 服务名一致（`mysql`、`nacos`、`xxl-job-admin`、`seata-server` 等），标签 `app: <名称>`。
- Deployment 固定 `replicas: 1`，有 PVC 的用 `strategy.type: Recreate`。
- 端口用 `hostPort` 字面量（K8s 不支持变量替换），写 `.env.temp` 的默认值，并在行尾注释对应的 `.env` 变量，例如 `hostPort: 3306   # 对应 .env 的 MYSQL_PORT，冲突时改这里`。
- 敏感值通过 Secret `yudao-env`（由脚本从 `.env` 生成）注入：整体用 `envFrom.secretRef`，单个用 `secretKeyRef: { name: yudao-env, key: XXX }`。
- 数据卷用 PVC（走 Docker Desktop 默认 StorageClass）；挂载仓库文件用 `hostPath`，指向 `config/`，路径格式 `/run/desktop/mnt/host/<盘符小写>/<路径>`，当前为 `/run/desktop/mnt/host/d/workspace/yudao/yudao-env/config/...`。
- 服务间互访用 Service 名（如 `mysql`、`nacos:8848`、`rocketmq-namesrv:9876`），并加注释 `# k8s Service 名`。

### GitOps 清单（`gitops-k8s/`）

- 服务器手动部署用（上传到 `/opt/yudao/gitops-k8s` 后 `kubectl apply -k .`），目录**自包含**：只引用本目录内文件，不用 hostPath，不依赖 `--load-restrictor`。清单从 `k8s/services/` 复制后修改，两边分开维护。
- 环境变量单独一份：本目录 `.env.temp`（提交）复制为 `.env`（不提交；`.env`、`.env.local`、`.env.*` 已被 `.gitignore` 忽略，`.env.temp` 除外），与根目录 `.env.temp` 分开维护，只含本目录服务用到的变量。
- 变量名用各镜像**原生环境变量名**（`POSTGRES_*`、`MINIO_ROOT_*`、`NACOS_AUTH_*`、`RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS`、`NORA_*`），清单中按同名取值、不改名；镜像没有原生变量的（redis 密码）用通用名 `REDIS_PASSWORD`。
- 每个服务用 `secretKeyRef: { name: yudao-env, key: <同名> }` 只引用自己的键，**不用 `envFrom`** 整体注入；除可选的 `NORA_*` 外不加 `optional: true`，缺键时直接报错而不是带默认口令启动。
- 端口写在 `services/<工具>.yaml` 的 `hostPort` 字面量，行尾注释 `# 宿主机端口，冲突时改这里（不读 .env）`；`.env.temp` 中不放端口变量。
- 新增服务时同步 `kustomization.yaml` 的 `resources`、`.env.temp` 对应分组、`README.md` 的服务表和 Secret 键表、`SERVICES.md` 的地址和账号表（`SERVICES.md` 只写 Secret 键名，不写口令实际值）。
- README 中的 kubectl 命令写完整的 `kubectl --context kubernetes-admin@kubernetes ...`，不用 `$K` 之类的变量缩写；每条命令单独一行，不用管道 `|` 和行尾 `\` 续行（粘贴时管道后半截会被截断、`\` 后多出空格会使续行失效），Secret 用 `delete secret --ignore-not-found` + `create secret --from-env-file` 先删再建。

### Windows 批处理（`compose\yudao.bat`、`k8s\yudao-k8s.bat`）

- 只维护这两个菜单；不再提供 `.sh`、单服务脚本。
- 文件编码 **GBK（ANSI）**，开头 `chcp 936 >nul`；换行符 **CRLF**。不要转成 UTF-8 或 LF。
- 固定开头：`@echo off`、`setlocal enabledelayedexpansion`、`cd /d "%~dp0.."`（以仓库根目录为工作目录，`.env`、`backups/` 在根目录）、修复 PATH（补回 `%SystemRoot%\System32` 等）。
- 可调参数集中在开头用 `set` 定义（`SCHEME`、`CMD`、`NAMESPACE`、`K8S_CONTEXT`、`KC`、`DB_*`、`BACKUP_DIR`）。K8s 菜单所有 kubectl 调用都用 `%KC%`（`kubectl --context %K8S_CONTEXT%`），默认上下文 `docker-desktop`，上下文不存在时报错退出。
- 单个服务的启停由**服务元数据**驱动：`TITLE_<服务>`、`SVCS_<服务>` / `DEPLOYS_<服务>`、`VOLS_<服务>`、`DEPS_<服务>`、`INFO_<服务>`，菜单编号表 `START_<n>` / `STOP_<n+10>` 指向服务名，由 `:svc_up` / `:svc_down` 子程序处理。新增服务时加一组元数据、一行菜单和一组编号。
- 其余菜单项用 `if "%choice%"=="N" goto :label` 分发，每个功能一个 `:label` 段，以 `pause` + `goto :menu` 结束；标签命名为小写下划线（如 `:profile_all_up`、`:db_backup`）。
- `echo` / `REM` 行中不要写 `<`、`>`、`|`（会被当作重定向或管道），占位符写成 `{名称}`。
- K8s 菜单生成的临时 `kustomization.yaml` 只写 ASCII：bat 以 GBK 输出，kustomize 按 UTF-8 解析，中文会报 `invalid UTF-8`。
- 用 `REM ================= 分组 =================` 分隔功能段；提示信息前缀 `[信息]`、`[错误]`、`[警告]`、`[取消]`、`[完成]`、`[成功]`。
- 危险操作必须二次确认：一般操作要求输入 `Y`，删除数据卷要求输入 `DELETE`。
- 两个菜单的编号保持一一对应，改一个时同步另一个。

### SQL（`config/mysql/initdb/`）

- 文件名两位数字前缀决定执行顺序；建库、建用户集中在 `01-create-databases.sql`，其余脚本第一行 `USE <库名>;`。
- 建库统一 `DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`，使用 `IF NOT EXISTS`。
- `05-yudao-schema.sql`、`06-yudao-quartz.sql` 来自 `yudao-cloud/sql/mysql/`，更新时从上游整体同步，不要手工零散修改。

### 换行符与编码现状

- 工作区中现有 YAML、SQL、`.env.temp`、`README.md`、`AGENTS.md` 均为 **CRLF**（索引为 LF），bat 为 **GBK + CRLF**。提交时用 `git -c core.autocrlf=input add <文件>`，保持索引为 LF。修改已有文件时保持原换行符，避免整个文件出现在 diff 里。
- 本仓库没有自己的 `.editorconfig`；作为聚合仓库子模块打开时会继承上层 `.editorconfig`（`end_of_line = lf`、`charset = utf-8`），编辑器可能自动改写 bat 的编码和换行，需特别注意。

## Project Structure

```
yudao-env/
├── .env.temp                   # 环境变量模板（提交）；复制为 .env 使用（不提交），compose 与 k8s 共用
├── README.md                   # 使用说明
├── .gitignore                  # 忽略运行时数据、日志、.env、k8s/.render 等
├── compose/
│   ├── yudao.bat               # Compose 版管理菜单：启停 / 日志 / 中间件 / 备份还原
│   ├── base.yaml               # 公共基础配置（service base：restart、TZ），各服务 extends 引用
│   ├── services/               # 每个服务一个文件：mysql redis nginx nacos tdengine jenkins postgres minio
│   │                           #   rocketmq rabbitmq nora xxl-job seata sentinel lgtm elk（.yaml）
│   └── schemes/                # 方案：all.yaml（菜单使用）、core.yaml、middleware.yaml，include 服务文件
├── k8s/
│   ├── yudao-k8s.bat           # K8s 版管理菜单，编号与 compose 版一致
│   ├── base/                   # kustomization.yaml（Component：namespace、公共标签）、namespace.yaml
│   ├── services/               # 每个服务一个文件，与 compose/services 同名
│   ├── schemes/                # 方案：core/、middleware/、all/（kustomization.yaml）
│   └── .render/                # 菜单启动单个服务时生成的临时方案（不提交）
├── gitops-k8s/                 # 自包含 GitOps 方案（postgres redis nacos rabbitmq minio lgtm nora），不用 hostPath，上传到服务器 /opt/yudao/gitops-k8s 后 apply -k；env 用本目录 .env.temp 复制出的 .env，与根目录 .env.temp 分开维护
├── gitops-k8s-mini/            # 最小 GitOps 环境（postgresql redis rabbitmq r-nacos loki nora），Flux CD 从 Gitee 同步、镜像用 ACR；base/ + overlays/<local|dev|test|prod>/ + clusters/<环境>/（Flux 配置）+ bootstrap/<环境>/（命名空间 yudao-<环境>）；gitea、gitops-sync 已停用（清单保留、引用已注释）
├── config/                     # compose 与 k8s 共用的挂载文件
│   ├── mysql/initdb/           # MySQL 首次初始化脚本（01 建库建用户 ~ 06 Quartz）
│   ├── postgres/initdb/        # PostgreSQL 首次初始化脚本（01 建库 ~ 03 Quartz）
│   ├── seata/resources/        # Seata Server 配置 application.yml
│   ├── elk/logstash/pipeline/  # Logstash pipeline：tcp json_lines（5044）→ Elasticsearch 索引 yudao-logs-YYYY.MM.dd
│   ├── nora/auth/              # NORA 鉴权用 users.htpasswd（bcrypt，不提交，仅提交 .gitkeep）
│   └── tdengine/               # TDengine 建库说明
├── infra/                      # 基础环境安装配置，按系统环境分目录
│   └── ubuntu-24.04/           # docker.md（Docker）、k8s-single.md + install-k8s-single.sh + k8s-install.env（K8s 单机）、k8s-cluster.md（K8s 集群）
└── backups/                    # 数据库备份输出目录（mysql_<时间戳>.sql）
```

compose 引用但**当前仓库中不存在**的路径（`.gitignore` 已放行，需要时自行创建）：

- `config/mysql/conf/`：MySQL 自定义配置（可选）。
- `config/rocketmq/broker/conf/broker.conf`：RocketMQ broker 配置（启用 `rocketmq` profile 前必须准备）。
- `config/seata/resources/application.yml`：Seata Server 配置。注册中心 Nacos（public 命名空间、`SEATA_GROUP`）、配置中心 file、存储 db（`seata` 库）；口令可用 `SEATA_DB_PASSWORD`、`SEATA_NACOS_USERNAME`、`SEATA_NACOS_PASSWORD` 等环境变量覆盖。镜像版本需与 `yudao-cloud` 的 Seata 客户端（`spring-cloud-alibaba-dependencies` 管理，当前 2.5.0）一致。

<!-- TODO: 补充 broker.conf 的参考配置或获取方式 -->
<!-- TODO: 确认 Docker Hub 镜像 apache/seata-server:2.5.0 可拉取，并实际启动验证 config/seata/resources/application.yml -->

## Testing Instructions

### CI 现状

<!-- TODO: 补充 CI 配置；当前仓库没有任何 CI 流水线文件 -->

### 变更验证

不要为了验证而实际启动容器或修改正在运行的环境，优先用静态校验：

```bash
P="--profile nginx --profile nacos --profile tdengine --profile minio --profile rocketmq --profile xxl-job --profile seata --profile sentinel --profile jenkins --profile postgres --profile lgtm --profile elk --profile rabbitmq --profile nora"

# 校验方案的语法和变量替换（用模板，不依赖 .env；--quiet 不输出含密码的展开结果）
docker compose -f compose/schemes/all.yaml --env-file .env.temp $P config --quiet

# 每个服务文件都能单独使用
for f in compose/services/*.yaml; do n=$(basename $f .yaml); docker compose -f $f --env-file .env.temp --profile $n config --quiet || echo "ERR $f"; done

# 列出所有服务、命名卷，确认新增/改名生效（卷名应为 yudao_<卷>）
docker compose -f compose/schemes/all.yaml --env-file .env.temp $P config --services
docker compose -f compose/schemes/all.yaml --env-file .env.temp $P config --volumes

# K8s 方案离线渲染（kustomize 不连接集群）
for d in k8s/schemes/*/; do kubectl kustomize --load-restrictor LoadRestrictionsNone $d > /dev/null || echo "ERR $d"; done
```

- **不要**对 K8s 清单执行不带 `--context docker-desktop` 的 `kubectl apply`（包括 `--dry-run=client`），默认上下文可能指向线上集群；离线校验用上面的 `kubectl kustomize`。
- 在 WSL 中如果提示 `docker` 找不到（Docker Desktop 未开启 WSL integration），可直接调用 Windows 侧的可执行文件，例如 `"/mnt/c/Program Files/Docker/Docker/resources/bin/docker.exe"`，同目录下也有 `kubectl.exe`；`/mnt/c/Windows/System32/cmd.exe /c 'compose\yudao.bat'` 可以在 WSL 中运行 bat。
- bat 脚本无法静态校验：修改后确认能用 GBK 解码、全部为 CRLF（`file compose/yudao.bat` 显示 `CRLF line terminators`），并在 Windows cmd 中实际打开菜单检查中文显示和跳转。用管道给 `set /p` 喂输入测试时，输入必须是 CRLF。
- 改端口/变量时，用 `grep` 交叉核对 `compose/services/*.yaml`、`.env.temp`、`k8s/services/*.yaml`、两个 bat 菜单、`README.md` 是否一致。
- 改 initdb 脚本时，可在一次性的空卷环境中验证；不要对用户现有的 `mysql-data` 卷执行 `down -v`。

### 合并前最低要求

1. 方案和每个服务文件的 `docker compose ... config --quiet` 通过（退出码 0）。
2. 改动 `k8s/` 时所有方案的 `kubectl kustomize --load-restrictor LoadRestrictionsNone` 渲染通过。
3. `git diff` 只包含实际改动，没有因换行符或编码变化导致的整文件 diff。
4. compose 服务文件与方案、`.env.temp`、K8s 服务文件与方案、bat 菜单（服务元数据、菜单编号）、README 中的端口/变量/profile 保持同步。
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
  - `config/mysql/initdb/01-create-databases.sql` 中创建 Nacos MySQL 用户的密码，须与 `.env` 的 `NACOS_DB_PASSWORD` 一致；
  - `compose\yudao.bat`、`k8s\yudao-k8s.bat` 开头的 `DB_PASSWORD`，须与 `MYSQL_ROOT_PASSWORD` 一致。
  - 不要在文档、提交信息或日志中写出任何口令的实际值。
- **端口暴露**：所有服务都把端口映射到宿主机所有网卡（compose 的 `ports` 未绑定 `127.0.0.1`，K8s 用 `hostPort`），只适合本地开发，不要在公网或共享网络中直接使用。
- **Jenkins 权限**：jenkins 以 `user: root` 运行并挂载 `/var/run/docker.sock`，等同于拥有宿主机 Docker 控制权；Nacos 使用 `privileged: true`。
- **Nacos 鉴权**：`NACOS_AUTH_TOKEN` 用 `openssl rand -base64 32` 生成，不要复用模板值。
- **NORA 鉴权默认关闭**：`NORA_AUTH_ENABLED=false` 时任何能访问 4000 端口的人都能推送镜像、上传制品。开启鉴权需先生成 `config/nora/auth/users.htpasswd`（bcrypt，已在 `.gitignore`），不要提交该文件，也不要把 API Token 写进仓库。
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
解决：用 `file compose/yudao.bat` 检查，应显示 `CRLF line terminators`；编辑时显式选择 GBK 编码和 CRLF 换行；如已损坏，可用 `git checkout -- compose/yudao.bat` 恢复后重新修改。

### 备份失败或提示容器未运行

原因：脚本写死 `DB_CONTAINER=yudao-mysql`，若 `.env` 的 `PROJECT_NAME` 不是 `yudao`，容器名会不同；或脚本中的 `DB_PASSWORD` 与 `MYSQL_ROOT_PASSWORD` 不一致。
解决：修改脚本开头的 `DB_CONTAINER` / `DB_PASSWORD`。另外备份文件名的时间戳取自 `date /t` 和 `%time%`，格式依赖系统区域设置（如小时不补零），属于已知现象。

### RocketMQ broker 或 Seata 起不来

原因：compose 绑定挂载 `config/rocketmq/broker/conf/broker.conf`，但该路径当前不在仓库中。路径不存在时 Docker 会创建同名**目录**，broker 因读不到配置文件而失败；`ROCKETMQ_BROKER_IP` 在 compose 中没有被引用，需要写进 `broker.conf`（`brokerIP1`）才会生效。Seata 若起不来，检查 `config/seata/resources/application.yml` 中的 MySQL / Nacos 地址与口令，以及 `seata` 库是否已执行 `04-seata-schema.sql`。
解决：启用 profile 前先准备好 `broker.conf`（如已误建为目录则先删除）。

### K8s 版 hostPath 挂载失败

原因：`k8s/services/` 中 mysql、postgres、rocketmq、seata 的 `hostPath` 写死为 `/run/desktop/mnt/host/d/workspace/yudao/yudao-env/config/...`（对应 `D:\workspace\yudao\yudao-env\config`）。仓库放在其他位置时路径不存在；`mysql/initdb`、`postgres/initdb` 使用 `type: Directory`，路径不存在时 Pod 无法启动。
解决：把这几个文件中的 `hostPath.path` 改成实际路径的映射（盘符小写）。

### 改了 `.env` 端口但 K8s 版没有变化

原因：K8s 的 `hostPort` 是字面量，不读 `.env`。
解决：直接修改 `k8s/services/*.yaml` 中对应的 `hostPort`，行尾注释标明了对应的变量。

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
