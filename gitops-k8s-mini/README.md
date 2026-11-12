# gitops-k8s-mini：最小 GitOps 环境

用 yudao-cloud 必需的基础依赖加 4 个轻量服务和 1 个定时同步任务，在独立的 Kubernetes 集群（如 `infra/ubuntu-24.04/k8s-single.md` 搭建的 kubeadm 单机集群）上搭一套最小 GitOps：清单托管在集群内的 Gitea，`gitops-sync` 每 2 分钟拉取并 `kubectl apply -k`，推送即部署。

| 服务 | 镜像 | 用途 | hostPort | 存储 |
|---|---|---|---|---|
| postgresql | `postgres:16-alpine` | 业务主库 `ruoyi-vue-pro` | 5432 | `postgresql-data` 5Gi |
| redis | `redis:7` | 缓存 | 6379 | 无（不持久化） |
| rabbitmq | `rabbitmq:4.1-management` | 消息队列 | 5672、15672（管理控制台） | `rabbitmq-data` 2Gi |
| r-nacos | `qingpan/rnacos:v0.8.8` | 注册 / 配置中心（兼容 Nacos 客户端协议） | 8848、9848（gRPC）、10848（控制台） | `r-nacos-data` 1Gi |
| loki | `11notes/loki:3.7.9` | 日志存储与查询（接收 OTLP 日志，保留 7 天） | 3100 | `loki-data` 5Gi |
| gitea | `gitea/gitea:28.3.0` | Git 仓库，GitOps 的唯一来源（SQLite，只开 HTTP） | 3000 | `gitea-data` 5Gi |
| nora | `ghcr.io/getnora-io/nora:1.4.4` | 制品仓库（Docker / Maven / npm 代理缓存） | 4000 | `nora-data` 20Gi |
| gitops-sync | `alpine/k8s:1.36.2` | CronJob：从 Gitea 拉取清单并 apply | 无 | 无 |

```text
本机 git push ──▶ Gitea（yudao-mini/gitea）
                     ▲  每 2 分钟浅克隆 GITOPS_BRANCH
                     │
              CronJob gitops-sync ──▶ kubectl apply -k <GITOPS_PATH>
                                       （postgresql、redis、rabbitmq、r-nacos、loki、gitea、nora、gitops-sync 自身）
```

## 与 `gitops-k8s/` 的区别

- **更少、更轻**：postgresql、redis、rabbitmq、nora 保留；去掉 minio（文件改用数据库或本地存储）；Nacos 换成 r-nacos（Rust 实现，几十 MB 内存），Grafana LGTM 换成单独的 Loki（distroless，只存日志）。
- **真正的 GitOps**：`gitops-k8s` 是上传文件后手工 `apply -k`；本目录启用同步后以 Gitea 中的内容为准，服务器上不再手工 apply。没有引入 Argo CD / Flux，同步用一个 CronJob 完成，不常驻进程。
- **独立命名空间 `yudao-mini`**：与 `gitops-k8s` 的 `yudao` 互不影响；Secret 同样叫 `yudao-env`，但在 `yudao-mini` 中，用本目录的 `.env` 生成。
- **引导资源单独一层**：命名空间、`gitops-sync` 的 ServiceAccount / Role 在 `bootstrap/`，手工 apply 一次，不参与同步。同步任务只有命名空间内权限，同步的清单里不能放 Namespace、ClusterRole 等集群级资源。
- **配置文件进 ConfigMap**：`config/loki.yml`、`config/gitops-sync.sh` 由 `configMapGenerator` 生成，名称带内容哈希，改了文件后对应 Pod 自动滚动更新。
- 沿用 `gitops-k8s` 的约定：变量名用镜像原生名、每个服务用 `secretKeyRef` 只取自己的键、端口写在清单的 `hostPort`、不使用 hostPath、依赖默认 StorageClass（local-path）。`services/` 下的 postgresql、redis、rabbitmq、nora 从 `gitops-k8s` 复制，两边分开维护，改镜像版本时注意同步。

### 与 `gitops-k8s` 装在同一集群

