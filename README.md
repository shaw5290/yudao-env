# yudao-env

`yudao-cloud` 本地开发环境的 Docker Compose 配置，一键拉起 MySQL、Redis 核心依赖，以及 Nacos、TDengine、Nginx、Jenkins、MinIO、RocketMQ、XXL-Job、Seata、Sentinel、PostgreSQL、Grafana LGTM、ELK、RabbitMQ、NORA（Docker / Maven / npm 制品仓库）等可选中间件。

## 目录结构

```
yudao-env/
├── .env.temp                   # 环境变量模板（提交到 git），compose 与 k8s 共用
├── .env                        # 实际使用的环境变量（不提交，自己复制生成）
├── compose/                    # Docker Compose 部署
│   ├── yudao.bat               # 管理菜单（启停 / 日志 / 中间件 / 备份还原）
│   ├── base.yaml               # 公共基础配置（restart、TZ），各服务 extends 引用
│   ├── services/               # 每个服务一个文件：mysql.yaml、nora.yaml、lgtm.yaml ...
│   └── schemes/                # 方案：用 include 组合服务文件（all.yaml 全部、core.yaml、middleware.yaml）
├── k8s/                        # Kubernetes 部署（Docker Desktop 单节点）
│   ├── yudao-k8s.bat           # 管理菜单，编号与 compose 版一致
│   ├── base/                   # 公共基础配置：Kustomize Component（namespace、公共标签）+ namespace.yaml
│   ├── services/               # 每个服务一个文件：mysql.yaml、nora.yaml、lgtm.yaml ...
│   └── schemes/                # 方案：core/、middleware/、all/，各自的 kustomization.yaml 引用 services/*.yaml
├── config/                     # compose 与 k8s 共用的挂载文件
│   ├── mysql/initdb/           # 首次启动自动执行的建库建表脚本（mysql/conf 为可选的自定义配置）
│   ├── postgres/initdb/        # PostgreSQL 首次启动自动执行的建库建表脚本
│   ├── rocketmq/broker/conf/   # RocketMQ broker.conf（不入库，启用前自行创建）
│   ├── seata/resources/        # Seata Server 配置（application.yml）
│   ├── elk/logstash/pipeline/  # Logstash pipeline（tcp json_lines → Elasticsearch）
│   ├── nora/auth/              # NORA 开启鉴权时的 users.htpasswd（不提交）
│   ├── orca-slicer/presets/    # OrcaSlicer 自定义预设（machine / process / filament 的 JSON）
│   └── tdengine/               # TDengine 建库说明
├── images/                     # 本地构建的镜像
│   └── orca-slicer/            # OrcaSlicer 切片服务（Dockerfile + server.py + README.md）
├── infra/                      # 基础环境安装配置，按系统环境分目录
│   └── ubuntu-24.04/           # docker.md（Docker）、k8s-single.md + install-k8s-single.sh + k8s-install.env（K8s 单机）、k8s-cluster.md（K8s 集群）
└── backups/                    # 数据库备份输出目录（脚本自动生成）
```

## 服务文件与方案

两种部署方式的组织方式相同：**每个服务一个配置文件**（`services/*.yaml`），都引用同一份**基础配置**（`base`），再由**方案**（`schemes/`）挑选服务文件组合起来。

- **Compose**：服务文件通过 `extends: { file: ../base.yaml, service: base }` 继承公共配置，每个文件都声明 `name: yudao`，所以单独使用和在方案中使用时，容器名、网络、卷名（`yudao_<卷>`）都一致。方案文件用 `include` 引用服务文件：
  ```bash
  # 在仓库根目录执行
  docker compose -f compose/schemes/all.yaml --env-file .env up -d                       # 核心（mysql、redis）
  docker compose -f compose/schemes/all.yaml --env-file .env --profile nora up -d nora   # 某个中间件
  docker compose -f compose/services/lgtm.yaml --env-file .env --profile lgtm up -d      # 只用一个服务文件
  ```
  服务文件在子目录中，Compose 不会自动读取根目录的 `.env`，所以要显式加 `--env-file .env`（菜单已处理）。跨文件的依赖（nacos、xxl-job、seata 依赖 mysql 等）不写 `depends_on`，因为单独使用服务文件时会报找不到服务；由菜单先启动依赖。
