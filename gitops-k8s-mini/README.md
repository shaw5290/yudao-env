# gitops-k8s-mini：最小 GitOps 环境

用 yudao-cloud 必需的基础依赖加几个轻量服务，在自建 Kubernetes 集群（如 `infra/ubuntu-24.04/k8s-single.md` 搭建的 kubeadm 单机集群）上搭一套 GitOps：清单托管在 **Gitee**（`yudao-env` 仓库的本目录），集群中的 **Flux CD** 持续拉取并应用，推送即部署；应用镜像放在**阿里云容器镜像服务 ACR**，Flux 可自动把 ACR 中的新 Tag 写回 Gitee。支持 **local、dev、test、prod** 四个环境，每个环境一个集群。

| 服务 | 镜像 | 用途 | hostPort | 存储 |
|---|---|---|---|---|
| postgresql | `postgres:16-alpine` | 业务主库 `ruoyi-vue-pro` | 5432 | `postgresql-data` 5Gi |
| redis | `redis:7` | 缓存 | 6379 | 无（不持久化） |
| rabbitmq | `rabbitmq:4.1-management` | 消息队列 | 5672、15672（管理控制台） | `rabbitmq-data` 2Gi |
| r-nacos | `qingpan/rnacos:v0.8.8` | 注册 / 配置中心（兼容 Nacos 客户端协议） | 8848、9848（gRPC）、10848（控制台） | `r-nacos-data` 1Gi |
| loki | `11notes/loki:3.7.9` | 日志存储与查询（接收 OTLP 日志，保留 7 天） | 3100 | `loki-data` 5Gi |
| nora | `ghcr.io/getnora-io/nora:1.4.4` | 制品仓库（Docker / Maven / npm 代理缓存） | 4000 | `nora-data` 20Gi |
| ~~gitea~~ | `gitea/gitea:28.3.0` | **已停用**：Git 仓库改用 Gitee；清单 `base/services/gitea.yaml` 保留备查，未被引用 | — | — |
| ~~gitops-sync~~ | `alpine/k8s:1.36.2` | **已停用**：同步改用 Flux CD；清单、脚本保留备查，未被引用 | — | — |

```text
本机 git push ──▶ Gitee（imshaw/yudao-env，目录 gitops-k8s-mini）
                     ▲  Flux source-controller 每分钟检查新提交（GitRepository yudao-env）
                     │
   集群 <环境> ── Flux kustomize-controller ──▶ apply overlays/<环境>（命名空间 yudao-<环境>）
                     │
   ACR ◀── image-reflector-controller 扫描新 Tag ── image-automation-controller 把 Tag 提交回 Gitee（local / dev）
```

| 环境 | 集群 | 跟踪分支 | 同步目录 | ACR 镜像自动更新 |
|---|---|---|---|---|
| local | 本地自建集群（当前 192.168.31.66） | `feature/dev` | `overlays/local` | 可选（`clusters/local/image-automation.yaml`） |
| dev | 开发集群 | `feature/dev` | `overlays/dev` | 可选（`clusters/dev/image-automation.yaml`） |
| test | 测试集群 | `main` | `overlays/test` | 否，手工晋升 |
| prod | 生产集群 | `main` | `overlays/prod` | 否，手工晋升 |

## 与 `gitops-k8s/` 的区别