两套都用 `hostPort`，以下端口冲突，只能二选一，或改其中一套清单的 `hostPort`：

| 端口 | gitops-k8s | gitops-k8s-mini |
|---|---|---|
| 5432、6379、5672、15672 | postgresql、redis、rabbitmq | 同左 |
| 8848、9848 | nacos | r-nacos |
| 3000 | lgtm（Grafana） | gitea |
| 4000 | nora | nora |

## 目录

```text
gitops-k8s-mini/
├── bootstrap/                 # 手工 apply 一次：Namespace yudao-mini、gitops-sync 的 ServiceAccount / Role / RoleBinding
├── kustomization.yaml         # 同步入口：services/* + configMapGenerator
├── services/                  # 每个服务一个文件（PVC + Deployment + Service；gitops-sync 为 CronJob）
├── config/
│   ├── loki.yml               # Loki 配置，挂载为 /loki/etc/default.yml
│   └── gitops-sync.sh         # 同步脚本
├── .env.temp                  # 本目录专用的环境变量模板（提交）
└── .env                       # 由 .env.temp 新建，含口令（不提交）
```

## 部署

以下命令中的 `kubernetes-admin@kubernetes` 是 kubeadm 的默认上下文名，与 `kubectl config get-contexts` 不同时整体替换。与 `gitops-k8s` 一样，每条命令单独一行，不用管道和 `\` 续行。

### 1. 本机：新建 .env

```bash
cd gitops-k8s-mini
cp .env.temp .env
```

`.env` 已存在时不要覆盖。修改 `.env`，替换所有 `CHANGE_ME`，`GITOPS_*` 先留空（第 6 步再填）：

| 变量 | 填写 |
|---|---|
| `POSTGRES_PASSWORD`、`REDIS_PASSWORD`、`RABBITMQ_DEFAULT_PASS`、`RNACOS_INIT_ADMIN_PASSWORD` | 自定义口令；可用 `openssl rand -hex 16` 生成 |
| `GITEA__security__SECRET_KEY` | `openssl rand -hex 32` 生成，之后不要再改 |
| `GITEA__server__ROOT_URL` | `http://<服务器IP>:3000/` |
| `NORA_PUBLIC_URL` | `http://<服务器IP>:4000` |

```bash
grep -n CHANGE_ME .env   # 没有输出才算填完
```

### 2. 本机：上传到服务器

服务器目录与 `gitops-k8s` 并列：`/opt/yudao/gitops-k8s-mini`。目录权限的设置方法见 `../gitops-k8s/README.md` 第 1 步。在本机 `yudao-env` 仓库根目录执行：

```bash
rsync -av gitops-k8s-mini <用户>@<服务器>:/opt/yudao/
```

上传后在服务器上 `chmod 600 /opt/yudao/gitops-k8s-mini/.env`。启用 GitOps 之后，清单改动走 Gitea，这个目录只用于引导和重建 Secret。

### 3. 服务器：引导、创建 Secret、首次部署

```bash
cd /opt/yudao/gitops-k8s-mini
kubectl --context kubernetes-admin@kubernetes apply -k bootstrap
kubectl --context kubernetes-admin@kubernetes -n yudao-mini delete secret yudao-env --ignore-not-found
kubectl --context kubernetes-admin@kubernetes -n yudao-mini create secret generic yudao-env --from-env-file=.env
kubectl --context kubernetes-admin@kubernetes apply -k .
kubectl --context kubernetes-admin@kubernetes get pods,svc,pvc,cronjob -n yudao-mini -o wide
```

成功标准：`postgresql`、`redis`、`rabbitmq`、`r-nacos`、`loki`、`gitea`、`nora` 7 个 Pod 都是 `Running` 且 `READY 1/1`，PVC 都是 `Bound`。`gitops-sync` 此时每 2 分钟运行一次，日志为 `[跳过] ... 未配置 GITOPS_REPO_URL`，属正常。

Secret `yudao-env` 中用到的键：

