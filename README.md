# yudao-env

`yudao-cloud` 本地开发环境的 Docker Compose 配置，一键拉起 MySQL、Redis 核心依赖，以及 Nacos、TDengine、Nginx、Jenkins、MinIO、RocketMQ、XXL-Job、Seata、Sentinel、PostgreSQL、Grafana LGTM、ELK、RabbitMQ 等可选中间件。

## 目录结构

```
env/
├── docker-compose-yudao.yaml   # 主编排文件
├── toggle-yudao.bat            # Windows 管理脚本（启停/日志/备份还原）
├── .env.temp                   # 环境变量模板（提交到 git）
├── .env                        # 实际使用的环境变量（不提交，自己复制生成）
├── mysql/
│   ├── initdb/                 # 首次启动自动执行的建库建表脚本
│   └── conf/                   # MySQL 自定义配置（可选）
├── rocketmq/broker/conf/       # RocketMQ broker.conf
├── seata/resources/            # Seata 配置文件
├── elk/logstash/pipeline/      # Logstash pipeline（tcp json_lines → Elasticsearch）
└── backups/                    # 数据库备份输出目录（脚本自动生成）
```

## 快速开始

1. 安装 Docker Desktop（Windows 下需开启 WSL2 后端），确认 `docker` 命令能在终端直接用。
2. （可选）不建 `.env` 也能直接启动：compose 中所有变量都带本地开发缺省值（端口为默认端口；MySQL root、Nacos/Seata 的 MySQL 用户口令与 `toggle-yudao.bat`、`01-create-databases.sql` 一致；Redis 无密码；Nacos 鉴权关闭；`SEATA_IP=127.0.0.1`）。需要自定义时复制环境变量模板并按需修改：
   ```bash
   copy .env.temp .env
   ```
   必须修改的几项：`MYSQL_ROOT_PASSWORD`、`REDIS_PASSWORD`、`NACOS_DB_PASSWORD`、`NACOS_AUTH_TOKEN`（见下方"Nacos 鉴权"）、`MINIO_ROOT_PASSWORD`、`ROCKETMQ_BROKER_IP`、`RABBITMQ_PASSWORD`（如需启用 RabbitMQ）、`SEATA_IP`、`POSTGRES_PASSWORD`（如需启用 PostgreSQL）。
3. 双击运行 `toggle-yudao.bat`，选 **1（启动核心）**。首次启动会自动执行 `mysql/initdb` 下的建库脚本。
4. 核心服务起来后，按需通过菜单单独启动 Nacos / TDengine / Nginx / Jenkins / MinIO / RocketMQ / RabbitMQ / XXL-Job / Seata / Sentinel / PostgreSQL。

## 服务清单

### 核心服务（`docker compose up -d` 默认启动，无需 `--profile`）

| 服务 | 镜像 | 默认端口（可在 `.env` 改） | 说明 |
|---|---|---|---|
| mysql | mysql:8.0.21 | `MYSQL_PORT`→3306 | root / `MYSQL_ROOT_PASSWORD` |
| redis | redis:7 | `REDIS_PORT`→6379 | 密码见 `REDIS_PASSWORD`，留空则不鉴权 |

### 可选中间件（需要 `--profile <name>`，`toggle-yudao.bat` 菜单已封装）

