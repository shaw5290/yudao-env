# gitops-k8s：基础依赖（GitOps 版）

在独立的 Kubernetes 集群（如 `infra/ubuntu-24.04/k8s-single.md` 搭建的 kubeadm 单机集群）上部署 yudao 的基础依赖，可以交给 Argo CD / Flux 同步，也可以手工 `kubectl apply -k`。

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

- **自包含**：只引用本目录内的文件，不需要 `--load-restrictor LoadRestrictionsNone`，可直接 `apply -k`，Argo CD / Flux 默认配置即可渲染。
- **不使用 hostPath**：不依赖 Docker Desktop 的 `/run/desktop/mnt/host/...` 路径。
  - postgres 不挂载 `config/postgres/initdb`，由 `POSTGRES_DB=ruoyi-vue-pro` 建业务库，表结构需手工导入（见下文）。
  - nacos 不连接 MySQL，使用内置存储（Derby），数据在 `nacos-data` PVC。
- 清单从 `k8s/services/` 复制后修改，两边**分开维护**；改镜像版本、端口时注意同步。
- 依赖集群有默认 StorageClass（kubeadm 集群按 `k8s-single.md` 第六节安装 local-path）。

## 部署

所有 kubectl 命令都显式指定上下文，不要用默认上下文（可能指向线上集群）。

```bash
K="kubectl --context <集群上下文>"

# 1. Secret yudao-env（不入库）：从 .env 生成；用到的键见下表
$K create namespace yudao --dry-run=client -o yaml | $K apply -f -
$K create secret generic yudao-env --from-env-file=.env -n yudao --dry-run=client -o yaml | $K apply -f -

# 2. 部署（手工方式；用 Argo CD 时跳过，见下文）
$K apply -k gitops-k8s
$K get pods,svc,pvc -n yudao -o wide
```

| 服务 | Secret `yudao-env` 中用到的键 |
|---|---|
| postgres | `POSTGRES_USER`、`POSTGRES_PASSWORD` |
| redis | `REDIS_PASSWORD`（必填） |
| nacos | `NACOS_AUTH_ENABLE`、`NACOS_AUTH_TOKEN`、`NACOS_AUTH_IDENTITY_KEY`、`NACOS_AUTH_IDENTITY_VALUE`（任一为空 Nacos 会直接退出） |
| rabbitmq | `RABBITMQ_USERNAME`、`RABBITMQ_PASSWORD`（只在数据卷首次初始化时生效） |
| minio | `MINIO_ROOT_USER`、`MINIO_ROOT_PASSWORD` |
| nora | `NORA_PUBLIC_URL`、`NORA_MAVEN_PROXIES`、`NORA_NPM_PROXY`、`NORA_DOCKER_PROXIES`（均可选）；不开鉴权，`NORA_AUTH_*` 不读取 |

### PostgreSQL 导入表结构

只需在空库上执行一次（脚本首行是 `\connect "ruoyi-vue-pro"`）：

```bash
$K exec -i -n yudao deploy/postgres -- sh -c 'psql -U "$POSTGRES_USER" -v ON_ERROR_STOP=1' < config/postgres/initdb/02-yudao-schema.sql
$K exec -i -n yudao deploy/postgres -- sh -c 'psql -U "$POSTGRES_USER" -v ON_ERROR_STOP=1' < config/postgres/initdb/03-yudao-quartz.sql
```

### Argo CD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: yudao-env
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitee.com/imshaw/yudao-env.git
    targetRevision: feature/dev
    path: gitops-k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: yudao
  syncPolicy:
    automated: { prune: true, selfHeal: true }
```

Secret 仍需按上文手工创建；`prune` 不会删除不在 Git 中的 Secret。

## 校验

```bash
kubectl kustomize gitops-k8s > /dev/null   # 离线渲染，不连接集群
```

## 注意

- 端口用 `hostPort` 暴露到节点所有网卡，只适合内网开发测试环境。
- NORA 固定不开鉴权（`NORA_AUTH_ENABLED=false`），能访问 4000 端口的人都能推送镜像、上传制品。
- 删除 PVC 会丢失数据；`local-path` 的数据在节点 `/opt/local-path-provisioner`。