| 服务 | 键 | 必填 |
|---|---|---|
| postgresql | `POSTGRES_USER`、`POSTGRES_PASSWORD`（`POSTGRES_DB` 固定为 `ruoyi-vue-pro`，写在清单中） | 是 |
| redis | `REDIS_PASSWORD`（可为空，但必须有这一行） | 是 |
| rabbitmq | `RABBITMQ_DEFAULT_USER`、`RABBITMQ_DEFAULT_PASS`（只在数据卷首次初始化时生效） | 是 |
| r-nacos | `RNACOS_INIT_ADMIN_USERNAME`、`RNACOS_INIT_ADMIN_PASSWORD`（只在空库首次启动时生效） | 是 |
| gitea | `GITEA__server__ROOT_URL`、`GITEA__security__SECRET_KEY` | 是 |
| nora | `NORA_PUBLIC_URL`、`NORA_MAVEN_PROXIES`、`NORA_NPM_PROXY`、`NORA_DOCKER_PROXIES` | 否 |
| gitops-sync | `GITOPS_REPO_URL`、`GITOPS_BRANCH`、`GITOPS_PATH`、`GITOPS_GIT_USERNAME`、`GITOPS_GIT_TOKEN` | 否 |

loki 不需要 Secret。

PostgreSQL 表结构只需在空库上导入一次（脚本首行是 `\connect "ruoyi-vue-pro"`）。在本机 `yudao-env` 仓库根目录执行，SQL 经 ssh 直接传给 Pod：

```bash
PSQL='kubectl --context kubernetes-admin@kubernetes exec -i -n yudao-mini deploy/postgresql -- sh -c "psql -U \$POSTGRES_USER -v ON_ERROR_STOP=1"'
ssh <用户>@<服务器> "$PSQL" < config/postgres/initdb/02-yudao-schema.sql
ssh <用户>@<服务器> "$PSQL" < config/postgres/initdb/03-yudao-quartz.sql
```

### 4. 服务器：创建 Gitea 管理员

跳过了安装向导（`INSTALL_LOCK=true`）且关闭了注册，第一个账号用命令创建。`admin` 是 Gitea 保留名，换一个用户名；`--random-password` 会在输出中打印随机口令，首次登录时要求修改：

```bash
kubectl --context kubernetes-admin@kubernetes -n yudao-mini exec deploy/gitea -- su git -c "gitea admin user create --admin --username <Gitea 用户> --email <邮箱> --random-password"
```

成功标准：输出 `New user '<Gitea 用户>' has been successfully created!`，用打印出的口令登录 `http://<服务器IP>:3000`。

### 5. 本机：把仓库推送到 Gitea

在 Gitea「设置 → 应用 → 生成令牌」生成两个令牌：

- **推送用**（本机）：权限 `repository` 读写。
- **同步用**（gitops-sync）：权限 `repository` 只读。

在本机 `yudao-env` 仓库根目录添加远程并推送。开启了 `ENABLE_PUSH_CREATE_USER`，仓库不存在时自动创建（私有），也可以先在网页上建好：

```bash
git remote add gitea http://<服务器IP>:3000/<Gitea 用户>/yudao-env.git
git push gitea feature/dev
```

提示输入账号口令时，用户名填 `<Gitea 用户>`，密码填**推送用令牌**。推送前确认仓库里没有跟踪含真实口令的文件（`git ls-files | grep -i env`）。

### 6. 本机 + 服务器：启用 GitOps

本机修改 `gitops-k8s-mini/.env`：

```bash
GITOPS_REPO_URL=http://gitea:3000/<Gitea 用户>/yudao-env.git   # 集群内 Service 名，不走节点 IP
GITOPS_BRANCH=feature/dev
GITOPS_PATH=gitops-k8s-mini
GITOPS_GIT_USERNAME=<Gitea 用户>
GITOPS_GIT_TOKEN=<同步用令牌>
```

重新上传 `.env`（第 2 步），在服务器上重建 Secret：

```bash
cd /opt/yudao/gitops-k8s-mini
kubectl --context kubernetes-admin@kubernetes -n yudao-mini delete secret yudao-env --ignore-not-found
kubectl --context kubernetes-admin@kubernetes -n yudao-mini create secret generic yudao-env --from-env-file=.env
kubectl --context kubernetes-admin@kubernetes -n yudao-mini create job --from=cronjob/gitops-sync gitops-sync-manual
kubectl --context kubernetes-admin@kubernetes -n yudao-mini logs -f job/gitops-sync-manual
```

