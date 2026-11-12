# gitops-k8s：基础依赖（服务器手动部署版）

在独立的 Kubernetes 集群（如 `infra/ubuntu-24.04/k8s-single.md` 搭建的 kubeadm 单机集群）上部署 yudao 的基础依赖。本目录从本机上传到服务器的 `/opt/yudao/gitops-k8s`，在服务器上执行 `kubectl apply -k`，不经过 Git 远程仓库。

| 服务 | 镜像 | hostPort | 存储 |
|---|---|---|---|
| postgres | `postgres:16-alpine` | 5432 | `postgres-data` 5Gi |
| redis | `redis:7` | 6379 | 无（不持久化） |
| nacos | `nacos/nacos-server:v3.0.3` | 8848、8080（控制台）、9848、9849 | `nacos-data`、`nacos-logs`、`nacos-plugins` |
| rabbitmq | `rabbitmq:4.1-management` | 5672、15672（管理控制台） | `rabbitmq-data` 2Gi |
| minio | `minio/minio:RELEASE.2025-09-07T16-13-09Z` | 9000、9001（控制台） | `minio-data` 5Gi |
| lgtm | `grafana/otel-lgtm:0.37.0` | 3000（Grafana）、4317、4318 | `lgtm-data` 5Gi |
| nora | `ghcr.io/getnora-io/nora:1.4.4` | 4000 | `nora-data` 20Gi |

## 与 `k8s/` 的区别

- **自包含**：只引用本目录内的文件，不需要 `--load-restrictor LoadRestrictionsNone`，可直接 `apply -k`；以后改用 Argo CD / Flux 也能直接指向本目录。
- **不使用 hostPath**：不依赖 Docker Desktop 的 `/run/desktop/mnt/host/...` 路径。
  - postgres 不挂载 `config/postgres/initdb`，由 `POSTGRES_DB=ruoyi-vue-pro` 建业务库，表结构需手工导入（见下文）。
  - nacos 不连接 MySQL，使用内置存储（Derby），数据在 `nacos-data` PVC。
- **环境变量单独一份**：用本目录的 `.env.temp` / `.env`，与根目录（compose、`k8s/` 菜单）分开维护，只含这 7 个服务的变量。
- **变量名用镜像原生名**：如 `POSTGRES_PASSWORD`、`MINIO_ROOT_USER`、`NACOS_AUTH_TOKEN`、`RABBITMQ_DEFAULT_USER`、`NORA_PUBLIC_URL`，清单中按同名取值、不改名；镜像没有原生变量的（redis 密码）用通用名 `REDIS_PASSWORD`。根目录的 `RABBITMQ_USERNAME` / `RABBITMQ_PASSWORD` 在这里是 `RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS`。
- **每个服务只取自己的键**：用 `secretKeyRef` 逐个引用 Secret `yudao-env`，不用 `envFrom` 整体注入；除 NORA 外都是必填，缺键时 Pod 报 `CreateContainerConfigError`，不会带着镜像默认口令启动。
- **端口写在清单里**：K8s 不支持变量替换，各工具的端口写在 `services/<工具>.yaml` 的 `hostPort`，`.env` 中没有端口变量；冲突时直接改清单。
- 清单从 `k8s/services/` 复制后修改，两边**分开维护**；改镜像版本、端口时注意同步。
- 依赖集群有默认 StorageClass（kubeadm 集群按 `k8s-single.md` 第六节安装 local-path）。

## 服务器目录

服务器上只放本目录（整个 `gitops-k8s` 文件夹），`.env` 也放在里面：

```text
/opt/yudao/
└── gitops-k8s/               # 从本机上传整个文件夹；不要在服务器上直接改，改本机后重新上传
    ├── kustomization.yaml    # 在 /opt/yudao/gitops-k8s 下执行 apply -k .
    ├── namespace.yaml
    ├── services/
    ├── README.md
    ├── .env.temp             # 本目录专用的环境变量模板（提交）
    └── .env                  # 本机由 .env.temp 新建后随文件夹上传，含密码，chmod 600（不提交）
```

PostgreSQL 表结构脚本不上传，导入时从本机通过 ssh 直接传给 Pod（见第 5 步）。

