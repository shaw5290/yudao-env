# gitops-k8s 服务地址与账号

本目录部署的 7 个服务的访问地址、端口、账号和查看口令的方法。部署步骤见 [README.md](README.md)。

- `192.168.31.66` 为 K8s 节点 IP（当前单机集群），端口用 `hostPort` 暴露在节点所有网卡上，改端口见 `services/<服务>.yaml`。
- 集群内访问：同一命名空间 `yudao` 的 Pod 直接用 Service 名（如 `postgres:5432`），其他命名空间用 `<服务>.yudao.svc.cluster.local`。
- **口令不写在本文档中**（本文档会提交），按下文「查看口令」从服务器上的 Secret `yudao-env` 读取；本机对应的是 `gitops-k8s/.env`（不提交）。

## 服务一览

链接按当前节点 IP `192.168.31.66` 填写，IP 变化时整体替换。

| 服务 | 用途 | 节点端口（外部访问） | 集群内地址 | Web 控制台 | 官方文档 |
|---|---|---|---|---|---|
| PostgreSQL | 业务主库 `ruoyi-vue-pro` | `5432` | `postgres:5432` | 无 | [https://www.postgresql.org/docs/16/](https://www.postgresql.org/docs/16/) |
| Redis | 缓存 | `6379` | `redis:6379` | 无 | [https://redis.io/docs/latest/](https://redis.io/docs/latest/) |
| Nacos | 注册 / 配置中心 | `8848`（HTTP API）、`9848`、`9849`（gRPC，客户端自动使用 8848 + 1000 / 1001） | `nacos:8848` | [http://192.168.31.66:8080](http://192.168.31.66:8080) | [https://nacos.io/docs/v3.0/what-is-nacos/](https://nacos.io/docs/v3.0/what-is-nacos/) |
| RabbitMQ | 消息队列 | `5672`（AMQP）、`15672`（管理） | `rabbitmq:5672` | [http://192.168.31.66:15672](http://192.168.31.66:15672) | [https://www.rabbitmq.com/docs](https://www.rabbitmq.com/docs) |
| MinIO | 对象存储（S3 兼容） | `9000`（S3 API）、`9001`（控制台） | `minio:9000` | [http://192.168.31.66:9001](http://192.168.31.66:9001) | [https://min.io/docs/minio/linux/index.html](https://min.io/docs/minio/linux/index.html) |
| Grafana LGTM | 日志 / 链路 / 指标 | `3000`（Grafana）、`4317`（OTLP gRPC）、`4318`（OTLP HTTP） | `lgtm:4317`、`lgtm:4318` | [http://192.168.31.66:3000](http://192.168.31.66:3000) | [https://github.com/grafana/docker-otel-lgtm](https://github.com/grafana/docker-otel-lgtm) |
| NORA | 制品仓库（Docker / Maven / npm 代理缓存） | `4000` | `nora:4000` | [http://192.168.31.66:4000/ui/](http://192.168.31.66:4000/ui/) | [https://github.com/getnora-io/nora](https://github.com/getnora-io/nora) |

## 账号与连接参数

| 服务 | 账号 | 口令（Secret 键） | 连接示例 / 说明 |
|---|---|---|---|
| PostgreSQL | `POSTGRES_USER`（模板默认 `postgres`） | `POSTGRES_PASSWORD` | `jdbc:postgresql://192.168.31.66:5432/ruoyi-vue-pro`；库名固定 `ruoyi-vue-pro` |
| Redis | 无（只有密码） | `REDIS_PASSWORD`（为空表示不设密码） | `redis://192.168.31.66:6379`，database 默认 0 |
| Nacos | 鉴权关闭时无需登录（`NACOS_AUTH_ENABLE=false`） | 开启鉴权后为控制台首次设置的 `nacos` 用户口令 | 服务地址 `192.168.31.66:8848`（控制台见上表）；内置存储（Derby），命名空间、配置需在控制台自行创建 |
| RabbitMQ | `RABBITMQ_DEFAULT_USER`（模板默认 `guest`） | `RABBITMQ_DEFAULT_PASS` | `amqp://<账号>:<口令>@192.168.31.66:5672/`，vhost `/`；账号只在数据卷首次初始化时生效 |
| MinIO | `MINIO_ROOT_USER`（模板默认 `minioadmin`） | `MINIO_ROOT_PASSWORD`（至少 8 位） | S3 endpoint [http://192.168.31.66:9000](http://192.168.31.66:9000)，access key / secret key 即账号 / 口令；bucket 需在控制台创建 |
| Grafana LGTM | 镜像默认 `admin`（以实际登录页为准） | 镜像默认 `admin`，首次登录后修改 | OTLP 上报：gRPC `http://192.168.31.66:4317`、HTTP [http://192.168.31.66:4318](http://192.168.31.66:4318) |
| NORA | 无（不开鉴权，任何人可读写） | — | Docker `192.168.31.66:4000`（HTTP，客户端需配置 insecure registry）、Maven [http://192.168.31.66:4000/maven2/](http://192.168.31.66:4000/maven2/)、npm [http://192.168.31.66:4000/npm/](http://192.168.31.66:4000/npm/) |

## 查看口令

在服务器上执行，键名见上表（`base64decode` 由 kubectl 完成，不用管道）：

```bash
kubectl --context kubernetes-admin@kubernetes -n yudao get secret yudao-env -o go-template='{{.data.POSTGRES_PASSWORD | base64decode}}{{"\n"}}'
```

一次列出所有键和值（会把口令打印到终端，注意场合）：

```bash
kubectl --context kubernetes-admin@kubernetes -n yudao get secret yudao-env -o go-template='{{range $k, $v := .data}}{{$k}}={{$v | base64decode}}{{"\n"}}{{end}}'
```

只看有哪些键、不显示值：

```bash
kubectl --context kubernetes-admin@kubernetes -n yudao describe secret yudao-env
```

## 检查服务是否可用

```bash
kubectl --context kubernetes-admin@kubernetes -n yudao get pods,svc -o wide
kubectl --context kubernetes-admin@kubernetes -n yudao exec deploy/postgres -- pg_isready
kubectl --context kubernetes-admin@kubernetes -n yudao exec deploy/redis -- redis-cli ping
kubectl --context kubernetes-admin@kubernetes -n yudao exec deploy/rabbitmq -- rabbitmq-diagnostics -q ping
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.31.66:8080/
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.31.66:9000/minio/health/live
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.31.66:3000/api/health
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.31.66:4000/health
```

成功标准：Pod 都是 `Running 1/1`；`pg_isready` 输出 `accepting connections`；`redis-cli ping` 输出 `PONG`（设了密码时报 `NOAUTH` 也说明服务在线）；rabbitmq 无报错；`curl` 返回 `200`（Nacos 控制台可能返回 `302` 跳转，也算正常）。

## 后端 yudao-cloud 对接

后端从本机改连服务器时，把各中间件地址从 `127.0.0.1` 换成 `192.168.31.66`，账号口令与 Secret 一致。注意与本机 compose 环境的差异：

- Nacos 是全新的内置存储实例，本机 Nacos（MySQL 存储）里的命名空间和配置不会同步过来。
- PostgreSQL 表结构需按 README 第 5 步导入一次。
- MinIO 口令至少 8 位，与本机 `.env` 不同时以服务器 Secret 为准。