成功标准：日志依次输出 `[信息] 同步 feature/dev@<提交号>，目录 gitops-k8s-mini`、各资源的 `unchanged` / `configured`、`[完成] 同步结束`。手工触发的 Job 用完后 `kubectl --context kubernetes-admin@kubernetes -n yudao-mini delete job gitops-sync-manual`。

## GitOps 同步

启用后的日常流程：本机修改 `gitops-k8s-mini/` 下的清单 → 提交 → `git push gitea feature/dev`，最多 2 分钟后生效。同时推到 Gitee 的方法：`git push origin feature/dev` 与 `git push gitea feature/dev` 各执行一次。

- **以 Git 为准**：在服务器上 `kubectl edit`、`scale` 等手工改动，会在下一次同步时被覆盖（`apply` 会把副本数恢复成清单中的值）。停止服务要在清单里改 `replicas: 0` 后推送。
- **只增改，不删除**：同步没有开启 `--prune`。从清单删除某个服务后，要手工删除对应资源，例如 `kubectl --context kubernetes-admin@kubernetes -n yudao-mini delete deployment/loki service/loki`。改了 `config/` 下的文件后，旧的带哈希 ConfigMap 会留下，可以按需删除。
- **Secret 不走 Git**：改 `.env` 后仍按第 6 步上传、重建 Secret，再 `rollout restart` 对应服务（Secret 变化不会自动重启 Pod）。
- **暂停同步**（排查问题时临时手工操作）：

  ```bash
  kubectl --context kubernetes-admin@kubernetes -n yudao-mini patch cronjob gitops-sync -p '{"spec":{"suspend":true}}'
  kubectl --context kubernetes-admin@kubernetes -n yudao-mini patch cronjob gitops-sync -p '{"spec":{"suspend":false}}'
  ```

  清单中没有写 `suspend`，同步不会覆盖这个值。

- **查看同步记录**：

  ```bash
  kubectl --context kubernetes-admin@kubernetes -n yudao-mini get cronjob,jobs -l app=gitops-sync
  kubectl --context kubernetes-admin@kubernetes -n yudao-mini logs -l app=gitops-sync --tail=50
  ```

- 改 `bootstrap/` 后需要在服务器上手工 `apply -k bootstrap`，同步不会处理。

## 服务地址与账号

`<IP>` 为 K8s 节点 IP。集群内同一命名空间直接用 Service 名，其他命名空间用 `<服务>.yudao-mini.svc.cluster.local`。

| 服务 | 外部地址 | 集群内地址 | 账号 |
|---|---|---|---|
| postgresql | `jdbc:postgresql://<IP>:5432/ruoyi-vue-pro` | `postgresql:5432` | `POSTGRES_USER` / `POSTGRES_PASSWORD` |
| redis | `redis://<IP>:6379` | `redis:6379` | 只有密码 `REDIS_PASSWORD` |
| rabbitmq | `amqp://<IP>:5672/`，管理控制台 `http://<IP>:15672` | `rabbitmq:5672` | `RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS` |
| r-nacos | 服务 `<IP>:8848`，控制台 `http://<IP>:10848` | `r-nacos:8848` | 控制台：`RNACOS_INIT_ADMIN_USERNAME` / `RNACOS_INIT_ADMIN_PASSWORD`；客户端接口不鉴权 |
| loki | `http://<IP>:3100` | `loki:3100` | 无（不鉴权，单租户） |
| gitea | `http://<IP>:3000` | `gitea:3000` | 第 4 步创建的管理员 |
| nora | `http://<IP>:4000/ui/` | `nora:4000` | 无（不鉴权，任何人可读写） |

查看 Secret 中的口令：

```bash
kubectl --context kubernetes-admin@kubernetes -n yudao-mini get secret yudao-env -o go-template='{{.data.RNACOS_INIT_ADMIN_PASSWORD | base64decode}}{{"\n"}}'
```