## 部署

### 1. 服务器：建目录并设置权限

用平时登录、上传文件的账号（有 sudo 权限的普通账号，与安装 K8s 的账号相同）执行。`<上传账号>` 写上传工具里配置的用户名，不要在 `sudo -i` 之后用 `$USER`（会变成 root）：

```bash
U=<上传账号>
sudo mkdir -p /opt/yudao/gitops-k8s
sudo chown -R "$U":"$U" /opt/yudao      # 归上传账号所有，scp/sftp 才能写入
sudo chmod 755 /opt/yudao /opt/yudao/gitops-k8s
ls -ld /opt/yudao /opt/yudao/gitops-k8s
```

成功标准：两个目录的属主都是 `<上传账号>`。

多个账号都要上传时，改用用户组授权：

```bash
sudo groupadd -f yudao
sudo usermod -aG yudao <上传账号>          # 其他账号同样加入，重新登录后生效
sudo chown -R root:yudao /opt/yudao
sudo chmod -R 2775 /opt/yudao             # setgid：新上传的文件自动属于 yudao 组
```

### 2. 本机：新建 .env

每套部署方式各用一份 env：根目录 `.env.temp` / `.env` 只给本机 compose 和 `k8s/` 菜单用；本目录用自己的模板 `gitops-k8s/.env.temp`（只含这 7 个服务的变量，按服务器场景填写）。

在本机 `gitops-k8s` 目录执行，由模板新建 `.env`（`.env`、`.env.local`、`.env.*` 已被 `.gitignore` 忽略，不会提交）；`.env` 已存在时不要覆盖（RabbitMQ 密码只在数据卷首次初始化时生效）：

```bash
cd gitops-k8s
cp .env.temp .env
```

需要多套配置时按 `.env.local`、`.env.<环境>` 命名，建 Secret 时把 `--from-env-file=.env` 换成对应文件名。

然后修改 `.env`，替换所有 `CHANGE_ME`：

| 变量 | 填写 |
|---|---|
| `POSTGRES_PASSWORD`、`REDIS_PASSWORD`、`RABBITMQ_DEFAULT_PASS`、`MINIO_ROOT_PASSWORD`、`NACOS_AUTH_IDENTITY_VALUE` | 自定义口令；可用 `openssl rand -hex 16` 生成 |
| `NACOS_AUTH_TOKEN` | `openssl rand -base64 32` 生成 |
| `NORA_PUBLIC_URL` | `http://<服务器IP>:4000` |

```bash
grep -n CHANGE_ME .env   # 没有输出才算填完
```

### 3. 本机：上传文件

图形工具（Xftp、WinSCP 等）：远程目录选 `/opt/yudao/`，把本机 `D:\workspace\yudao\yudao-env\gitops-k8s` 整个文件夹（含 `.env`）拖进去。上传后在服务器上确认 `.env` 存在。

命令行：在本机 `yudao-env` 仓库根目录执行，`<用户>@<服务器>` 换成实际值；服务器没有 rsync 时先 `sudo apt install -y rsync`：

```bash
rsync -av gitops-k8s <用户>@<服务器>:/opt/yudao/
```

上传后在服务器上确认并收紧 `.env` 权限（图形工具上传的文件一般是 644）：

```bash
ls -l /opt/yudao/gitops-k8s/.env
chmod 600 /opt/yudao/gitops-k8s/.env
```

### 4. 服务器：创建 Secret 并部署

所有 kubectl 命令都显式指定上下文。本文命令中的 `kubernetes-admin@kubernetes` 是 kubeadm 的默认上下文名，`get-contexts` 输出不同时，把文中所有命令的上下文名替换为实际值：

```bash
cd /opt/yudao/gitops-k8s
kubectl config get-contexts                          # 确认上下文名

kubectl --context kubernetes-admin@kubernetes apply -f namespace.yaml
kubectl --context kubernetes-admin@kubernetes -n yudao delete secret yudao-env --ignore-not-found
kubectl --context kubernetes-admin@kubernetes -n yudao create secret generic yudao-env --from-env-file=.env
kubectl --context kubernetes-admin@kubernetes apply -k .
kubectl --context kubernetes-admin@kubernetes get pods,svc,pvc -n yudao -o wide
```

