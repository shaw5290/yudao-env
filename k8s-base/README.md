# k8s-base：GitOps 的基础环境

自建 kubeadm 单机集群（`k8s-master`，Ubuntu 24.04，k8s v1.36.2）上的 Git 服务、镜像仓库和 Flux 控制器。**只放基础环境，不放应用**；应用清单在 `../../yudao-gitops`。

集群地址是 `fixed-ip-k8s` 那套方案做的：控制面固定绑 `10.10.10.10`（dummy0），局域网 IP 由路由器 DHCP 分配、换场地就变。

| 服务 | 镜像 | 用途 | 访问 | 存储 |
|---|---|---|---|---|
| postgresql | `postgres:16-alpine` | Gitea 的数据库（库名 `gitea`） | `postgresql.yudao-local.svc.cluster.local:5432`、宿主机 5432 | `postgresql-data` 5Gi |
| gitea | `gitea/gitea:28.3.0` | Git 仓库、Actions 触发源 | `http://<节点IP>:3000/`、`gitea.yudao-local.svc.cluster.local:3000` | `gitea-data` 5Gi |
| registry | `registry:2` | CI 推送镜像、Flux 扫描 Tag | **`10.10.10.10:5000`**（HTTP） | `registry-data` 10Gi |
| flux（6 个控制器） | `ghcr.io/fluxcd/*` | source / kustomize / helm / notification / image-reflector / image-automation | 命名空间 `flux-system` | 无 |

```text
yudao-ui-admin-vben ──Gitea Actions（act_runner）──▶ docker build ──▶ registry 10.10.10.10:5000
                                                                          │
                                      image-reflector 扫到新 Tag ──────────┘
                                                  │
yudao-gitops ──git push──▶ Gitea（yudao/yudao-gitops）
                              │ source-controller 每分钟拉取
                              ▼
                     kustomize-controller ──▶ apply apps/local（命名空间 yudao-local）
```

## 为什么镜像地址写 `10.10.10.10:5000`

镜像名里带仓库地址，这个地址一变，GitOps 仓库里所有清单都得跟着改，还会让已部署的 Pod 拉不到新镜像。所以仓库绑在 dummy0 的固定地址上，不跟 DHCP 走：

- 节点上的 containerd 通过 `/etc/containerd/certs.d/10.10.10.10:5000/hosts.toml` 放行 HTTP（`bootstrap/containerd-registry.sh` 生成）
- Pod 内访问 `10.10.10.10:5000` 走节点的 hostPort，已实测可达
- 局域网其他电脑也能用 `http://<节点IP>:5000`，只是镜像名里不写它

## 部署

以下命令都在**服务器**上执行，kubectl 默认上下文即可（`~/.kube/config` 指向 `https://127.0.0.1:6443`）。

### 1. 目录与 .env

```bash
sudo mkdir -p /opt/yudao
# 把本目录放到 /opt/yudao/k8s-base（本仓库里的 .env 不入库，单独上传）
cp .env.temp .env
```

`.env` 当前值由 `../../gitops-k8s-mini/env_local` 转换而来，改了三处：新增 `POSTGRES_DB=gitea`、`GITEA__server__ROOT_URL` 换成当前局域网 IP、Gitea 段解除注释。变量含义：

| 变量 | 说明 |
|---|---|
| `POSTGRES_DB` | Gitea 的库名，空库首次初始化时创建；之后改动要进库改或删 PVC 重来 |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | 数据库账号，Gitea 复用同一组值 |
| `GITEA__server__ROOT_URL` | 页面链接、HTTP 克隆地址、Actions 回调都按它生成，**换网必须改** |
| `GITEA__security__SECRET_KEY` | 2FA、Actions 密钥等，设置后不要再改 |

### 2. 创建 Secret 并应用清单

```bash
cd /opt/yudao/k8s-base
bash ops/apply-env.sh     # 建命名空间 + Secret yudao-env（含 CHANGE_ME 校验）
kubectl apply -k .
kubectl -n yudao-local get pods -w
```

### 3. 放行 HTTP 镜像仓库（只在节点执行一次）

```bash
bash bootstrap/containerd-registry.sh
```

### 4. 初始化 Gitea

```bash
bash ops/gitea-bootstrap.sh
```

做四件事：建管理员 `devops`、生成 Flux 令牌（写 `.gitea-token`，权限 600）、建组织 `yudao`、建仓库 `yudao-gitops` 与 `yudao-ui-admin-vben`。建组织/仓库用的是临时 `all` 权限令牌，用完立即删除，Flux 拿到的只是 `write:repository`。