检查服务是否可用：

```bash
kubectl --context kubernetes-admin@kubernetes -n yudao-mini exec deploy/postgresql -- pg_isready
kubectl --context kubernetes-admin@kubernetes -n yudao-mini exec deploy/redis -- redis-cli ping
kubectl --context kubernetes-admin@kubernetes -n yudao-mini exec deploy/rabbitmq -- rabbitmq-diagnostics -q ping
curl -s -o /dev/null -w "%{http_code}\n" http://<IP>:10848/
curl -s -o /dev/null -w "%{http_code}\n" http://<IP>:3100/ready
curl -s -o /dev/null -w "%{http_code}\n" http://<IP>:3000/api/healthz
curl -s -o /dev/null -w "%{http_code}\n" http://<IP>:4000/health
```

成功标准：`pg_isready` 输出 `accepting connections`；`redis-cli ping` 输出 `PONG`（设了密码时报 `NOAUTH` 也说明服务在线）；rabbitmq 无报错；`curl` 都返回 `200`（r-nacos 控制台可能返回 `302` 跳转，也算正常）。

## 后端 yudao-cloud 对接

### PostgreSQL、Redis、RabbitMQ

后端设置 `DB_PRIMARY=postgresql`，`PG_HOST`、Redis、RabbitMQ 地址从 `127.0.0.1` 换成 `<IP>`，账号口令与 Secret 一致。表结构按第 3 步导入一次。

### r-nacos

- 地址改为 `NACOS_HOST=<IP>`、`NACOS_PORT=8848`；gRPC 端口客户端自动用 9848。
- yudao-cloud 默认使用命名空间 `dev`：先在 r-nacos 控制台「命名空间」中新建 ID 为 `dev` 的命名空间，配置也要在控制台重新创建（可从原 Nacos 导出后导入，格式兼容）。
- 客户端接口未开鉴权（`RNACOS_ENABLE_OPEN_API_AUTH=false`），后端配置的 `NACOS_USERNAME` / `NACOS_PASSWORD` 不校验。要开启时把 `services/r-nacos.yaml` 中的值改为 `"true"` 并推送，后端改用控制台中的用户。

### Loki（日志）

yudao-cloud 用 OTLP HTTP 上报日志，Loki 3 原生接收 OTLP，直接改上报地址即可；本环境没有链路和指标存储，关闭这两项上报：

```bash
MANAGEMENT_OPENTELEMETRY_LOGGING_EXPORT_OTLP_ENDPOINT=http://<IP>:3100/otlp/v1/logs
MANAGEMENT_TRACING_EXPORT_ENABLED=false
MANAGEMENT_OTLP_METRICS_EXPORT_ENABLED=false
```

本环境没有 Grafana，查询日志用 Loki HTTP API，或在已有的 Grafana 中添加 Loki 数据源 `http://<IP>:3100`。OTLP 的 `service.name` 会转成标签 `service_name`：

```bash
curl -s http://<IP>:3100/loki/api/v1/labels
curl -s -G http://<IP>:3100/loki/api/v1/query_range --data-urlencode 'query={service_name="gateway-server"}' --data-urlencode 'limit=20'
```

### NORA

用法与 `gitops-k8s` 相同，上游加速地址的选择和检查方法见 `../gitops-k8s/README.md`「NORA 上游加速地址」。

## 常用操作

服务名：`postgresql`、`redis`、`rabbitmq`、`r-nacos`、`loki`、`gitea`、`nora`，以下以 `gitea` 为例。

```bash
kubectl --context kubernetes-admin@kubernetes get pods,svc,pvc,cronjob -n yudao-mini -o wide
kubectl --context kubernetes-admin@kubernetes describe pod -n yudao-mini -l app=gitea
kubectl --context kubernetes-admin@kubernetes logs -f -n yudao-mini deployment/gitea
kubectl --context kubernetes-admin@kubernetes rollout restart deployment/gitea -n yudao-mini
```

删除：

