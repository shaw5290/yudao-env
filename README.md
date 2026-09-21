# yudao-env

`yudao-cloud` 本地开发环境的 Docker Compose 配置，一键拉起 MySQL、Redis、Nacos、TDengine 等核心依赖，以及 Jenkins、MinIO、RocketMQ、XXL-Job、Seata、Sentinel 等可选中间件。

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
└── backups/                    # 数据库备份输出目录（脚本自动生成）
```

## 快速开始

1. 安装 Docker Desktop（Windows 下需开启 WSL2 后端），确认 `docker` 命令能在终端直接用。
2. 复制环境变量模板并按需修改：
   ```bash
   copy .env.temp .env
   ```
   必须修改的几项：`MYSQL_ROOT_PASSWORD`、`REDIS_PASSWORD`、`NACOS_DB_PASSWORD`、`NACOS_AUTH_TOKEN`（见下方"Nacos 鉴权"）、`MINIO_ROOT_PASSWORD`、`ROCKETMQ_BROKER_IP`、`SEATA_IP`。
3. 双击运行 `toggle-yudao.bat`，选 **1（启动核心）**。首次启动会自动执行 `mysql/initdb` 下的建库脚本。
4. 核心服务起来后，按需通过菜单单独启动 Jenkins / MinIO / RocketMQ / XXL-Job / Seata / Sentinel。

## 服务清单

### 核心服务（`docker compose up -d` 默认启动，无需 `--profile`）

| 服务 | 镜像 | 默认端口（可在 `.env` 改） | 说明 |
|---|---|---|---|
| nginx | nginx:latest | `NGINX_PORT`→80 | 预留，未配置站点 |
| mysql | mysql:8.0.21 | `MYSQL_PORT`→3306 | root / `MYSQL_ROOT_PASSWORD` |
| redis | redis:7 | `REDIS_PORT`→6379 | 密码见 `REDIS_PASSWORD`，留空则不鉴权 |
| nacos | nacos/nacos-server:v3.0.3 | `NACOS_PORT`(8848) / `NACOS_CONSOLE_PORT`(8081，容器内 8080) / `NACOS_GRPC_PORT`(9848) / `NACOS_GRPC_PORT_2`(9849) | 持久化到 MySQL，见下方"Nacos"说明 |
| tdengine | tdengine/tdengine:3.3.6.0 | `TDENGINE_PORT`(6041，taosAdapter REST/WebSocket) / 6030（taosd 原生端口） | IoT 模块设备时序数据库，见下方"TDengine"说明 |

### 可选中间件（需要 `--profile <name>`，`toggle-yudao.bat` 菜单已封装）

| 服务 | 镜像 | 默认端口 | profile |
|---|---|---|---|
| jenkins | jenkins/jenkins:lts | `JENKINS_PORT`→8080 | jenkins |
| minio | minio/minio:latest | `MINIO_PORT`(9000) / `MINIO_CONSOLE_PORT`(9001) | minio |
| rocketmq-namesrv / rocketmq-broker | apache/rocketmq:5.3.1 | `ROCKETMQ_NAMESRV_PORT`(9876) / `ROCKETMQ_BROKER_PORT`(10911) / `ROCKETMQ_BROKER_VIP_PORT`(10909) | rocketmq |
| xxl-job-admin | xuxueli/xxl-job-admin:2.4.1 | `XXL_JOB_PORT`→8080 | xxl-job |
| seata-server | seataio/seata-server:2.0.0 | `SEATA_PORT`(8091) / `SEATA_DASHBOARD_PORT`(7091) | seata |
| sentinel-dashboard | bladex/sentinel-dashboard:1.8.8 | `SENTINEL_PORT`→8858 | sentinel |

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

- 应用连接地址：`127.0.0.1:${NACOS_PORT}`（默认 8848），控制台：`http://127.0.0.1:${NACOS_CONSOLE_PORT}`（默认 8081）。
- 已预置 `dev` / `test` / `prod` 三个命名空间（`mysql/initdb/02-nacos-schema.sql` 里插入的 `tenant_info` 记录），对应各服务 `application-{profile}.yaml` 里的 `spring.cloud.nacos.*.namespace` 配置，开箱即用。
- **鉴权变量必须都填，不能留空**：`NACOS_AUTH_TOKEN`、`NACOS_AUTH_IDENTITY_KEY`、`NACOS_AUTH_IDENTITY_VALUE` 这三个哪怕不启用鉴权（`NACOS_AUTH_ENABLE` 可以注释/关闭）也必须有值，否则镜像启动脚本会直接 `exit 255`。`NACOS_AUTH_TOKEN` 需要 Base64 编码的 32 字节字符串，生成命令：
  ```bash
  openssl rand -base64 32
  ```