- **K8s**：服务文件不写 `namespace`，由 `k8s/base`（Kustomize Component）统一加上 namespace `yudao` 和公共标签。方案引用了目录外的 `services/*.yaml`，Kustomize 默认不允许，所以必须加 `--load-restrictor LoadRestrictionsNone`，不能直接用 `kubectl apply -k`：
  ```bash
  kubectl --context docker-desktop kustomize --load-restrictor LoadRestrictionsNone k8s/schemes/core | kubectl --context docker-desktop apply -f -
  ```
  菜单启停单个服务时，会生成临时方案 `k8s/.render/<服务>/kustomization.yaml`（依赖 + 本服务 + base，已在 `.gitignore`），与方案部署走同一套渲染流程。
- **新增方案**：复制一个现有方案，增删其中引用的服务文件即可（Compose 复制 `compose/schemes/*.yaml`，K8s 复制 `k8s/schemes/<方案>/`）。
- **新增服务**：在 `compose/services/`、`k8s/services/` 各加一个 `<服务>.yaml`，加入相应方案；再在两个菜单开头的“服务元数据”和“菜单编号”中各加一组。

## 快速开始

1. 安装 Docker Desktop（Windows 下需开启 WSL2 后端），确认 `docker` 命令能在终端直接用。
2. （可选）不建 `.env` 也能直接启动：compose 中所有变量都带本地开发缺省值（端口为默认端口；MySQL root、Nacos/Seata 的 MySQL 用户口令与 `compose\yudao.bat`、`config/mysql/initdb/01-create-databases.sql` 一致；Redis 无密码；Nacos 鉴权关闭；`SEATA_IP=127.0.0.1`）。需要自定义时复制环境变量模板并按需修改：
   ```bash
   copy .env.temp .env
   ```
   必须修改的几项：`MYSQL_ROOT_PASSWORD`、`REDIS_PASSWORD`、`NACOS_DB_PASSWORD`、`NACOS_AUTH_TOKEN`（见下方"Nacos 鉴权"）、`MINIO_ROOT_PASSWORD`、`ROCKETMQ_BROKER_IP`、`RABBITMQ_PASSWORD`（如需启用 RabbitMQ）、`SEATA_IP`、`POSTGRES_PASSWORD`（如需启用 PostgreSQL）。
3. 双击运行 `compose\yudao.bat`，选 **1（启动核心）**。首次启动会自动执行 `config/mysql/initdb` 下的建库脚本。
4. 核心服务起来后，按需通过菜单单独启动 Nacos / TDengine / Nginx / Jenkins / MinIO / RocketMQ / RabbitMQ / XXL-Job / Seata / Sentinel / PostgreSQL / NORA。

## 服务清单

### 核心服务（`docker compose up -d` 默认启动，无需 `--profile`）

| 服务 | 镜像 | 默认端口（可在 `.env` 改） | 说明 |
|---|---|---|---|
| mysql | mysql:8.0.21 | `MYSQL_PORT`→3306 | root / `MYSQL_ROOT_PASSWORD` |
| redis | redis:7 | `REDIS_PORT`→6379 | 密码见 `REDIS_PASSWORD`，留空则不鉴权 |