- 每条命令单独一行，不用管道 `|` 和行尾 `\` 续行：整行粘贴时终端可能截断管道之后的部分（报 `flag needs an argument: --context`），复制的 `\` 后面多出空格时续行失效（报 `-o: command not found`）。
- Secret 用"先删再建"更新：`create` 遇到已存在的 Secret 会报 `AlreadyExists`；成功时输出 `secret/yudao-env created`。
- 检查 Secret：`kubectl --context kubernetes-admin@kubernetes -n yudao describe secret yudao-env`，只列键名和字节数，不显示值。

成功标准：7 个 Pod 都是 `Running` 且 `READY 1/1`，PVC 都是 `Bound`。

Secret `yudao-env` 中用到的键。键名与各镜像原生环境变量一致，清单中按同名取值；每个服务只引用自己的键（不用 `envFrom` 整体注入），除 NORA 外都是必填：

| 服务 | 键（镜像原生变量名） |
|---|---|
| postgres | `POSTGRES_USER`、`POSTGRES_PASSWORD`（`POSTGRES_DB` 固定为 `ruoyi-vue-pro`，写在清单中） |
| redis | `REDIS_PASSWORD`（官方镜像没有原生变量，用通用名，经 `--requirepass` 传入；可为空，但必须有这一行） |
| nacos | `NACOS_AUTH_ENABLE`、`NACOS_AUTH_TOKEN`、`NACOS_AUTH_IDENTITY_KEY`、`NACOS_AUTH_IDENTITY_VALUE`（任一为空 Nacos 会直接退出） |
| rabbitmq | `RABBITMQ_DEFAULT_USER`、`RABBITMQ_DEFAULT_PASS`（只在数据卷首次初始化时生效） |
| minio | `MINIO_ROOT_USER`、`MINIO_ROOT_PASSWORD` |
| nora | `NORA_PUBLIC_URL`、`NORA_MAVEN_PROXIES`、`NORA_NPM_PROXY`、`NORA_DOCKER_PROXIES`（均可选）；不开鉴权，`NORA_AUTH_*` 不读取 |

### 5. 本机：PostgreSQL 导入表结构

postgres 就绪后，只需在空库上执行一次（脚本首行是 `\connect "ruoyi-vue-pro"`）。在本机 `yudao-env` 仓库根目录执行，SQL 经 ssh 直接传给服务器上的 Pod，不落盘：

```bash
PSQL='kubectl --context kubernetes-admin@kubernetes exec -i -n yudao deploy/postgres -- sh -c "psql -U \$POSTGRES_USER -v ON_ERROR_STOP=1"'
ssh <用户>@<服务器> "$PSQL" < config/postgres/initdb/02-yudao-schema.sql
ssh <用户>@<服务器> "$PSQL" < config/postgres/initdb/03-yudao-quartz.sql
```

## 更新

本机修改清单后重新执行第 3 步上传，再在服务器上 `apply`。清单中的环境变量引用变化时 `apply -k` 会自动重建对应 Pod；只改了 `.env` 的值时，重建 Secret 后需要手动重启（Secret 变化不会自动重启 Pod）：

```bash
cd /opt/yudao/gitops-k8s
kubectl --context kubernetes-admin@kubernetes apply -k .
kubectl --context kubernetes-admin@kubernetes -n yudao delete secret yudao-env --ignore-not-found
kubectl --context kubernetes-admin@kubernetes -n yudao create secret generic yudao-env --from-env-file=.env
kubectl --context kubernetes-admin@kubernetes rollout restart deployment -n yudao               # 或只重启指定服务，如 deployment/nacos
```

rsync 和图形工具都不会删除服务器上多出的旧文件；本机删掉了某个服务文件时，同步在服务器上删除，并手工 `kubectl --context kubernetes-admin@kubernetes delete` 对应资源。

## 常用操作

以下命令都在服务器 `/opt/yudao/gitops-k8s` 下执行。服务名：`postgres`、`redis`、`nacos`、`rabbitmq`、`minio`、`lgtm`、`nora`，下文以 `nacos` 为例，操作其他服务时替换服务名和文件名。

### 查看

```bash
kubectl --context kubernetes-admin@kubernetes get pods,svc,pvc -n yudao -o wide             # 全部资源状态
kubectl --context kubernetes-admin@kubernetes describe pod -n yudao -l app=nacos            # Pod 详情，Pending / CrashLoopBackOff 时看 Events
kubectl --context kubernetes-admin@kubernetes logs -f -n yudao deployment/nacos             # 实时日志
kubectl --context kubernetes-admin@kubernetes logs -n yudao deployment/nacos --previous     # 上一次崩溃前的日志
```

### 新建

```bash
# 全部服务（已存在的资源只更新，不会重建）
kubectl --context kubernetes-admin@kubernetes apply -k .