- **更少、更轻**：postgresql、redis、rabbitmq、nora 保留；去掉 minio（文件改用数据库或本地存储）；Nacos 换成 r-nacos（Rust 实现，几十 MB 内存），Grafana LGTM 换成单独的 Loki（distroless，只存日志）。
- **真正的 GitOps**：`gitops-k8s` 是上传文件后手工 `apply -k`；本目录由 Flux CD 从 Gitee 同步，以 Git 中的内容为准，服务器上不再手工 apply。Flux 常驻 4 个控制器（source、kustomize、image-reflector、image-automation），合计约 200~300 MB 内存。
- **命名空间 `yudao-<环境>`**（`yudao-local`、`yudao-dev`、`yudao-test`、`yudao-prod`，每个环境一个集群）：与 `gitops-k8s` 的 `yudao` 互不影响；Secret 同样叫 `yudao-env`，但在本环境命名空间中，用本目录的 `.env` 生成。
- **多环境**：`base/` 是共用清单，`overlays/<环境>/` 只写差异，`clusters/<环境>/` 是该环境集群的 Flux 同步配置。
- **引导资源单独一层**：命名空间、默认 ServiceAccount（挂 ACR 拉取凭证）在 `bootstrap/<环境>/`（共用部分在 `bootstrap/base/`），手工 apply 一次，不参与同步，避免一次错误提交把命名空间连同数据删掉。
- **配置文件进 ConfigMap**：`base/config/loki.yml` 由 `configMapGenerator` 生成，名称带内容哈希，改了文件后对应 Pod 自动滚动更新。
- 沿用 `gitops-k8s` 的约定：变量名用镜像原生名、每个服务用 `secretKeyRef` 只取自己的键、端口写在清单的 `hostPort`、不使用 hostPath、依赖默认 StorageClass（local-path）。`base/services/` 下的 postgresql、redis、rabbitmq、nora 从 `gitops-k8s` 复制，两边分开维护，改镜像版本时注意同步。

### 与 `gitops-k8s` 装在同一集群

两套都用 `hostPort`，以下端口冲突，只能二选一，或改其中一套清单的 `hostPort`：

| 端口 | gitops-k8s | gitops-k8s-mini |
|---|---|---|
| 5432、6379、5672、15672 | postgresql、redis、rabbitmq | 同左 |
| 8848、9848 | nacos | r-nacos |
| 3000 | lgtm（Grafana） | —（gitea 已停用，不再冲突） |
| 4000 | nora | nora |

## 目录

```text
gitops-k8s-mini/
├── bootstrap/                 # 每个集群手工 apply 一次 bootstrap/<环境>：Namespace yudao-<环境>、默认 ServiceAccount（imagePullSecrets acr-auth）
│   ├── base/                  # 各环境共用的引导清单，不写 namespace
│   └── <环境>/                # local、dev、test、prod：只指定 namespace
├── base/                      # 各环境共用
│   ├── kustomization.yaml     # 公共标签、services、configMapGenerator、PVC 防 prune 注解（不写 namespace；gitea、gitops-sync 已注释）
│   ├── services/              # 每个服务一个文件（PVC + Deployment + Service）
│   └── config/loki.yml        # Loki 配置，挂载为 /loki/etc/default.yml
├── overlays/                  # 各环境差异：local、dev、test、prod（namespace / images / patches）
├── clusters/                  # 各环境集群的 Flux 配置：local、dev、test、prod
│   └── <环境>/
│       ├── kustomization.yaml     # 手工 apply 一次的入口
│       ├── gitrepository.yaml     # GitRepository yudao-env：Gitee 地址、分支、凭证 gitee-auth
│       ├── sync.yaml              # Flux Kustomization yudao-<环境>：同步 overlays/<环境>
│       └── image-automation.yaml  # 仅 local、dev：ACR 镜像自动更新（默认未启用）
├── kustomization.yaml         # 兼容旧用法，等同于 overlays/local
├── .env.temp                  # Secret yudao-env 模板（提交）
└── .env                       # 由 .env.temp 新建，含口令（不提交）
```

## 部署

以下命令中的 `kubernetes-admin@kubernetes` 是 kubeadm 的默认上下文名，与 `kubectl config get-contexts` 不同时整体替换。与 `gitops-k8s` 一样，每条命令单独一行，不用管道和 `\` 续行。

### 1. 本机：新建 .env

```bash
cd gitops-k8s-mini
cp .env.temp .env
```

`.env` 已存在时不要覆盖。修改 `.env`，替换所有 `CHANGE_ME`（Gitea、GitOps 同步两段已注释，不用填）：

| 变量 | 填写 |
|---|---|
| `POSTGRES_PASSWORD`、`REDIS_PASSWORD`、`RABBITMQ_DEFAULT_PASS`、`RNACOS_INIT_ADMIN_PASSWORD` | 自定义口令；可用 `openssl rand -hex 16` 生成 |
| `NORA_PUBLIC_URL` | `http://<服务器IP>:4000` |

```bash
grep -n CHANGE_ME .env   # 没有输出才算填完
```

### 2. 本机：上传到服务器