### 可选中间件（需要 `--profile <name>`，`compose\yudao.bat` 菜单已封装）

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
| seata-server | apache/seata-server:2.5.0 | `SEATA_PORT`(8091) / `SEATA_DASHBOARD_PORT`(7091) | seata |
| sentinel-dashboard | bladex/sentinel-dashboard:1.8.8 | `SENTINEL_PORT`→8858 | sentinel |
| postgres | postgres:16-alpine | `POSTGRES_PORT`→5432 | postgres |
| lgtm | grafana/otel-lgtm:0.37.0 | `LGTM_GRAFANA_PORT`(3000) / `LGTM_OTLP_GRPC_PORT`(4317) / `LGTM_OTLP_HTTP_PORT`(4318) | lgtm |
| elasticsearch / logstash / kibana | docker.elastic.co/*:8.19.23 | `ELASTICSEARCH_PORT`(9200) / `LOGSTASH_TCP_PORT`(5044) / `KIBANA_PORT`(5601) | elk |
| nora | ghcr.io/getnora-io/nora:1.4.4 | `NORA_PORT`(4000，Docker / Maven / npm / Web UI 共用) | nora |
| orca-slicer | yudao-env/orca-slicer:2.5.1（本地构建，`images/orca-slicer`） | `ORCA_SLICER_PORT`(8590) | orca-slicer |

> `postgres` 是 yudao-cloud 切换到 PostgreSQL 时使用的数据库（后端设置 `DB_PRIMARY=postgresql`，默认连接 `127.0.0.1:5432/ruoyi-vue-pro`、`postgres` / `123456`）。首次启动会自动执行 `config/postgres/initdb` 下的脚本建库 `ruoyi-vue-pro` 并导入表结构，见下方"数据库初始化"。账号密码见 `.env` 里的 `POSTGRES_USER` / `POSTGRES_PASSWORD`，需与后端的 `PG_USERNAME` / `PG_PASSWORD` 一致。

> `lgtm` 是 Grafana 官方的一体化可观测性镜像（OTel Collector + Loki 日志 + Tempo 链路 + Prometheus 指标 + Grafana），仅用于开发测试。yudao-cloud-mini 的服务在启动类上添加 `@EnableTraceLogPushOTEL` 注解时默认上报，未添加时默认不上报（避免没启动 LGTM 时报错）；配置项 `management.tracing.export.enabled` 等优先级更高，可以覆盖注解，上报地址在 `application-local.yaml` 中，默认是 `http://127.0.0.1:4318`（OTLP HTTP）。打开 Grafana `http://127.0.0.1:3000`（默认 `admin` / `admin`）→ Explore：选 Tempo 查链路，点击 span 的 "Logs for this span" 跳到该 traceId 在各服务的日志；选 Loki 查日志（如 `{service_name="system-server"} | trace_id="xxx"`），点击日志中的 `trace_id` 跳回链路。数据保存在 `lgtm-data` 卷。

> `elk` 是日志聚合：Logstash 接收应用日志（`tcp` 输入 + `json_lines`，端口 5044），写入 Elasticsearch（按天建索引 `yudao-logs-YYYY.MM.dd`），在 Kibana 中查询；已关闭安全认证，仅用于开发测试，首次启动需要 1~2 分钟。yudao-cloud-mini 的服务在启动类上添加 `@EnableLogPushLogstash` 注解时默认上报，未添加时默认不上报；配置项 `logstash.enabled` 优先级更高，可以覆盖注解，上报地址为 `logstash.destination`（`application-local.yaml` 中默认 `127.0.0.1:5044`）。打开 Kibana `http://127.0.0.1:5601` → Stack Management → 数据视图，创建 `yudao-logs-*`（时间字段 `@timestamp`），然后在 Discover 中按 `traceId`、`app_name`、`level` 等字段查询。Logstash pipeline 见 `config/elk/logstash/pipeline/logstash.conf`，数据保存在 `elasticsearch-data` 卷。

> `orca-slicer` 是 3D 打印报价用的切片服务（OrcaSlicer 命令行 + HTTP 接口）：上传模型和预设，切片成 G-code，返回耗材重量、打印时间、层数、打印参数，供 yudao-blocks 的 print3d-slice 积木调用。镜像在本地构建（`images/orca-slicer`，约 1.5GB），首次启动（菜单 `44`）会先构建，需要几分钟；Docker Hub 访问不了时在 `.env` 中把 `ORCA_SLICER_BASE_IMAGE` 改为镜像站（如 `docker.m.daocloud.io/library/ubuntu:24.04`）。自己调好的机型 / 工艺 / 耗材预设放在 `config/orca-slicer/presets`。接口说明见 [images/orca-slicer/README.md](images/orca-slicer/README.md)，健康检查 `http://127.0.0.1:8590/health`。

> `rabbitmq` 是 yudao-cloud 的可选消息队列（`spring.rabbitmq.*`）。管理员账号由 `.env` 的 `RABBITMQ_USERNAME` / `RABBITMQ_PASSWORD` 设置，变量名与 yudao-cloud 一致，应用侧直接读取同名环境变量；账号只在 `rabbitmq-data` 卷首次初始化时创建，之后修改 `.env` 不会生效（在管理控制台改密码，或清空数据卷）。容器固定 `hostname: rabbitmq`，因为 RabbitMQ 按节点名 `rabbit@<hostname>` 存放数据，hostname 变化会导致重建后读不到原数据。管理控制台 `http://127.0.0.1:15672`。注意 yudao-cloud 各模块的账号默认值不统一（多数为 `guest`，`yudao-server` 为 `rabbit`），连接时以应用侧的 `RABBITMQ_USERNAME` / `RABBITMQ_PASSWORD` 环境变量为准。

## 数据库初始化

`config/mysql/initdb/` 下的 SQL 脚本**只在 MySQL 数据卷第一次初始化（空卷）时自动执行**，重启容器不会重跑。会创建以下数据库：

| 库名 | 用途 |
|---|---|
| `ruoyi-vue-pro` | 业务主库（yudao-cloud 各模块 + Quartz 定时任务表） |
| `nacos` | Nacos 配置/注册中心持久化 |
| `xxl_job` | XXL-Job 调度中心 |
| `seata` | Seata 事务协调器 |
| `quartz` | 历史遗留，当前没有模块使用，可忽略 |

如果需要重新初始化（改过建库脚本、或想清空数据重来），用 `compose\yudao.bat` 选项 **9（停止全部并清空数据卷）**，注意这会删除所有服务的数据卷，操作前请先用选项 31 备份数据库。

### PostgreSQL

`config/postgres/initdb/` 下的脚本同样**只在 `postgres-data` 卷第一次初始化时执行**，按文件名顺序：

| 脚本 | 内容 |
|---|---|
| `01-create-databases.sql` | 建库 `ruoyi-vue-pro`（UTF8） |
| `02-yudao-schema.sql` | `\connect "ruoyi-vue-pro"` + yudao-cloud 业务主库（来自 `yudao-cloud/sql/postgresql/ruoyi-vue-pro.sql`） |
| `03-yudao-quartz.sql` | `\connect "ruoyi-vue-pro"` + Quartz 表（来自 `yudao-cloud/sql/postgresql/quartz.sql`） |

需要重新初始化时（会丢失 PostgreSQL 数据）：`docker compose -f compose/schemes/all.yaml --env-file .env --profile postgres rm -sf postgres` 删除容器，`docker volume rm yudao_postgres-data` 删除数据卷，再通过菜单 `17` 启动。

## Nacos

- 应用连接地址：`127.0.0.1:${NACOS_PORT}`（默认 8848），控制台：`http://127.0.0.1:${NACOS_CONSOLE_PORT}`（默认 8080，与 IDEA 内嵌 Nacos 相同；两者二选一启动）。
- 已预置 `dev` / `test` / `prod` 三个命名空间（`config/mysql/initdb/02-nacos-schema.sql` 里插入的 `tenant_info` 记录），对应各服务 `application-{profile}.yaml` 里的 `spring.cloud.nacos.*.namespace` 配置，开箱即用。
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

## NORA（制品仓库）

[NORA](https://github.com/getnora-io/nora) 是单文件、无数据库的制品仓库，这里只启用 Docker、Maven、npm 三种仓库（`NORA_REGISTRIES_ENABLE=docker,maven,npm`）。每种仓库既能存放自己发布的制品，也能代理缓存上游：Maven 默认回源阿里云 + Maven Central，npm 回源 npmmirror，Docker 回源 Docker Hub（`.env` 的 `NORA_MAVEN_PROXIES`、`NORA_NPM_PROXY`、`NORA_DOCKER_PROXIES` 可改）。数据保存在 `nora-data` 卷。镜像放在 ghcr.io（Docker Hub 上的 `getnora/nora` 是同一个镜像）。

| 用途 | 地址 |
|---|---|
| Web UI | `http://127.0.0.1:4000/ui/` |
| Docker 镜像仓库 | `localhost:4000`（如 `localhost:4000/yudao/system-server:<tag>`） |
| Maven 仓库 | `http://127.0.0.1:4000/maven2/` |
| npm 仓库 | `http://127.0.0.1:4000/npm/` |
| 健康检查 / 指标 | `/health`、`/metrics` |

**Maven**：在 `~/.m2/settings.xml` 里把 NORA 配成镜像（拉依赖走 NORA 缓存）：

```xml
<mirrors>
  <mirror>
    <id>nora</id>
    <mirrorOf>*</mirrorOf>
    <url>http://127.0.0.1:4000/maven2/</url>
  </mirror>
</mirrors>
```

`mvn deploy` 发布时，在 pom 的 `distributionManagement` 中把 `repository` 和 `snapshotRepository` 都指向 `http://127.0.0.1:4000/maven2/`（NORA 不区分 release / snapshot 仓库）。开启鉴权后，在 `settings.xml` 的 `<servers>` 里为对应 id 配置账号。注意：release 版本不可覆盖，同一版本重复上传返回 `409`（实测）；`-SNAPSHOT` 版本同路径重复上传返回 `201` 可覆盖，`maven-metadata.xml` 也可覆盖，所以开发期用 SNAPSHOT 不会撞 409。NORA 不区分 release / snapshot 仓库，也不会自动生成或合并 `maven-metadata.xml`（依赖 Maven 自己上传），更不做 `-SNAPSHOT` 到时间戳的别名解析，客户端要靠 metadata 自己解析。

**npm**：`npm config set registry http://127.0.0.1:4000/npm/`（pnpm 同理）。返回的 tarball 下载地址按 `NORA_PUBLIC_URL` 生成，所以局域网其他机器访问时，要把它改成宿主机 IP 并重建容器。

**Docker**：`docker tag <镜像> localhost:4000/yudao/<名称>:<tag>`，再 `docker push localhost:4000/yudao/<名称>:<tag>`。Docker Desktop 默认把 `127.0.0.0/8` 当作 insecure registry，本机走 HTTP 可以直接推送和拉取；其他机器需要在 Docker Engine 配置的 `insecure-registries` 中加入 `<宿主机IP>:4000`。

**鉴权**（默认关闭，任何人都能读写，只适合本机开发）：
1. 生成 bcrypt 格式的 htpasswd（在 cmd 中执行；PowerShell 的 `>` 会写成 UTF-16，不能用）：
   ```bat
   docker run --rm httpd:2.4-alpine htpasswd -nbB admin <密码> > config\nora\auth\users.htpasswd
   ```
   添加更多用户时，把命令输出追加到同一个文件。该文件已在 `.gitignore` 中，不会提交。
2. `.env` 中设置 `NORA_AUTH_ENABLED=true`，然后重新启动 NORA（菜单 `43`）。
3. 开启后上传 / 推送必须带账号（`docker login localhost:4000`，Maven 在 `<servers>` 中配置账号）；`NORA_AUTH_ANONYMOUS_READ`、`NORA_AUTH_DOCKER_ANON_PULL` 默认为 `true`，即 Maven / npm 下载和镜像拉取仍可匿名，K8s 节点拉镜像不用配 `imagePullSecrets`。CI 中建议在 Web UI 创建 API Token（`nra_` 开头）代替密码。

## compose\yudao.bat 菜单说明

双击运行后是一个交互式菜单，输入编号回车执行：

**核心服务**
- `1` 启动核心（mysql/redis）
- `2` 停止全部（含所有已启用的中间件 profile，保留数据卷）
- `3` 重启核心
- `4` 查看所有服务状态
- `5` 查看核心服务日志（Ctrl+C 退出）
- `6` 强制重建核心服务（改了镜像版本、环境变量后用这个）

**中间件（单独启停）**：`10`/`20` TDengine，`11`/`21` MinIO，`12`/`22` RocketMQ，`13`/`23` XXL-Job，`14`/`24` Seata，`15`/`25` Sentinel，`16`/`26` Jenkins，`17`/`27` PostgreSQL，`18`/`28` Nacos，`19`/`29` Grafana LGTM，`40`/`50` Nginx，`41`/`51` ELK，`42`/`52` RabbitMQ，`43`/`53` NORA，`44`/`54` OrcaSlicer 切片服务（不在全部中间件中）；`7`/`8` 一键启停全部中间件（`8` 只停中间件，mysql/redis 保持运行）。

单独停止中间件时，有命名数据卷的服务会询问“是否同时删除容器和数据卷”，**默认 N**（直接回车）只停止、保留数据；输入 `y` 会删除该中间件的容器及其数据卷（如 MinIO 的 `yudao_minio-data`），数据不可恢复。Seata、Nginx 没有命名卷，直接停止不询问。

**危险操作**
- `9` 停止全部并**清空所有数据卷**（`down -v`），需要手动输入 `DELETE` 二次确认。用于彻底重置环境、让 `config/mysql/initdb` 脚本重新执行。

**数据库备份 / 还原**（依赖本机能直接执行 `docker exec`）
- `31` 备份所有非系统库到 `backups/mysql_<时间戳>.sql`
- `32` 从 `backups/` 里选一个文件还原
- `33` 查看备份文件列表
- `34` 查看当前数据库列表

## Kubernetes 版本

除了 `compose/`，`k8s/` 目录下提供了一套等价的 Kubernetes 清单 + `k8s\yudao-k8s.bat` 管理菜单，用法跟上面的 compose 版本基本一一对应。**目标环境是 Docker Desktop 自带的单节点 Kubernetes**（设置 → Kubernetes → Enable Kubernetes），其他集群（minikube/真实多节点集群）需要自行调整存储和网络部分。

### 快速开始

1. Docker Desktop 里启用 Kubernetes，等状态栏图标变绿。
2. 确保 `.env` 已经存在（跟 compose 版本共用同一份 `.env`，见上文"快速开始"）。
3. 双击运行 `k8s\yudao-k8s.bat`，选 **1（启动核心）**。脚本会自动创建 `yudao` 这个 Namespace，并从 `.env` 生成/更新一个叫 `yudao-env` 的 Secret，再部署方案 `k8s/schemes/core`。
4. **kubectl 上下文**：脚本中所有 kubectl 命令都显式加 `--context docker-desktop`，不使用当前默认上下文，上下文不存在时直接报错退出，避免误部署到其他集群。确实要用其他集群时，先在 cmd 中 `set K8S_CONTEXT=<上下文名>` 再运行。

### 跟 compose 版本的关键差异

- **端口是写死的字面量**：K8s 的 `hostPort` 字段不支持变量替换，所以 `k8s/services/*.yaml` 里的端口直接写成了 `.env.temp` 的默认值（3306/6379/8848/9000 等），每个端口旁边都有注释标注对应 `.env` 里的哪个变量。如果本机端口冲突，需要直接改 YAML 文件里的数字，改完 `.env` 里对应的变量仅供人工核对，不会被自动同步进 YAML。
- **没有 `PROJECT_NAME` 前缀**：compose 版本用前缀区分同一台机器上的多套环境，K8s 版本用 `yudao` 这个 Namespace 天然隔离，资源名就是 `mysql`、`nacos` 这种简单名字，不支持多环境并存（要多套就开多个 Namespace，需要自行改清单）。
- **数据卷**：对应 compose 里的 named volume（`mysql-data`、`nacos-data`、`minio-data` 等）都改成了 `PersistentVolumeClaim`，走 Docker Desktop 默认 StorageClass 动态供给；`config/` 下 `mysql/initdb`、`mysql/conf`、`postgres/initdb`、`rocketmq/broker/conf`、`seata/resources` 这几个需要挂载仓库真实文件的，用 `hostPath` 挂载 `/run/desktop/mnt/host/d/workspace/yudao/yudao-env/config/...`（Docker Desktop for Windows 固定的宿主机路径映射规则，盘符小写）。**如果这个仓库不是放在 `D:\workspace\yudao\yudao-env`，需要手动把 `k8s/services/*.yaml` 里所有 `hostPath.path` 改成实际路径对应的映射。**
- **中间件的"可选启动"**：compose 用 `--profile`，K8s 版本用方案选择——核心方案 `k8s/schemes/core` 包含 mysql、redis、nacos、tdengine、nginx，其余服务默认不部署；菜单中单个中间件的启动生成单服务临时方案部署，停止对应 `kubectl delete deployment,service`（特意只删 Deployment/Service，不碰 PVC，避免误删数据）。
- **NORA 鉴权**：`k8s/services/nora.yaml` 从 Secret `yudao-env` 读取 `NORA_*` 变量，从 Secret `nora-htpasswd` 挂载 htpasswd。菜单 `43` / `7` 启动前，如果 `config\nora\auth\users.htpasswd` 存在，会自动把它同步为 `nora-htpasswd`。节点拉取 NORA 中的镜像时用 `localhost:4000/...`（`hostPort` 4000）。

### k8s\yudao-k8s.bat 菜单说明

菜单编号跟 `compose\yudao.bat` 完全对齐（`1`-`6` 核心操作、`11`-`29`、`41`/`51`、`42`/`52`、`43`/`53` 中间件单独启停、`7`/`8` 中间件全启全停、`44`/`54` OrcaSlicer、`31`-`34` 数据库备份还原），只有两处不同：
- `5` 查看日志：K8s 没有内置"一次看全部服务日志"的简单命令，改成交互式输入要看哪个 Deployment 的名字（`mysql`/`nacos`/`redis`/`tdengine`/`nginx` 等），单独 `kubectl logs -f` 跟随。
- `9` 危险操作从"`down -v`"变成"`kubectl delete pvc --all -n yudao`"，效果一样（清空所有数据卷），同样需要手动输入 `DELETE` 二次确认。

数据库备份/还原（`31`-`34`）把 `docker exec %DB_CONTAINER%` 换成了 `kubectl exec deploy/mysql`，其余逻辑（`mysqldump` 参数、时间戳命名、`backups/` 目录）跟 compose 版本完全一样，两个脚本生成的备份文件可以互相还原。

## 常见问题

- **`chcp`/`where`/`docker` 报"不是内部或外部命令"**：Windows 系统 PATH 缺了 `C:\Windows\System32`。脚本已经在开头临时把 `%SystemRoot%\System32` 等目录加回本进程 PATH，一般不用管；如果还报错，说明系统级 PATH 环境变量本身被破坏了，需要在"编辑系统环境变量"里手动修复。
- **IDEA 报 `Command line is too long`**：多模块项目 classpath 太长超过 Windows 命令行限制，跟本仓库无关。在 Run/Debug Configuration 里勾选 `Modify options → Shorten command line`，选 `JAR manifest` 或 `@argfiles`。
- **多个服务启动报 `Port XXXX was already in use`**：先确认不是同一个端口被两个 yudao-cloud 模块同时占用（各模块端口在各自 `application.yaml` 里写死，检查有没有重复），再排查是否有上一次运行残留的进程没退出（`netstat -ano | findstr <端口>` 找 PID，`taskkill /PID <pid> /F` 杀掉）。
- **应用连的数据库名对不上**：这个仓库的主库名是 `ruoyi-vue-pro`（在 `config/mysql/initdb/01-create-databases.sql` 里定义），确认应用的 `application-local.yaml` 数据源 URL 里的库名跟这个一致。