# 单个服务（含该服务的 PVC、Deployment、Service）
kubectl --context kubernetes-admin@kubernetes apply -f services/nacos.yaml -n yudao
```

单个服务用 `-f` 部署时不带公共标签 `app.kubernetes.io/part-of`，之后执行一次 `apply -k .` 会补上，不影响运行。

### 重启

```bash
# 单个服务
kubectl --context kubernetes-admin@kubernetes rollout restart deployment/nacos -n yudao
kubectl --context kubernetes-admin@kubernetes rollout status deployment/nacos -n yudao --timeout=300s

# 全部服务
kubectl --context kubernetes-admin@kubernetes rollout restart deployment -n yudao
```

所有服务都是 `Recreate` 策略（使用 hostPort / 单写 PVC，单节点上新旧 Pod 不能同时运行），重启时先停旧 Pod 再起新 Pod，期间服务短暂不可用。

### 停止 / 启动（保留全部资源）

```bash
kubectl --context kubernetes-admin@kubernetes scale deployment/nacos -n yudao --replicas=0   # 停止
kubectl --context kubernetes-admin@kubernetes scale deployment/nacos -n yudao --replicas=1   # 启动
```

执行 `apply -k .` 会把副本数恢复为 1，停止的服务会被重新启动。

### 删除

```bash
# 单个服务，保留数据（只删 Deployment、Service，PVC 保留，重新新建后数据还在）
kubectl --context kubernetes-admin@kubernetes delete deployment/nacos service/nacos -n yudao --ignore-not-found

# 单个服务，连同数据（会删除该服务的 PVC，数据不可恢复）
kubectl --context kubernetes-admin@kubernetes delete -f services/nacos.yaml -n yudao --ignore-not-found

# 全部服务，保留数据（命名空间、Secret、PVC 保留）
kubectl --context kubernetes-admin@kubernetes delete deployment,service --all -n yudao

# 全部删除，连同数据（删除命名空间 yudao，其中的 Secret、PVC 一并删除，数据不可恢复）
kubectl --context kubernetes-admin@kubernetes delete -k .
```

删除数据前先确认是否需要备份。`local-path` 的 PVC 删除后，节点 `/opt/local-path-provisioner` 下对应目录也会被清理。

## NORA 上游加速地址

NORA 作为 Docker / Maven / npm 的代理缓存，上游配置在 `.env`（模板 `.env.temp`）。原则：**只用有公司或开源项目背书、长期运行的国内加速；官方地址放最后兜底**；不用来源不明的个人 / 公益加速站。

| 仓库 | 变量 | 顺序（前一个失败再试下一个） | 提供方 |
|---|---|---|---|
| Maven | `NORA_MAVEN_PROXIES` | 1. `https://maven.aliyun.com/repository/public` | 阿里云 |
| | | 2. `https://repo.huaweicloud.com/repository/maven` | 华为云 |
| | | 3. `https://mirrors.cloud.tencent.com/nexus/repository/maven-public` | 腾讯云 |
| | | 4. `https://repo1.maven.org/maven2`（官方） | Maven Central |
| Docker | `NORA_DOCKER_PROXIES` | 1. `https://docker.m.daocloud.io` | DaoCloud（开源项目 DaoCloud/public-image-mirror） |
| | | 2. `https://docker.1panel.live` | 飞致云 1Panel |
| | | 3. `https://registry-1.docker.io`（官方） | Docker Hub |
| npm | `NORA_NPM_PROXY` | `https://registry.npmmirror.com` | npmmirror（阿里云支持） |