服务器目录与 `gitops-k8s` 并列：`/opt/yudao/gitops-k8s-mini`。目录权限的设置方法见 `../gitops-k8s/README.md` 第 1 步。在本机 `yudao-env` 仓库根目录执行：

```bash
rsync -av gitops-k8s-mini <用户>@<服务器>:/opt/yudao/
```

上传后在服务器上 `chmod 600 /opt/yudao/gitops-k8s-mini/.env`。启用 Flux 之后，清单改动走 Gitee，这个目录只用于引导、创建 Secret 和 Flux 配置。每个环境的集群各上传一份，`.env` 按环境分别填写。

### 3. 服务器：引导、创建 Secret yudao-env

```bash
cd /opt/yudao/gitops-k8s-mini
kubectl --context kubernetes-admin@kubernetes apply -k bootstrap/<环境>
kubectl --context kubernetes-admin@kubernetes -n yudao-<环境> delete secret yudao-env --ignore-not-found
kubectl --context kubernetes-admin@kubernetes -n yudao-<环境> create secret generic yudao-env --from-env-file=.env
kubectl --context kubernetes-admin@kubernetes -n yudao-<环境> describe secret yudao-env
```

`<环境>` 换成本集群的环境名（`local`、`dev`、`test`、`prod`），下同。成功标准：命名空间 `yudao-<环境>`、ServiceAccount `default` 已创建；`describe secret` 列出下表中的键。服务由第 7 步的 Flux 部署，不再手工 `apply -k`（Flux 不可用时的应急方式：`kubectl --context kubernetes-admin@kubernetes apply -k overlays/<环境>`）。

Secret `yudao-env` 中用到的键：

| 服务 | 键 | 必填 |
|---|---|---|
| postgresql | `POSTGRES_USER`、`POSTGRES_PASSWORD`（`POSTGRES_DB` 固定为 `ruoyi-vue-pro`，写在清单中） | 是 |
| redis | `REDIS_PASSWORD`（可为空，但必须有这一行） | 是 |
| rabbitmq | `RABBITMQ_DEFAULT_USER`、`RABBITMQ_DEFAULT_PASS`（只在数据卷首次初始化时生效） | 是 |
| r-nacos | `RNACOS_INIT_ADMIN_USERNAME`、`RNACOS_INIT_ADMIN_PASSWORD`（只在空库首次启动时生效） | 是 |
| nora | `NORA_PUBLIC_URL`、`NORA_MAVEN_PROXIES`、`NORA_NPM_PROXY`、`NORA_DOCKER_PROXIES` | 否 |

loki 不需要 Secret。Gitee、ACR 的凭证不放在 `yudao-env` 中，在第 5、6 步单独创建。

PostgreSQL 表结构在第 7 步 postgresql 就绪后、空库上导入一次（脚本首行是 `\connect "ruoyi-vue-pro"`）。在本机 `yudao-env` 仓库根目录执行，SQL 经 ssh 直接传给 Pod：

```bash
PSQL='kubectl --context kubernetes-admin@kubernetes exec -i -n yudao-<环境> deploy/postgresql -- sh -c "psql -U \$POSTGRES_USER -v ON_ERROR_STOP=1"'
ssh <用户>@<服务器> "$PSQL" < config/postgres/initdb/02-yudao-schema.sql
ssh <用户>@<服务器> "$PSQL" < config/postgres/initdb/03-yudao-quartz.sql
```

### 4. 服务器：安装 Flux