| 服务 | 镜像 | 默认端口 | profile |
|---|---|---|---|
| nginx | nginx:latest | `NGINX_PORT`→80 | nginx |
| nacos | nacos/nacos-server:v3.0.3 | `NACOS_PORT`(8848) / `NACOS_CONSOLE_PORT`(8080) / `NACOS_GRPC_PORT`(9848) / `NACOS_GRPC_PORT_2`(9849) | nacos |
| tdengine | tdengine/tdengine:3.3.6.0 | `TDENGINE_PORT`(6041，taosAdapter REST/WebSocket) / 6030（taosd 原生端口） | tdengine |
| jenkins | jenkins/jenkins:lts | `JENKINS_PORT`(8089)→8080 | jenkins |
| minio | minio/minio:latest | `MINIO_PORT`(9000) / `MINIO_CONSOLE_PORT`(9001) | minio |
| rocketmq-namesrv / rocketmq-broker | apache/rocketmq:5.3.1 | `ROCKETMQ_NAMESRV_PORT`(9876) / `ROCKETMQ_BROKER_PORT`(10911) / `ROCKETMQ_BROKER_VIP_PORT`(10909) | rocketmq |
| rabbitmq | rabbitmq:4.1-management | `RABBITMQ_PORT`(5672，AMQP) / `RABBITMQ_MANAGEMENT_PORT`(15672，管理控制台) | rabbitmq |
| xxl-job-admin | xuxueli/xxl-job-admin:2.4.1 | `XXL_JOB_PORT`→8080 | xxl-job |
| seata-server | seataio/seata-server:2.0.0 | `SEATA_PORT`(8091) / `SEATA_DASHBOARD_PORT`(7091) | seata |
| sentinel-dashboard | bladex/sentinel-dashboard:1.8.8 | `SENTINEL_PORT`→8858 | sentinel |
| postgres | postgres:16-alpine | `POSTGRES_PORT`→5432 | postgres |
| lgtm | grafana/otel-lgtm:0.37.0 | `LGTM_GRAFANA_PORT`(3000) / `LGTM_OTLP_GRPC_PORT`(4317) / `LGTM_OTLP_HTTP_PORT`(4318) | lgtm |
| elasticsearch / logstash / kibana | docker.elastic.co/*:8.19.23 | `ELASTICSEARCH_PORT`(9200) / `LOGSTASH_TCP_PORT`(5044) / `KIBANA_PORT`(5601) | elk |

> `postgres` 是一个通用的空实例，当前 yudao-cloud 各模块默认都用 MySQL，没有服务依赖它；只有本地需要额外用到 PostgreSQL（自己的服务、调试其他项目等）时才需要启动，库名/账号密码见 `.env` 里的 `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD`。

> `lgtm` 是 Grafana 官方的一体化可观测性镜像（OTel Collector + Loki 日志 + Tempo 链路 + Prometheus 指标 + Grafana），仅用于开发测试。yudao-cloud-mini 的服务在启动类上添加 `@EnableTraceLogPushOTEL` 注解时默认上报，未添加时默认不上报（避免没启动 LGTM 时报错）；配置项 `management.tracing.export.enabled` 等优先级更高，可以覆盖注解，上报地址在 `application-local.yaml` 中，默认是 `http://127.0.0.1:4318`（OTLP HTTP）。打开 Grafana `http://127.0.0.1:3000`（默认 `admin` / `admin`）→ Explore：选 Tempo 查链路，点击 span 的 "Logs for this span" 跳到该 traceId 在各服务的日志；选 Loki 查日志（如 `{service_name="system-server"} | trace_id="xxx"`），点击日志中的 `trace_id` 跳回链路。数据保存在 `lgtm-data` 卷。

> `elk` 是日志聚合：Logstash 接收应用日志（`tcp` 输入 + `json_lines`，端口 5044），写入 Elasticsearch（按天建索引 `yudao-logs-YYYY.MM.dd`），在 Kibana 中查询；已关闭安全认证，仅用于开发测试，首次启动需要 1~2 分钟。yudao-cloud-mini 的服务在启动类上添加 `@EnableLogPushLogstash` 注解时默认上报，未添加时默认不上报；配置项 `logstash.enabled` 优先级更高，可以覆盖注解，上报地址为 `logstash.destination`（`application-local.yaml` 中默认 `127.0.0.1:5044`）。打开 Kibana `http://127.0.0.1:5601` → Stack Management → 数据视图，创建 `yudao-logs-*`（时间字段 `@timestamp`），然后在 Discover 中按 `traceId`、`app_name`、`level` 等字段查询。Logstash pipeline 见 `elk/logstash/pipeline/logstash.conf`，数据保存在 `elasticsearch-data` 卷。

> `rabbitmq` 是 yudao-cloud 的可选消息队列（`spring.rabbitmq.*`）。管理员账号由 `.env` 的 `RABBITMQ_USERNAME` / `RABBITMQ_PASSWORD` 设置，变量名与 yudao-cloud 一致，应用侧直接读取同名环境变量；账号只在 `rabbitmq-data` 卷首次初始化时创建，之后修改 `.env` 不会生效（在管理控制台改密码，或清空数据卷）。容器固定 `hostname: rabbitmq`，因为 RabbitMQ 按节点名 `rabbit@<hostname>` 存放数据，hostname 变化会导致重建后读不到原数据。管理控制台 `http://127.0.0.1:15672`。注意 yudao-cloud 各模块的账号默认值不统一（多数为 `guest`，`yudao-server` 为 `rabbit`），连接时以应用侧的 `RABBITMQ_USERNAME` / `RABBITMQ_PASSWORD` 环境变量为准。

## 数据库初始化

`mysql/initdb/` 下的 SQL 脚本**只在 MySQL 数据卷第一次初始化（空卷）时自动执行**，重启容器不会重跑。会创建以下数据库：

| 库名 | 用途 |
|---|---|
| `ruoyi-vue-pro` | 业务主库（yudao-cloud 各模块 + Quartz 定时任务表） |
| `nacos` | Nacos 配置/注册中心持久化 |
| `xxl_job` | XXL-Job 调度中心 |
| `seata` | Seata 事务协调器 |
| `quartz` | 历史遗留，当前没有模块使用，可忽略 |

如果需要重新初始化（改过建库脚本、或想清空数据重来），用 `toggle-yudao.bat` 选项 **9（停止全部并清空数据卷）**，注意这会删除所有服务的数据卷，操作前请先用选项 31 备份数据库。

## Nacos

- 应用连接地址：`127.0.0.1:${NACOS_PORT}`（默认 8848），控制台：`http://127.0.0.1:${NACOS_CONSOLE_PORT}`（默认 8080，与 IDEA 内嵌 Nacos 相同；两者二选一启动）。
- 已预置 `dev` / `test` / `prod` 三个命名空间（`mysql/initdb/02-nacos-schema.sql` 里插入的 `tenant_info` 记录），对应各服务 `application-{profile}.yaml` 里的 `spring.cloud.nacos.*.namespace` 配置，开箱即用。
- **鉴权变量必须都填，不能留空**：`NACOS_AUTH_TOKEN`、`NACOS_AUTH_IDENTITY_KEY`、`NACOS_AUTH_IDENTITY_VALUE` 这三个哪怕不启用鉴权（`NACOS_AUTH_ENABLE` 可以注释/关闭）也必须有值，否则镜像启动脚本会直接 `exit 255`。`NACOS_AUTH_TOKEN` 需要 Base64 编码的 32 字节字符串，生成命令：
  ```bash
  openssl rand -base64 32
  ```

## TDengine（IoT 模块）

IoT 模块用 TDengine 存设备时序消息，属于中间件，需要通过菜单 `10` 单独启动（`--profile tdengine`），另有两处需要手动处理：

1. **应用侧**：`yudao-module-iot/yudao-module-iot-server/src/main/resources/application-local.yaml` 里的 `spring.datasource.dynamic.datasource.tdengine` 默认是注释的，需要取消注释才能连上，否则 `IoTServerApplication` 启动时会因为 `TDengineTableInitRunner` 初始化失败直接 `System.exit(1)`。
2. **建库**：IoT 模块代码只会建"超级表"，不会自动建库，容器起来后需要手动执行一次（数据持久化在 `tdengine-data` 卷里，之后重启不用重复执行）：
   ```bash
   docker exec -it yudao-tdengine taos -s "CREATE DATABASE IF NOT EXISTS ruoyi_vue_pro;"
   ```

如果暂时不需要用 IoT 模块，不启动 `IoTServerApplication` 即可，不影响其他服务。

## toggle-yudao.bat 菜单说明

双击运行后是一个交互式菜单，输入编号回车执行：

**核心服务**
- `1` 启动核心（mysql/redis）
- `2` 停止全部（含所有已启用的中间件 profile，保留数据卷）
- `3` 重启核心
- `4` 查看所有服务状态
- `5` 查看核心服务日志（Ctrl+C 退出）
- `6` 强制重建核心服务（改了镜像版本、环境变量后用这个）

**中间件（单独启停）**：`10`/`20` TDengine，`11`/`21` MinIO，`12`/`22` RocketMQ，`13`/`23` XXL-Job，`14`/`24` Seata，`15`/`25` Sentinel，`16`/`26` Jenkins，`17`/`27` PostgreSQL，`18`/`28` Nacos，`19`/`29` Grafana LGTM，`40`/`50` Nginx，`41`/`51` ELK，`42`/`52` RabbitMQ；`7`/`8` 一键启停全部中间件（`8` 只停中间件，mysql/redis 保持运行）。

**危险操作**
- `9` 停止全部并**清空所有数据卷**（`down -v`），需要手动输入 `DELETE` 二次确认。用于彻底重置环境、让 `mysql/initdb` 脚本重新执行。

**数据库备份 / 还原**（依赖本机能直接执行 `docker exec`）
- `31` 备份所有非系统库到 `backups/mysql_<时间戳>.sql`
- `32` 从 `backups/` 里选一个文件还原
- `33` 查看备份文件列表
- `34` 查看当前数据库列表

## Kubernetes 版本

除了 `docker-compose-yudao.yaml`，`k8s/` 目录下提供了一套等价的 Kubernetes 清单 + `toggle-yudao-k8s.bat` 管理脚本，用法跟上面的 compose 版本基本一一对应。**目标环境是 Docker Desktop 自带的单节点 Kubernetes**（设置 → Kubernetes → Enable Kubernetes），其他集群（minikube/真实多节点集群）需要自行调整存储和网络部分。

### 快速开始

1. Docker Desktop 里启用 Kubernetes，等状态栏图标变绿。
2. 确保 `.env` 已经存在（跟 compose 版本共用同一份 `.env`，见上文"快速开始"）。
3. 双击运行 `toggle-yudao-k8s.bat`，选 **1（启动核心）**。脚本会自动创建 `yudao` 这个 Namespace，并从 `.env` 生成/更新一个叫 `yudao-env` 的 Secret，再 apply 核心服务清单。

### 跟 compose 版本的关键差异

- **端口是写死的字面量**：K8s 的 `hostPort` 字段不支持变量替换，所以 `k8s/*.yaml` 里的端口直接写成了 `.env.temp` 的默认值（3306/6379/8848/9000 等），每个端口旁边都有注释标注对应 `.env` 里的哪个变量。如果本机端口冲突，需要直接改 YAML 文件里的数字，改完 `.env` 里对应的变量仅供人工核对，不会被自动同步进 YAML。
- **没有 `PROJECT_NAME` 前缀**：compose 版本用前缀区分同一台机器上的多套环境，K8s 版本用 `yudao` 这个 Namespace 天然隔离，资源名就是 `mysql`、`nacos` 这种简单名字，不支持多环境并存（要多套就开多个 Namespace，需要自行改清单）。
- **数据卷**：对应 compose 里的 named volume（`mysql-data`、`nacos-data`、`minio-data` 等）都改成了 `PersistentVolumeClaim`，走 Docker Desktop 默认 StorageClass 动态供给；`mysql/initdb`、`mysql/conf`、`rocketmq/broker/conf`、`seata/resources` 这几个需要挂载仓库真实文件的，用 `hostPath` 挂载 `/run/desktop/mnt/host/d/sourceCode/yudao/env/...`（Docker Desktop for Windows 固定的宿主机路径映射规则，盘符小写）。**如果这个仓库不是放在 `D:\sourceCode\yudao\env`，需要手动把 `k8s/*.yaml` 里所有 `hostPath.path` 改成实际路径对应的映射。**
- **中间件的"可选启动"**：compose 用 `--profile`，K8s 版本用文件级选择——`10-jenkins.yaml` ~ `19-rabbitmq.yaml` 十个文件默认不 apply，`toggle-yudao-k8s.bat` 的中间件菜单项分别对应 `kubectl apply -f` / `kubectl delete deployment,service`（停止时特意只删 Deployment/Service，不碰 PVC，避免误删数据）。

### toggle-yudao-k8s.bat 菜单说明

菜单编号跟 `toggle-yudao.bat` 完全对齐（`1`-`6` 核心操作、`11`-`29`、`41`/`51`、`42`/`52` 中间件单独启停、`7`/`8` 中间件全启全停、`31`-`34` 数据库备份还原），只有两处不同：
- `5` 查看日志：K8s 没有内置"一次看全部服务日志"的简单命令，改成交互式输入要看哪个 Deployment 的名字（`mysql`/`nacos`/`redis`/`tdengine`/`nginx` 等），单独 `kubectl logs -f` 跟随。
- `9` 危险操作从"`down -v`"变成"`kubectl delete pvc --all -n yudao`"，效果一样（清空所有数据卷），同样需要手动输入 `DELETE` 二次确认。

数据库备份/还原（`31`-`34`）把 `docker exec %DB_CONTAINER%` 换成了 `kubectl exec deploy/mysql`，其余逻辑（`mysqldump` 参数、时间戳命名、`backups/` 目录）跟 compose 版本完全一样，两个脚本生成的备份文件可以互相还原。

## 常见问题

- **`chcp`/`where`/`docker` 报"不是内部或外部命令"**：Windows 系统 PATH 缺了 `C:\Windows\System32`。脚本已经在开头临时把 `%SystemRoot%\System32` 等目录加回本进程 PATH，一般不用管；如果还报错，说明系统级 PATH 环境变量本身被破坏了，需要在"编辑系统环境变量"里手动修复。
- **IDEA 报 `Command line is too long`**：多模块项目 classpath 太长超过 Windows 命令行限制，跟本仓库无关。在 Run/Debug Configuration 里勾选 `Modify options → Shorten command line`，选 `JAR manifest` 或 `@argfiles`。
- **多个服务启动报 `Port XXXX was already in use`**：先确认不是同一个端口被两个 yudao-cloud 模块同时占用（各模块端口在各自 `application.yaml` 里写死，检查有没有重复），再排查是否有上一次运行残留的进程没退出（`netstat -ano | findstr <端口>` 找 PID，`taskkill /PID <pid> /F` 杀掉）。
- **应用连的数据库名对不上**：这个仓库的主库名是 `ruoyi-vue-pro`（在 `mysql/initdb/01-create-databases.sql` 里定义），确认应用的 `application-local.yaml` 数据源 URL 里的库名跟这个一致。
