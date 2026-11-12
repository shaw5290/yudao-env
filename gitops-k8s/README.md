# gitops-k8s：基础依赖（服务器手动部署版）

在独立的 Kubernetes 集群（如 `infra/ubuntu-24.04/k8s-single.md` 搭建的 kubeadm 单机集群）上部署 yudao 的基础依赖。本目录从本机上传到服务器的 `/opt/yudao/gitops-k8s`，在服务器上执行 `kubectl apply -k`，不经过 Git 远程仓库。

| 服务 | 镜像 | hostPort | 存储 |
|---|---|---|---|
| postgres | `postgres:16-alpine` | 5432 | `postgres-data` 5Gi |
| redis | `redis:7` | 6379 | 无（不持久化） |
| nacos | `nacos/nacos-server:v3.0.3` | 8848、8080（控制台）、9848、9849 | `nacos-data`、`nacos-logs`、`nacos-plugins` |
| rabbitmq | `rabbitmq:4.1-management` | 5672、15672（管理控制台） | `rabbitmq-data` 2Gi |
| minio | `minio/minio:latest` | 9000、9001（控制台） | `minio-data` 5Gi |
| lgtm | `grafana/otel-lgtm:0.37.0` | 3000（Grafana）、4317、4318 | `lgtm-data` 5Gi |
| nora | `ghcr.io/getnora-io/nora:1.4.4` | 4000 | `nora-data` 20Gi |

## 与 `k8s/` 的区别

- **自包含**：只引用本目录内的文件，不需要 `--load-restrictor LoadRestrictionsNone`，可直接 `apply -k`；以后改用 Argo CD / Flux 也能直接指向本目录。
- **不使用 hostPath**：不依赖 Docker Desktop 的 `/run/desktop/mnt/host/...` 路径。
  - postgres 不挂载 `config/postgres/initdb`，由 `POSTGRES_DB=ruoyi-vue-pro` 建业务库，表结构需手工导入（见下文）。
  - nacos 不连接 MySQL，使用内置存储（Derby），数据在 `nacos-data` PVC。
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
    ├── .env.temp             # 从本机仓库根目录上传的环境变量模板
    └── .env                  # 在服务器上由 .env.temp 新建，含密码，chmod 600
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

### 2. 本机：上传文件

图形工具（Xftp、WinSCP 等）：远程目录选 `/opt/yudao/`，把本机 `D:\workspace\yudao\yudao-env\gitops-k8s` 整个文件夹拖进去；再把本机仓库根目录的 `.env.temp`（环境变量模板）拖到 `/opt/yudao/gitops-k8s/`。

命令行：在本机 `yudao-env` 仓库根目录执行，`<用户>@<服务器>` 换成实际值；服务器没有 rsync 时先 `sudo apt install -y rsync`：

```bash
rsync -av gitops-k8s <用户>@<服务器>:/opt/yudao/
scp .env.temp <用户>@<服务器>:/opt/yudao/gitops-k8s/.env.temp
```

### 3. 服务器：新建 .env

由根目录模板 `.env.temp` 新建 `.env`，本方案用到的口令自动生成随机值，NORA 下载地址改成服务器 IP：

```bash
cd /opt/yudao/gitops-k8s
cp .env.temp .env
chmod 600 .env
sed -i 's/\r$//' .env                                 # 模板来自 Windows，去掉 CRLF
sed -i "s|^NACOS_AUTH_TOKEN=.*|NACOS_AUTH_TOKEN=$(openssl rand -base64 32)|" .env
for k in POSTGRES_PASSWORD REDIS_PASSWORD NACOS_AUTH_IDENTITY_VALUE RABBITMQ_PASSWORD MINIO_ROOT_PASSWORD; do
  sed -i "s|^$k=.*|$k=$(openssl rand -hex 16)|" .env
done
sed -i "s|^NORA_PUBLIC_URL=.*|NORA_PUBLIC_URL=http://$(hostname -I | awk '{print $1}'):4000|" .env
grep -E '^(POSTGRES_USER|RABBITMQ_USERNAME|MINIO_ROOT_USER|NORA_PUBLIC_URL)=' .env
```

成功标准：`NORA_PUBLIC_URL` 为服务器 IP。模板中 MySQL、Nacos 连接 MySQL、RocketMQ、Seata 等变量本方案不使用，保留 `CHANGE_ME` 即可。