## TDengine（IoT 模块）

IoT 模块用 TDengine 存设备时序消息，跟核心服务一起启动，但有两处需要手动处理：

1. **应用侧**：`yudao-module-iot/yudao-module-iot-server/src/main/resources/application-local.yaml` 里的 `spring.datasource.dynamic.datasource.tdengine` 默认是注释的，需要取消注释才能连上，否则 `IoTServerApplication` 启动时会因为 `TDengineTableInitRunner` 初始化失败直接 `System.exit(1)`。
2. **建库**：IoT 模块代码只会建"超级表"，不会自动建库，容器起来后需要手动执行一次（数据持久化在 `tdengine-data` 卷里，之后重启不用重复执行）：
   ```bash
   docker exec -it yudao-tdengine taos -s "CREATE DATABASE IF NOT EXISTS ruoyi_vue_pro;"
   ```

如果暂时不需要用 IoT 模块，不启动 `IoTServerApplication` 即可，不影响其他服务。

## toggle-yudao.bat 菜单说明

双击运行后是一个交互式菜单，输入编号回车执行：

**核心服务**
- `1` 启动核心（nginx/mysql/redis/nacos/tdengine）
- `2` 停止全部（含所有已启用的中间件 profile，保留数据卷）
- `3` 重启核心
- `4` 查看所有服务状态
- `5` 查看核心服务日志（Ctrl+C 退出）
- `6` 强制重建核心服务（改了镜像版本、环境变量后用这个）

**中间件（单独启停）**：`11`/`21` MinIO，`12`/`22` RocketMQ，`13`/`23` XXL-Job，`14`/`24` Seata，`15`/`25` Sentinel，`16`/`26` Jenkins；`7`/`8` 一键启停全部中间件。

**危险操作**
- `9` 停止全部并**清空所有数据卷**（`down -v`），需要手动输入 `DELETE` 二次确认。用于彻底重置环境、让 `mysql/initdb` 脚本重新执行。

**数据库备份 / 还原**（依赖本机能直接执行 `docker exec`）
- `31` 备份所有非系统库到 `backups/mysql_<时间戳>.sql`
- `32` 从 `backups/` 里选一个文件还原
- `33` 查看备份文件列表
- `34` 查看当前数据库列表

## 常见问题

- **`chcp`/`where`/`docker` 报"不是内部或外部命令"**：Windows 系统 PATH 缺了 `C:\Windows\System32`。脚本已经在开头临时把 `%SystemRoot%\System32` 等目录加回本进程 PATH，一般不用管；如果还报错，说明系统级 PATH 环境变量本身被破坏了，需要在"编辑系统环境变量"里手动修复。
- **IDEA 报 `Command line is too long`**：多模块项目 classpath 太长超过 Windows 命令行限制，跟本仓库无关。在 Run/Debug Configuration 里勾选 `Modify options → Shorten command line`，选 `JAR manifest` 或 `@argfiles`。
- **多个服务启动报 `Port XXXX was already in use`**：先确认不是同一个端口被两个 yudao-cloud 模块同时占用（各模块端口在各自 `application.yaml` 里写死，检查有没有重复），再排查是否有上一次运行残留的进程没退出（`netstat -ano | findstr <端口>` 找 PID，`taskkill /PID <pid> /F` 杀掉）。
- **应用连的数据库名对不上**：这个仓库的主库名是 `ruoyi-vue-pro`（在 `mysql/initdb/01-create-databases.sql` 里定义），确认应用的 `application-local.yaml` 数据源 URL 里的库名跟这个一致。