### 5. 安装 Flux

```bash
# 服务器访问不到 github.com，CLI 通过 gh-proxy 下载
V=$(curl -s https://api.github.com/repos/fluxcd/flux2/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')
curl -sL -o /tmp/flux.tgz "https://gh-proxy.com/https://github.com/fluxcd/flux2/releases/download/v${V}/flux_${V}_linux_amd64.tar.gz"
sudo install -m 755 <(tar xzOf /tmp/flux.tgz flux) /usr/local/bin/flux

flux install --components-extra=image-reflector-controller,image-automation-controller
```

### 6. Flux 连 Gitea

```bash
kubectl -n flux-system create secret generic gitea-auth \
  --from-literal=username=devops \
  --from-literal=password="$(cat .gitea-token)"

kubectl apply -f ../../yudao-gitops/clusters/local/gitrepository.yaml
flux get sources git -A
```

`gitrepository.yaml` 里的地址是 `http://gitea.yudao-local.svc.cluster.local:3000/yudao/yudao-gitops.git`，走 Service 域名，与局域网 IP 无关。

## 换网 / 换场地

| 步骤 | 命令 | 说明 |
|---|---|---|
| 1 | 什么都不用做 | `k8s-dummy0` 开机先建好 `10.10.10.10`，集群、Gitea、registry、Flux 全部不依赖局域网 IP |
| 2 | `bash ops/gitea-root-url.sh` | 把 ROOT_URL 改成当前局域网 IP 并重启 Gitea；只在需要从浏览器访问时才必须 |
| 3 | `sudo k8s-info.sh` | fixed-ip-k8s 装的运维脚本，一屏看 IP、dummy0、节点、Pod、证书 SAN |

Flux 拉代码、Runner 推镜像都不受影响：前者用 Service 域名，后者用 `10.10.10.10:5000`。

## 常用命令

```bash
kubectl -n yudao-local get pods,svc,pvc          # 基础环境
flux get sources git -A                          # Flux 能否拉到 Gitea
flux get kustomizations -A                       # Flux 同步状态
kubectl -n yudao-local logs deploy/gitea --tail=50
curl -s http://10.10.10.10:5000/v2/_catalog      # 仓库里有哪些镜像
```

## 已验证（2026-11-14）

| 项 | 结果 |
|---|---|
| 三个 Pod | `postgresql`、`gitea`、`registry` 全部 `Running`，PVC 均 `Bound` |
| Gitea | `/api/healthz` 200；管理员 `devops` 可登录；组织 `yudao` + 两个仓库已建 |
| registry | `http://10.10.10.10:5000/v2/` 200；Pod 内 wget 同样返回 `{}` |
| containerd | `certs.d/10.10.10.10:5000/hosts.toml` 已生效，HTTP 仓库可拉取 |
| Flux | 6 个控制器 `Running`；`GitRepository yudao-gitops` = `Ready=True`，revision `feature/dev@sha1:fd823c2` |

## 下一步（还没做）

1. **Runner**：Gitea Actions 的 runner 是 `gitea/act_runner`，不是 GitHub 的 ARC（Actions Runner Controller）。ARC 只对接 GitHub/GHES，无法向 Gitea 注册；act_runner 需要在 Pod 里带 dind 才能 `docker build`。
2. **工作流**：`yudao-ui-admin-vben/.gitea/workflows/build-antdv-next.yml` 已存在，但里面的 `REGISTRY` 仍是旧地址 `192.168.31.66:4000`，要改成 `10.10.10.10:5000`；工作流里也不能用市场 Action（本机访问不到 github.com）。
3. **应用清单**：`yudao-gitops/apps/base/admin-vben/admin-vben.yaml` 的镜像地址同样是旧 ACR/NORA 地址，要统一成 `10.10.10.10:5000/yudao/admin-vben-antdv-next`；`clusters/local` 的 Kustomization 还没 apply，因此应用尚未部署。
4. **仓库内容**：`yudao-gitops` 已推到 `feature/dev`，`yudao-ui-admin-vben` 仓库还是空的，需要把前端源码推上去供 Actions 检出。

## 与 gitops-k8s-mini 的分工

`gitops-k8s-mini` 是「Gitee + ACR」的方案，Gitea 在那边是停用状态；本目录换成「集群内 Gitea + 集群内 registry」，两者不要同时部署：`5432`、`3000` 会冲突（本目录占用 5432、3000、5000）。