- 生成的口令在 `.env` 中查看（`cat .env`），后端 yudao-cloud 连接这些服务时使用同样的账号密码。
- `RABBITMQ_PASSWORD` 只在 `rabbitmq-data` 首次初始化时生效，Secret 建好后不要再重新生成；`.env` 不要覆盖，重新上传模板时只传 `.env.temp`。

### 4. 服务器：创建 Secret 并部署

所有 kubectl 命令都显式指定上下文。本文命令中的 `kubernetes-admin@kubernetes` 是 kubeadm 的默认上下文名，`get-contexts` 输出不同时，把文中所有命令的上下文名替换为实际值：

```bash
cd /opt/yudao/gitops-k8s
kubectl config get-contexts                          # 确认上下文名

kubectl --context kubernetes-admin@kubernetes create namespace yudao --dry-run=client -o yaml | kubectl --context kubernetes-admin@kubernetes apply -f -
kubectl --context kubernetes-admin@kubernetes create secret generic yudao-env --from-env-file=.env -n yudao --dry-run=client -o yaml | kubectl --context kubernetes-admin@kubernetes apply -f -
kubectl --context kubernetes-admin@kubernetes apply -k .
kubectl --context kubernetes-admin@kubernetes get pods,svc,pvc -n yudao -o wide
```

成功标准：7 个 Pod 都是 `Running` 且 `READY 1/1`，PVC 都是 `Bound`。

Secret `yudao-env` 中用到的键：

| 服务 | 键 |
|---|---|
| postgres | `POSTGRES_USER`、`POSTGRES_PASSWORD` |
| redis | `REDIS_PASSWORD`（必填） |
| nacos | `NACOS_AUTH_ENABLE`、`NACOS_AUTH_TOKEN`、`NACOS_AUTH_IDENTITY_KEY`、`NACOS_AUTH_IDENTITY_VALUE`（任一为空 Nacos 会直接退出） |
| rabbitmq | `RABBITMQ_USERNAME`、`RABBITMQ_PASSWORD`（只在数据卷首次初始化时生效） |
| minio | `MINIO_ROOT_USER`、`MINIO_ROOT_PASSWORD` |
| nora | `NORA_PUBLIC_URL`、`NORA_MAVEN_PROXIES`、`NORA_NPM_PROXY`、`NORA_DOCKER_PROXIES`（均可选）；不开鉴权，`NORA_AUTH_*` 不读取 |

### 5. 本机：PostgreSQL 导入表结构

postgres 就绪后，只需在空库上执行一次（脚本首行是 `\connect "ruoyi-vue-pro"`）。在本机 `yudao-env` 仓库根目录执行，SQL 经 ssh 直接传给服务器上的 Pod，不落盘：

```bash
ssh <用户>@<服务器> 'kubectl --context kubernetes-admin@kubernetes exec -i -n yudao deploy/postgres -- sh -c "psql -U \$POSTGRES_USER -v ON_ERROR_STOP=1"' < config/postgres/initdb/02-yudao-schema.sql
ssh <用户>@<服务器> 'kubectl --context kubernetes-admin@kubernetes exec -i -n yudao deploy/postgres -- sh -c "psql -U \$POSTGRES_USER -v ON_ERROR_STOP=1"' < config/postgres/initdb/03-yudao-quartz.sql
```

## 更新

本机修改清单后重新执行第 2 步上传，再在服务器上 `apply`；改了 `.env` 时同时重建 Secret 并重启相关服务（Secret 变化不会自动重启 Pod）：

```bash
cd /opt/yudao/gitops-k8s
kubectl --context kubernetes-admin@kubernetes apply -k .
kubectl --context kubernetes-admin@kubernetes create secret generic yudao-env --from-env-file=.env -n yudao --dry-run=client -o yaml | kubectl --context kubernetes-admin@kubernetes apply -f -
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

有 PVC 的服务是 `Recreate` 策略，重启时先停旧 Pod 再起新 Pod，期间服务短暂不可用。

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

## 校验

```bash
kubectl kustomize gitops-k8s > /dev/null   # 离线渲染，不连接集群
```

## 注意

- 端口用 `hostPort` 暴露到节点所有网卡，只适合内网开发测试环境。
- NORA 固定不开鉴权（`NORA_AUTH_ENABLED=false`），能访问 4000 端口的人都能推送镜像、上传制品。
- `/opt/yudao/gitops-k8s/.env` 含全部口令，保持 `600` 权限；用图形工具上传后检查权限，必要时重新 `chmod 600`。
- 删除 PVC 会丢失数据；`local-path` 的数据在节点 `/opt/local-path-provisioner`。