```bash
# 全部服务，保留数据（PVC、Secret、命名空间保留）；启用 GitOps 时先暂停同步，否则 2 分钟内会被重新创建
kubectl --context kubernetes-admin@kubernetes delete deployment,service,cronjob --all -n yudao-mini

# 全部删除，连同数据（删除命名空间 yudao-mini，其中的 Secret、PVC、Gitea 仓库一并删除，数据不可恢复）
kubectl --context kubernetes-admin@kubernetes delete -k bootstrap
```

Gitea 的仓库数据在 `gitea-data` PVC 中；删除前确认本机或 Gitee 上有完整副本。

## 常见问题

### Pod 报 `CreateContainerConfigError`

原因：Secret `yudao-env` 不存在，或缺少该服务的必填键。

解决：`kubectl --context kubernetes-admin@kubernetes -n yudao-mini describe secret yudao-env` 只看键名，按「Secret `yudao-env` 中用到的键」补齐 `.env` 后重建 Secret。

### `gitops-sync` 报 `Authentication failed` / `not found`

原因：令牌错误或没有该仓库的读权限；或 `GITOPS_REPO_URL` 写成了节点 IP、仓库路径不对；或 `GITOPS_BRANCH` 在 Gitea 中不存在。

解决：在本机用 `git ls-remote http://<IP>:3000/<Gitea 用户>/yudao-env.git` 确认仓库和分支存在；地址用 Service 名 `http://gitea:3000/...`；令牌重新生成后按第 6 步重建 Secret。

### `gitops-sync` 报 `forbidden`

原因：同步的清单里有 Namespace、ClusterRole 等集群级资源，或资源写了其他命名空间。`gitops-sync` 只有 `yudao-mini` 内的权限。

解决：集群级资源放到 `bootstrap/` 手工 apply；同步的清单不要写 `namespace`，由 `kustomization.yaml` 统一添加。

### `alpine/k8s` 拉取失败

原因：`alpine/k8s` 的标签是 kubectl 版本，加速地址可能没有缓存该标签。

解决：`services/gitops-sync.yaml` 换成与集群版本相同或相邻的版本（kubectl 支持与服务端相差 ±1 个小版本），推送前在节点上 `sudo crictl pull docker.io/alpine/k8s:<版本>` 确认能拉取。注意：同步任务本身拉不到镜像时无法通过 Git 修复，需在服务器上直接 `kubectl --context kubernetes-admin@kubernetes apply -k .`（服务器目录先同步成新清单）。

### loki 反复重启，日志 `permission denied`

原因：PVC 目录不属于 1000 组，镜像用户无法写入 `/loki/var`。

解决：`services/loki.yaml` 已设置 `fsGroup: 1000`；local-path 以外的 StorageClass 不支持 `fsGroup` 时，在节点上把 PVC 目录 `chown -R 1000:1000`。

### RabbitMQ 账号密码不生效

原因：`RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS` 只在 `rabbitmq-data` 首次初始化时写入。

解决：在管理控制台（15672）改密码；或确认没有数据后删除 rabbitmq 的 Deployment 和 PVC `rabbitmq-data`，下一次同步（或手工 `apply -k .`）会重新创建。

### Gitea 管理员忘记口令

```bash
kubectl --context kubernetes-admin@kubernetes -n yudao-mini exec deploy/gitea -- su git -c "gitea admin user change-password --username <Gitea 用户> --password <新口令>"
```

## 校验

```bash
kubectl kustomize gitops-k8s-mini > /dev/null             # 离线渲染，不连接集群
kubectl kustomize gitops-k8s-mini/bootstrap > /dev/null
```

## 注意

- 端口用 `hostPort` 暴露到节点所有网卡，只适合内网开发测试环境；loki、nora 不鉴权，r-nacos 客户端接口不鉴权。
- `gitops-sync` 的 Role 拥有 `yudao-mini` 内全部权限（包括读取 Secret），能推送到同步分支的人等同于能操作整个命名空间，控制好 Gitea 仓库的写权限。
- `/opt/yudao/gitops-k8s-mini/.env` 含全部口令，保持 `600` 权限。
- 删除 PVC 会丢失数据；`local-path` 的数据在节点 `/opt/local-path-provisioner`。