每个环境的集群执行一次。先安装 Flux CLI（`fluxcd.io` 下载不了时，在能访问 GitHub 的机器上下载 [flux 发布包](https://github.com/fluxcd/flux2/releases) 解压出 `flux` 放到 `/usr/local/bin/`）：

```bash
curl -fsSL -o /tmp/flux-install.sh https://fluxcd.io/install.sh
sudo bash /tmp/flux-install.sh
flux --version
flux check --pre
```

Flux 控制器镜像在 `ghcr.io/fluxcd`，节点的 Docker Hub 加速对它无效，国内用 `--registry` 指向 ghcr 加速地址。先导出清单查看镜像，在节点上试拉一个：

```bash
flux install --components-extra=image-reflector-controller,image-automation-controller --registry=ghcr.m.daocloud.io/fluxcd --export > /tmp/flux-install.yaml
grep "image:" /tmp/flux-install.yaml
sudo crictl pull ghcr.m.daocloud.io/fluxcd/source-controller:<上一步输出中的标签>
```

`crictl pull` 输出 `Image is up to date` 后安装。返回 `403` 说明该加速源不代理这个镜像，换其他 ghcr 加速地址，或在能访问 ghcr.io 的机器上 `docker save` 后用 `sudo ctr -n k8s.io images import <文件>.tar` 导入节点：

```bash
flux install --components-extra=image-reflector-controller,image-automation-controller --registry=ghcr.m.daocloud.io/fluxcd
flux check
```

成功标准：`flux check` 全部 `✔`，`flux-system` 中 4 个控制器 `Running`。不用 ACR 镜像自动更新时可以去掉 `--components-extra`，省两个控制器的内存。

### 5. 服务器：Gitee 凭证 gitee-auth

Flux 用 HTTPS 拉取 Gitee 仓库，账号为 Gitee 用户名，密码为 Gitee **私人令牌**（Gitee「设置 → 私人令牌」生成，权限勾选 `projects`；启用 ACR 镜像自动更新时令牌要有推送权限）：

```bash
flux create secret git gitee-auth --namespace=flux-system --url=https://gitee.com/imshaw/yudao-env.git --username=<Gitee 用户名> --password=<Gitee 私人令牌>
kubectl --context kubernetes-admin@kubernetes -n flux-system describe secret gitee-auth
```

仓库公开且不启用镜像自动更新时可以不建，同时删除 `clusters/<环境>/gitrepository.yaml` 中的 `secretRef`。令牌不要写进仓库或 `.env`。

### 6. 服务器：ACR 凭证 acr-auth

应用镜像放在 ACR 时创建（只用公开镜像可跳过）。`<ACR 地址>` 个人版为 `registry.cn-<地域>.aliyuncs.com`，企业版为 `<实例名>-registry.cn-<地域>.cr.aliyuncs.com`；本地服务器不在阿里云 VPC 内，用公网地址，不要用 `registry-vpc`。账号为阿里云账号全名，口令为 ACR 控制台「访问凭证」中设置的固定密码：

```bash
kubectl --context kubernetes-admin@kubernetes -n yudao-<环境> create secret docker-registry acr-auth --docker-server=<ACR 地址> --docker-username=<阿里云账号> --docker-password=<ACR 固定密码>
kubectl --context kubernetes-admin@kubernetes -n flux-system create secret docker-registry acr-auth --docker-server=<ACR 地址> --docker-username=<阿里云账号> --docker-password=<ACR 固定密码>
```

- 本环境命名空间中的 `acr-auth`：Pod 拉取 ACR 私有镜像，由 `bootstrap/base/default-serviceaccount.yaml` 挂到默认 ServiceAccount，清单中不用写 `imagePullSecrets`。
- `flux-system` 中的 `acr-auth`：image-reflector-controller 扫描 ACR Tag，只在启用镜像自动更新时需要。
- 改口令时两处都先 `delete secret acr-auth --ignore-not-found` 再建。

### 7. 服务器：启用 Flux 同步

```bash
cd /opt/yudao/gitops-k8s-mini
kubectl --context kubernetes-admin@kubernetes apply -k clusters/local
flux get sources git
flux get kustomizations
kubectl --context kubernetes-admin@kubernetes -n yudao-local get pods,svc,pvc -o wide
```

`local` 换成本集群对应的环境。成功标准：GitRepository `yudao-env` 和 Kustomization `yudao-local` 都是 `READY True`，MESSAGE 中有当前提交号；`postgresql`、`redis`、`rabbitmq`、`r-nacos`、`loki`、`nora` 6 个 Pod 都是 `Running 1/1`，PVC 都是 `Bound`。之后按第 3 步末尾导入 PostgreSQL 表结构。

**已用旧命名空间 `yudao-mini` 部署过的集群**（包括旧方式 Gitea + gitops-sync）：命名空间改为 `yudao-<环境>` 后，Flux 部署到新的命名空间，旧命名空间中的资源和 PVC 不会自动迁移，也不会被删除；两边 hostPort 相同，旧服务不停新 Pod 会一直 `Pending`。需要保留的数据（PostgreSQL 等）先从旧命名空间导出、导入新命名空间，确认 Gitee 上有完整的仓库副本后删除旧命名空间（其中的 Secret、PVC、Gitea 仓库一并删除，不可恢复）：

```bash
kubectl --context kubernetes-admin@kubernetes -n yudao-mini exec deploy/postgresql -- sh -c "pg_dump -U \$POSTGRES_USER -d ruoyi-vue-pro --clean --if-exists" > /tmp/ruoyi-vue-pro.sql
kubectl --context kubernetes-admin@kubernetes delete namespace yudao-mini
```

先执行第一条（PostgreSQL 无数据可跳过），再删除旧命名空间，最后执行第 3 步、第 7 步；新库就绪后用 `kubectl --context kubernetes-admin@kubernetes exec -i -n yudao-<环境> deploy/postgresql -- sh -c "psql -U \$POSTGRES_USER -d ruoyi-vue-pro"` 加 `< /tmp/ruoyi-vue-pro.sql` 导入（代替第 3 步末尾的表结构导入）。

### 8. 可选：ACR 镜像自动更新（local、dev）

适合 local / dev：CI 把新镜像推到 ACR 后，Flux 自动把 Tag 写进 `overlays/<环境>/kustomization.yaml` 并提交回 Gitee，再部署。

1. 把 `clusters/<环境>/image-automation.yaml` 中的示例 `yudao-gateway` 换成实际镜像（每个镜像一组 ImageRepository + ImagePolicy），在 `clusters/<环境>/kustomization.yaml` 中取消 `image-automation.yaml` 的注释。
2. 在 `overlays/<环境>/kustomization.yaml` 的 `images` 中给 `newTag` 加标记：`newTag: "2.6.0" # {"$imagepolicy": "flux-system:yudao-gateway:tag"}`。
3. 推送到 Gitee 后在服务器上执行 `kubectl --context kubernetes-admin@kubernetes apply -k clusters/<环境>`，检查 `flux get images all`。

Flux 的自动提交会推到 `feature/dev`，本机先 `git pull` 再改，避免冲突。

## 日常变更与环境晋升

本机修改 `gitops-k8s-mini/` 下的清单 → 提交 → `git push origin <分支>`（推到 Gitee），Flux 在 1~2 分钟内应用。

- **改哪里**：所有环境共用的改 `base/`；只影响一个环境的改 `overlays/<环境>/`（`images`、`patches`）。提交前离线渲染：`kubectl kustomize gitops-k8s-mini/overlays/<环境>`。
- **晋升**：local / dev 跟踪 `feature/dev`，test / prod 跟踪 `main`。在 local / dev 验证后，把 `overlays/test`（之后 `overlays/prod`）的镜像 Tag 改成验证过的版本，合并 `feature/dev` 到 `main` 并推送，test / prod 集群自动部署。`base/` 的改动合并到 `main` 后会同时影响 test 和 prod，先在 `overlays/test` 中验证。
- **以 Git 为准**：在集群上 `kubectl edit`、`scale` 等手工改动会在下一次同步（2 分钟）时被改回。临时停止服务，在 `overlays/<环境>` 中用 patch 把 `replicas` 设为 0 并推送。
- **删除会同步**：`prune: true`，从清单删除某个服务后 Flux 会删除它的 Deployment、Service、ConfigMap；**PVC 除外**（`base/kustomization.yaml` 给 PVC 加了 `kustomize.toolkit.fluxcd.io/prune: disabled`），确认不再需要数据后手工 `kubectl --context kubernetes-admin@kubernetes -n yudao-<环境> delete pvc <名称>`。
- **Secret 不走 Git**：改 `.env` 后按第 3 步删除重建 Secret，再 `rollout restart` 对应服务（Secret 变化不会自动重启 Pod）。
- **立即同步**（不等周期）：

  ```bash
  flux reconcile kustomization yudao-<环境> --with-source
  ```

- **暂停 / 恢复同步**（排查问题时临时手工操作）：

  ```bash
  flux suspend kustomization yudao-<环境>
  flux resume kustomization yudao-<环境>
  ```

- **查看同步状态**：

  ```bash
  flux get sources git
  flux get kustomizations
  flux logs --level=error
  ```

- 改 `bootstrap/`、`clusters/<环境>/` 后需要在服务器上手工 `apply -k`，Flux 不同步这两个目录。

## 服务地址与账号

`<IP>` 为 K8s 节点 IP。集群内同一命名空间直接用 Service 名，其他命名空间用 `<服务>.yudao-<环境>.svc.cluster.local`。

| 服务 | 外部地址 | 集群内地址 | 账号 |
|---|---|---|---|
| postgresql | `jdbc:postgresql://<IP>:5432/ruoyi-vue-pro` | `postgresql:5432` | `POSTGRES_USER` / `POSTGRES_PASSWORD` |
| redis | `redis://<IP>:6379` | `redis:6379` | 只有密码 `REDIS_PASSWORD` |
| rabbitmq | `amqp://<IP>:5672/`，管理控制台 `http://<IP>:15672` | `rabbitmq:5672` | `RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS` |
| r-nacos | 服务 `<IP>:8848`，控制台 `http://<IP>:10848` | `r-nacos:8848` | 控制台：`RNACOS_INIT_ADMIN_USERNAME` / `RNACOS_INIT_ADMIN_PASSWORD`；客户端接口不鉴权 |
| loki | `http://<IP>:3100` | `loki:3100` | 无（不鉴权，单租户） |
| nora | `http://<IP>:4000/ui/` | `nora:4000` | 无（不鉴权，任何人可读写） |

查看 Secret 中的口令：

```bash
kubectl --context kubernetes-admin@kubernetes -n yudao-<环境> get secret yudao-env -o go-template='{{.data.RNACOS_INIT_ADMIN_PASSWORD | base64decode}}{{"\n"}}'
```

检查服务是否可用：

```bash
kubectl --context kubernetes-admin@kubernetes -n yudao-<环境> exec deploy/postgresql -- pg_isready
kubectl --context kubernetes-admin@kubernetes -n yudao-<环境> exec deploy/redis -- redis-cli ping
kubectl --context kubernetes-admin@kubernetes -n yudao-<环境> exec deploy/rabbitmq -- rabbitmq-diagnostics -q ping
curl -s -o /dev/null -w "%{http_code}\n" http://<IP>:10848/
curl -s -o /dev/null -w "%{http_code}\n" http://<IP>:3100/ready
curl -s -o /dev/null -w "%{http_code}\n" http://<IP>:4000/health
```

成功标准：`pg_isready` 输出 `accepting connections`；`redis-cli ping` 输出 `PONG`（设了密码时报 `NOAUTH` 也说明服务在线）；rabbitmq 无报错；`curl` 都返回 `200`（r-nacos 控制台可能返回 `302` 跳转，也算正常）。

## 后端 yudao-cloud 对接

### PostgreSQL、Redis、RabbitMQ

后端设置 `DB_PRIMARY=postgresql`，`PG_HOST`、Redis、RabbitMQ 地址从 `127.0.0.1` 换成 `<IP>`，账号口令与 Secret 一致。表结构按第 3 步末尾导入一次。

### r-nacos

- 地址改为 `NACOS_HOST=<IP>`、`NACOS_PORT=8848`；gRPC 端口客户端自动用 9848。
- yudao-cloud 默认使用命名空间 `dev`：先在 r-nacos 控制台「命名空间」中新建 ID 为 `dev` 的命名空间，配置也要在控制台重新创建（可从原 Nacos 导出后导入，格式兼容）。
- 客户端接口未开鉴权（`RNACOS_ENABLE_OPEN_API_AUTH=false`），后端配置的 `NACOS_USERNAME` / `NACOS_PASSWORD` 不校验。要开启时把 `services/r-nacos.yaml` 中的值改为 `"true"` 并推送到 Gitee，后端改用控制台中的用户。

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

服务名：`postgresql`、`redis`、`rabbitmq`、`r-nacos`、`loki`、`nora`，以下以 `r-nacos` 为例。

```bash
kubectl --context kubernetes-admin@kubernetes get pods,svc,pvc -n yudao-<环境> -o wide
kubectl --context kubernetes-admin@kubernetes describe pod -n yudao-<环境> -l app=r-nacos
kubectl --context kubernetes-admin@kubernetes logs -f -n yudao-<环境> deployment/r-nacos
kubectl --context kubernetes-admin@kubernetes rollout restart deployment/r-nacos -n yudao-<环境>
```

删除：

```bash
# 全部服务，保留数据（PVC、Secret、命名空间保留）；先 flux suspend kustomization yudao-<环境>，否则 2 分钟内会被重新创建
kubectl --context kubernetes-admin@kubernetes delete deployment,service --all -n yudao-<环境>

# 全部删除，连同数据（删除命名空间 yudao-<环境>，其中的 Secret、PVC 一并删除；先 flux suspend kustomization yudao-<环境>，数据不可恢复）
kubectl --context kubernetes-admin@kubernetes delete -k bootstrap/<环境>
```

清单在 Gitee 上，删除集群资源不影响仓库。停用 Flux 同步：`kubectl --context kubernetes-admin@kubernetes delete -k clusters/<环境>`（Kustomization 被删除时 `prune` 会删除它同步过的资源，PVC 因带 `prune: disabled` 注解保留）。

## 常见问题

### Pod 报 `CreateContainerConfigError`

原因：Secret `yudao-env` 不存在，或缺少该服务的必填键。

解决：`kubectl --context kubernetes-admin@kubernetes -n yudao-<环境> describe secret yudao-env` 只看键名，按「Secret `yudao-env` 中用到的键」补齐 `.env` 后重建 Secret。

### GitRepository `yudao-env` 报 `authentication required` / `not found`

原因：Secret `gitee-auth` 不存在、私人令牌错误或已过期；或 `clusters/<环境>/gitrepository.yaml` 的分支在 Gitee 上不存在。

解决：本机 `git ls-remote https://gitee.com/imshaw/yudao-env.git <分支>` 确认分支存在；重新生成私人令牌后按第 5 步重建 `gitee-auth`（`flux create secret git` 会覆盖），再 `flux reconcile source git yudao-env`。

### Flux Kustomization `yudao-<环境>` 不是 READY

`flux get kustomizations` 的 MESSAGE 列给出原因：构建失败（本机 `kubectl kustomize gitops-k8s-mini/overlays/<环境>` 复现）；健康检查超时（`wait: true`，某个 Deployment 未就绪，按下文排查对应 Pod）；`namespaces "yudao-<环境>" not found`（第 3 步的 `bootstrap/<环境>` 未 apply）。

### Pod 拉取 ACR 镜像报 `unauthorized` / `pull access denied`

原因：本环境命名空间中没有 `acr-auth`，或账号口令、ACR 地址（地域、个人版 / 企业版）不对；或默认 ServiceAccount 没有 `imagePullSecrets`（`bootstrap/<环境>` 未重新 apply）。

解决：在节点上 `sudo crictl pull --creds <阿里云账号>:<ACR 固定密码> <ACR 镜像地址>` 验证；按第 6 步重建 `acr-auth`，再用 `kubectl --context kubernetes-admin@kubernetes -n yudao-<环境> get sa default -o yaml` 确认有 `acr-auth`。

### Flux 控制器 `ImagePullBackOff`

原因：`ghcr.io/fluxcd` 的镜像在国内拉不到，或 `--registry` 指向的加速源不代理。

解决：按第 4 步在节点上 `crictl pull` 验证加速地址，换可用的地址后重新执行 `flux install ... --registry=<地址>`。

### loki 反复重启，日志 `permission denied`

原因：PVC 目录不属于 1000 组，镜像用户无法写入 `/loki/var`。

解决：`services/loki.yaml` 已设置 `fsGroup: 1000`；local-path 以外的 StorageClass 不支持 `fsGroup` 时，在节点上把 PVC 目录 `chown -R 1000:1000`。

### RabbitMQ 账号密码不生效

原因：`RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS` 只在 `rabbitmq-data` 首次初始化时写入。

解决：在管理控制台（15672）改密码；或确认没有数据后删除 rabbitmq 的 Deployment 和 PVC `rabbitmq-data`，下一次同步（或手工 `apply -k .`）会重新创建。

## 以后转 Helm

当前用 Kustomize（base + overlays），清单已按下面的对应关系组织，以后可以直接改写成 Helm chart，PVC 数据保留。

| 现在（Kustomize） | 转 Helm 后 |
|---|---|
| `base/services/*.yaml` | `chart/templates/*.yaml`，镜像、副本数、端口、PVC 大小换成 `{{ .Values.xxx }}` |
| `overlays/<环境>/` 的 `namespace` | `helm upgrade --install -n <命名空间>`（base 中不写 namespace，模板中也不写） |
| `overlays/<环境>/` 的 `images`、`patches` | `values-<环境>.yaml`（如 `loki.image.tag`、`loki.replicas`）；公共默认值放 `values.yaml` |
| `base/kustomization.yaml` 的 `labels` | `_helpers.tpl` 中的公共标签 |
| `configMapGenerator`（名称带哈希，改配置自动滚动更新） | `.Files.Get` 生成固定名称的 ConfigMap，Pod 模板加注解 `checksum/config: {{ include (print $.Template.BasePath "/xxx.yaml") . \| sha256sum }}` |
| Flux `Kustomization`（`clusters/<环境>/sync.yaml`） | Flux `HelmRelease`，`chart` 引用同一个 GitRepository 中的 chart 目录，`valuesFiles` 指向 `values-<环境>.yaml` |
| PVC 注解 `kustomize.toolkit.fluxcd.io/prune: disabled` | 保留，并加 `helm.sh/resource-policy: keep`（`helm uninstall` 不删 PVC） |
| Secret `yudao-env`、`acr-auth`、`bootstrap/` | 不变，仍手工创建，chart 只引用 |

写 chart 时必须保持不变，否则会重建资源或丢数据：

- **资源名**：Deployment、Service、PVC 的名称与现在相同（不要用 `{{ .Release.Name }}-xxx` 前缀），PVC 才能按原名接上数据。
- **selector**：Deployment 的 `selector.matchLabels` 保持 `app: <服务名>`（selector 不可修改，改了只能删除重建）；Helm 推荐的 `app.kubernetes.io/name`、`app.kubernetes.io/instance` 只加到 metadata 和 Pod 模板，不加进 selector。

切换步骤（在一个环境验证后再做下一个，先 local / dev）：

1. 本机 `helm template` 渲染 chart，与 `kubectl kustomize gitops-k8s-mini/overlays/<环境>` 对比，除标签、注解、ConfigMap 名称外应一致。
2. `flux suspend kustomization yudao-<环境>`。
3. 给现有资源加 Helm 归属，`helm install` 才能接管（否则报 `invalid ownership metadata`）：标签 `app.kubernetes.io/managed-by=Helm`，注解 `meta.helm.sh/release-name=<release>`、`meta.helm.sh/release-namespace=yudao-<环境>`，对象为 Deployment、Service、PVC、ConfigMap。
4. 删除 Flux Kustomization（`kubectl delete -f clusters/<环境>/sync.yaml`）；Deployment 等会被 prune，PVC 因注解保留。为避免服务中断，也可以先在 Kustomization 中设 `prune: false` 并推送，再删除。
5. apply HelmRelease，确认 Pod 挂载的是原 PVC、数据还在；旧的带哈希 ConfigMap 手工删除。

## 校验

```bash
kubectl kustomize gitops-k8s-mini/overlays/local > /dev/null   # 离线渲染，不连接集群；dev、test、prod 同理
kubectl kustomize gitops-k8s-mini/bootstrap/local > /dev/null
kubectl kustomize gitops-k8s-mini/clusters/local > /dev/null
```

## 注意

- 端口用 `hostPort` 暴露到节点所有网卡，只适合内网开发测试环境；loki、nora 不鉴权，r-nacos 客户端接口不鉴权。
- Flux 的 kustomize-controller 拥有集群管理员权限，能推送到 `feature/dev` / `main` 的人等同于能操作对应集群，控制好 Gitee 仓库的写权限；`main`（test / prod）建议开启分支保护，只允许合并请求。
- Gitee 私人令牌、ACR 固定密码只放在集群 Secret 中，不写进仓库、`.env` 或提交信息。
- `/opt/yudao/gitops-k8s-mini/.env` 含全部口令，保持 `600` 权限。
- 删除 PVC 会丢失数据；`local-path` 的数据在节点 `/opt/local-path-provisioner`。