- **npm 只能配一个上游**：NORA 的 npm 只支持一个默认上游，没有按顺序回退；npmmirror 不可用时，把 `NORA_NPM_PROXY` 改为官方 `https://registry.npmjs.org`。
- **云厂商的 Docker Hub 加速不可用**：阿里云、腾讯云、华为云的 Docker Hub 加速器只对各自云内网络开放，服务器在本地局域网，不在列表中。
- **Docker 加速仍有失效风险**：Docker Hub 国内加速都是免费服务，提供方可能限流或调整；失效时 NORA 会自动尝试下一个，最后回到官方地址（国内直连官方通常也不通）。定期按下文检查，失效的删除。
- **安全**：Maven 依赖带 `.sha1` / `.md5` 校验；Docker 按 digest 拉取的层内容自校验，但**按标签**拉取时标签指向哪个 digest 由上游决定。生产用的关键镜像在清单中写 `镜像@sha256:...` 固定 digest。
- 每个 Docker 上游的缓存按地址分别存放，调整顺序或换地址后会重新从上游下载。
- 改完 `.env` 后重建 Secret 并重启 nora（见「更新」）。

检查上游是否可用（在服务器上执行）：

```bash
# Maven、npm：返回 200 为可用
for u in https://maven.aliyun.com/repository/public https://repo.huaweicloud.com/repository/maven https://mirrors.cloud.tencent.com/nexus/repository/maven-public https://repo1.maven.org/maven2; do
  printf '%s %s\n' "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$u/org/springframework/spring-core/maven-metadata.xml")" "$u"
done
printf '%s %s\n' "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://registry.npmmirror.com/vue)" npmmirror

# Docker：/v2/ 返回 200 或 401 为在线（401 是正常的鉴权质询），000 为不通
for u in https://docker.m.daocloud.io https://docker.1panel.live https://registry-1.docker.io; do
  printf '%s %s\n' "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$u/v2/")" "$u"
done
```

2026-11-12 在本机检查：Maven 4 个、npmmirror 均为 200；DaoCloud 401、1Panel 200（在线）；Docker Hub 官方 000（国内不通，只作兜底）。

## 常见问题

### Pod 报 `CreateContainerConfigError`

原因：Secret `yudao-env` 不存在，或缺少该服务的键（如 `.env` 中没有 `REDIS_PASSWORD` 这一行）。

解决：只看键名、不显示值：

```bash
kubectl --context kubernetes-admin@kubernetes describe pod -n yudao -l app=redis | tail -5
kubectl --context kubernetes-admin@kubernetes -n yudao describe secret yudao-env
```

按"Secret `yudao-env` 中用到的键"补齐 `.env`，重建 Secret 后 `rollout restart` 对应服务。

### Pod 报 `ImagePullBackOff`

原因：镜像拉取失败。服务器配置的 Docker Hub 加速只对 Docker Hub 镜像生效，加速地址也可能没有缓存某个标签。

解决：`describe pod` 查看 Events 中的具体报错，换可用的加速地址或在清单中改为可拉取的固定版本。

### RabbitMQ 账号密码不生效

原因：`RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS` 只在 `rabbitmq-data` 首次初始化时写入，之后修改 `.env` 不会生效。

解决：在管理控制台（15672）改密码；或在确认没有数据后，删除并重建 rabbitmq（`delete -f services/rabbitmq.yaml` 会删除其 PVC），再 `apply -f services/rabbitmq.yaml`。

## 校验

```bash
kubectl kustomize gitops-k8s > /dev/null   # 离线渲染，不连接集群
```

## 注意

- 端口用 `hostPort` 暴露到节点所有网卡，只适合内网开发测试环境。
- NORA 固定不开鉴权（`NORA_AUTH_ENABLED=false`），能访问 4000 端口的人都能推送镜像、上传制品。
- `/opt/yudao/gitops-k8s/.env` 含全部口令，保持 `600` 权限；用图形工具上传后检查权限，必要时重新 `chmod 600`。
- 删除 PVC 会丢失数据；`local-path` 的数据在节点 `/opt/local-path-provisioner`。
