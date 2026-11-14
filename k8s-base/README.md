# k8s-base：GitOps 的基础环境

自建 kubeadm 单机集群（`k8s-master`，Ubuntu 24.04，k8s v1.36.2）上的 Git 服务、制品仓库、Actions 执行器和 Flux 控制器。**只放基础环境，不放应用**；应用清单在 `../../yudao-gitops`。

集群地址是 `fixed-ip-k8s` 那套方案做的：控制面固定绑 `10.10.10.10`（dummy0），局域网 IP 由路由器 DHCP 分配、换场地就变。

| 服务 | 镜像 | 用途 | 访问 | 存储 |
| --- | --- | --- | --- | --- |
| postgresql | `postgres:16-alpine` | Gitea 的数据库（库名 `gitea`） | `postgresql.yudao-local.svc.cluster.local:5432`、宿主机 5432 | `postgresql-data` 5Gi |
| gitea | `gitea/gitea:28.3.0` | Git 仓库、Actions 触发源 | `http://<节点IP>:3000/`、`gitea.yudao-local.svc.cluster.local:3000` | `gitea-data` 5Gi |
| nora | `ghcr.io/getnora-io/nora:1.4.4` + `nginx:stable-alpine` | Docker Registry v2 hosted + Maven/npm 代理；CI 推镜像、Flux 扫 Tag | **`10.10.10.10:4000`**（HTTP，nginx sidecar 监听 4000 → NORA 4001） | `nora-data` 20Gi |
| act-runner | `gitea/act_runner` + `docker:dind` | Gitea Actions 执行器（host 模式），同 Pod 内 dind 提供 Docker daemon | 无对外端口 | 注册信息在 `/data/.runner` |
| flux（6 个控制器） | `ghcr.io/fluxcd/*` | source / kustomize / helm / notification / image-reflector / image-automation | 命名空间 `flux-system` | 无 |

> **为什么用 NORA 而不是 `registry:2`**：`gitops-k8s-mini/base/services/nora.yaml` 和 `env_local` 里已有 `NORA_PUBLIC_URL` / `NORA_DOCKER_PROXIES` 的约定，NORA 同时承担 Maven / npm 代理。另起一个 `registry:2` 属于重复建设；`services/registry.yaml` 仅保留备查，已从 `kustomization.yaml` 注释掉。

## GitOps 发布链路（当前方案）

```text
① 开发者 push 到 Gitea yudao/yudao-ui-admin-vben 的 template/base-v2
        │
        ▼
② Gitea Actions（act_runner host 模式 + 同 Pod dind）
   docker buildx build --output "type=image,push=true,registry.insecure=true"
   推送 10.10.10.10:4000/yudao/admin-vben-antdv-next:<14位时间戳>-<sha7> 与 latest
        │   （Actions 只推镜像，不写 GitOps 仓库）
        ▼
③ Flux image-reflector-controller 每分钟扫 NORA 的 Tag
   ImagePolicy admin-vben 按 14 位时间戳取最大（latest 不匹配正则，被过滤）
        │
        ▼
④ ImageUpdateAutomation 把新 Tag 写进 yudao-gitops/apps/local/kustomization.yaml
   并 commit / push 回 template/base-v2 —— GitOps 仓库只有 Flux 一个写入方
        │
        ▼
⑤ source-controller 拉到新提交 → kustomize-controller apply apps/local
        │
        ▼
⑥ Deployment admin-vben 滚动更新（hostPort 80）
```

单写入方是刻意的设计：如果 Actions 也去改 `apps/local`，会和 image-automation 互相覆盖。`clusters/local/image-automation.yaml` 因此必须启用。

## 为什么镜像地址写 `10.10.10.10:4000`

镜像名里带仓库地址，这个地址一变，GitOps 仓库里所有清单都得跟着改，还会让已部署的 Pod 拉不到新镜像。所以仓库绑在 dummy0 的固定地址上，不跟 DHCP 走：

- 节点上的 containerd 通过 `/etc/containerd/certs.d/10.10.10.10:4000/hosts.toml` 放行 HTTP（`bootstrap/containerd-registry.sh` 生成）
- Pod 内访问 `10.10.10.10:4000` 走节点的 hostPort，已实测可达
- 局域网其他电脑用 `http://<节点IP>:4000`，但镜像名里不写它

### NORA 纯 HTTP 的两个坑

1. **新版 docker client 会先试 HTTPS**。NORA 对 TLS ClientHello 不快速拒绝，客户端会一直等而不回退到 HTTP，表现为 `docker push` 卡在 `Head "https://.../manifests/...": timeout awaiting response headers`。
   - 对策 A：前置 nginx sidecar（已部署），让 HTTPS 探测被快速拒绝。
   - 对策 B（工作流采用）：不用 `docker push`，改用 `docker buildx build --output "type=image,push=true,registry.insecure=true"`，由 BuildKit 直接走 HTTP。
   - 多个 Tag 必须用多个 `-t` + **省略 `name` 的** `--output`；把两个 Tag 塞进 `name=a,b` 会被 CSV 解析器当成独立字段，实测报 `ERROR: invalid value <第二个 Tag>`。
2. **NORA 1.4.4 在 manifest HEAD 阶段会查上游**。不配 `NORA_DOCKER_PROXIES` 时回退到 `registry-1.docker.io`，本机超时约 30s，HEAD 返回 502；配上后要避开这个源。
   - 当前值：`NORA_DOCKER_PROXIES=https://docker.m.daocloud.io,https://docker.1panel.live`（能快速返回 403）。基础镜像由 dind 的 `--registry-mirror` 直接拉，不依赖 NORA 代理。
   - 实测：runner 容器内 `docker buildx build` 一次构建同时推 `<时间戳>-<sha7>` 与 `latest`，9.4 秒完成，NORA `/v2/yudao/buildtest/tags/list` 返回两个 Tag。

### act_runner host 模式的坑

`config/act-runner/config.yaml` 的 `host.workdir_parent` **必须写绝对路径 `/data/work`**。写相对路径 `data/work` 时，act 用相对路径写脚本，执行时却把 `cmd.Dir` 切到 job 子目录，第一步就报 `bash: data/work/<id>/act/workflow/0.sh: No such file or directory`，整个 job 秒失败、后续步骤全部 skipped。改绝对路径并 `kubectl apply -k .` 重建 ConfigMap 后，检出 / 生成 Tag / buildx 三步都正常。

排查失败 job 的日志：先查 `action_task.log_filename`（PostgreSQL 的 `gitea` 库），日志是 zstd 压缩，宿主机用 `zstd -dc` 解压；容器里没有 zstd，可用 `kubectl exec ... base64 <file>` 传出来再解。

## 部署

以下命令都在**服务器**上执行，kubectl 默认上下文即可（`~/.kube/config` 指向 `https://127.0.0.1:6443`）。

### 1. 目录与 .env

```bash
sudo mkdir -p /opt/yudao
# 把本目录放到 /opt/yudao/k8s-base（.env 不入库，单独上传）
cp .env.temp .env
```

`.env` 由 `../../gitops-k8s-mini/env_local` 转换而来，只摘取本环境实际用到的 PostgreSQL / Gitea / NORA 变量；`.env.temp` 是脱敏模板。变量含义：

| 变量 | 说明 |
| --- | --- |
| `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` | Gitea 的库与账号，空库首次初始化时创建；之后改动要进库改或删 PVC 重来 |
| `GITEA__server__ROOT_URL` | 页面链接、HTTP 克隆地址、Actions 回调都按它生成，**换网必须改** |
| `GITEA__security__SECRET_KEY` | 2FA、Actions 密钥等，设置后不要再改 |
| `NORA_PUBLIC_URL` | 客户端看到的下载地址，**换网必须和 ROOT_URL 一起改** |
| `NORA_MAVEN_PROXIES` / `NORA_NPM_PROXY` | Maven / npm 上游 |
| `NORA_DOCKER_PROXIES` | Docker 上游，见上方「两个坑」，不要留空也不要放 `registry-1.docker.io` |

`.env` 改完必须重跑 `ops/apply-env.sh` 并重启受影响的工作负载（容器读的是环境变量，不重启不生效）。

### 2. 放行 HTTP 镜像仓库（只在节点执行一次）

```bash
bash bootstrap/containerd-registry.sh     # REGISTRY 默认 10.10.10.10:4000
```

### 3. Secret 与基础环境

```bash
cd /opt/yudao/k8s-base
bash ops/apply-env.sh        # 建命名空间 + Secret yudao-env（含 CHANGE_ME 校验）
kubectl apply -k .           # postgresql / gitea / nora / act-runner
kubectl -n yudao-local rollout status deploy/gitea --timeout=180s
```

> `act-runner` 依赖 Secret `gitea-runner-token`，在第 4 步生成前会处于 Pending，属正常；Secret 建好后 Pod 自动启动。

### 4. 初始化 Gitea 与 Runner

```bash
bash ops/gitea-bootstrap.sh     # 管理员 devops、Flux 令牌、组织 yudao、两个仓库
bash ops/act-runner-token.sh    # 生成 registration token 写入 Secret gitea-runner-token
kubectl -n yudao-local rollout status deploy/act-runner --timeout=180s
```

`gitea-bootstrap.sh` 里的 gitea CLI 必须以 `su git -c` 执行（root 会被拒绝）；建组织/仓库用临时 `all` 权限令牌，用完立即删除，Flux 拿到的只是 `write:repository`。

### 5. 安装 Flux 并连 Gitea

```bash
# 服务器访问不到 github.com，CLI 通过 gh-proxy 下载
V=$(curl -s https://api.github.com/repos/fluxcd/flux2/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')
curl -sL -o /tmp/flux.tgz "https://gh-proxy.com/https://github.com/fluxcd/flux2/releases/download/v${V}/flux_${V}_linux_amd64.tar.gz"
sudo install -m 755 <(tar xzOf /tmp/flux.tgz flux) /usr/local/bin/flux

flux install --components-extra=image-reflector-controller,image-automation-controller

kubectl -n flux-system create secret generic gitea-auth \
  --from-literal=username=devops \
  --from-literal=password="$(cat .gitea-token)"
```

### 6. 启用集群同步与镜像自动更新

```bash
kubectl apply -k ../../yudao-gitops/clusters/local
flux get all -A
```

`clusters/local` 含 `gitrepository.yaml`（拉 `yudao/yudao-gitops` 的 `template/base-v2`）、`apps.yaml`（同步 `apps/local`）、`image-automation.yaml`（扫 NORA Tag 并回写）。地址用 Service 域名 `http://gitea.yudao-local.svc.cluster.local:3000/...`，与局域网 IP 无关。

## 换网 / 换场地

| 步骤 | 命令 | 说明 |
| --- | --- | --- |
| 1 | 什么都不用做 | `k8s-dummy0` 开机先建好 `10.10.10.10`，集群、Gitea、NORA、Flux 全部不依赖局域网 IP |
| 2 | `bash ops/gitea-root-url.sh` | 把 ROOT_URL 改成当前局域网 IP 并重启 Gitea；只在需要从浏览器访问时才必须 |
| 3 | 同步更新 `NORA_PUBLIC_URL` | 改 `/opt/yudao/k8s-base/.env` → `ops/apply-env.sh` → `kubectl -n yudao-local rollout restart deploy/nora` |
| 4 | `sudo k8s-info.sh` | fixed-ip-k8s 装的运维脚本，一屏看 IP、dummy0、节点、Pod、证书 SAN |

Flux 拉代码、Runner 推镜像都不受影响：前者用 Service 域名，后者用 `10.10.10.10:4000`。

## 常用命令

```bash
kubectl -n yudao-local get pods,svc,pvc                       # 基础环境
flux get sources git -A                                       # Flux 能否拉到 Gitea
flux get kustomizations -A                                    # Flux 同步状态
flux get images all -A                                        # 镜像扫描 / 自动更新状态
kubectl -n yudao-local logs deploy/gitea --tail=50
kubectl -n yudao-local logs deploy/act-runner -c runner --tail=50
kubectl -n yudao-local logs deploy/nora -c nora --tail=50
curl -s http://10.10.10.10:4000/health
curl -s http://10.10.10.10:4000/v2/_catalog                   # 仓库里有哪些镜像
curl -s http://10.10.10.10:4000/v2/yudao/admin-vben-antdv-next/tags/list
```

## 已验证（2026-11-14）

| 项 | 结果 |
| --- | --- |
| 节点 | `k8s-master` `Ready`，INTERNAL-IP `10.10.10.10`，containerd 2.4.2 |
| 基础环境 | `postgresql` / `gitea` / `nora`(2/2) / `act-runner`(2/2) 全部 `Running` |
| Gitea | `/api/healthz` 200；管理员 `devops`；组织 `yudao` + 两个仓库已建；Actions `has_actions=true` |
| 仓库推送 | `yudao-gitops` → `template/base-v2@c714981`；`yudao-ui-admin-vben` → `template/base-v2`（5243 提交 / 75 MB）；两个仓库默认分支均为 `template/base-v2` |
| NORA | `/health`、`/v2/` 200；`NORA_DOCKER_PROXIES` 已生效；buildx 双 Tag HTTP 推送 9.4s 成功 |
| act_runner | 已注册；`docker buildx` v0.39.0；`workdir_parent` 改绝对路径后 host 模式正常 |
| containerd | `certs.d/10.10.10.10:4000/hosts.toml` 已生效 |
| Flux | 6 个控制器 `Running`；`GitRepository`(template/base-v2) / `Kustomization apps` / `ImageRepository` / `ImageUpdateAutomation` 均 `Ready=True` |
| Actions | run #1 因 `workdir_parent` 相对路径秒失败；修复后 run #2 三步全 `success`，NORA 出现 `20261114080736-0833ef1` 与 `latest` |
| Flux 自动更新 | `ImagePolicy` 解析出 `20261114080736-0833ef1`；`ImageUpdateAutomation` 自动提交 `9d12be3 chore(apps): 更新 local 镜像 Tag` 回 Gitea |
| 应用发布 | `Kustomization apps` Applied 新 revision；`Deployment admin-vben` 滚动到 `10.10.10.10:4000/yudao/admin-vben-antdv-next:20261114080736-0833ef1`，`1/1` Ready |

## 已跑通的链路（2026-11-14）

push 到 `template/base-v2` → Gitea Actions（act_runner + dind）→ buildx 推 NORA → image-reflector 扫 Tag → image-automation 回写 `apps/local` → kustomize-controller 发布。全链路已实测通过，GitOps 仓库只有 Flux 一个写入方。

## 遗留事项

1. **清理调试镜像**：NORA 的 `yudao/buildtest`，以及早期 `yudao/test` / `test2` tag，可按需删除；不影响 `admin-vben` 的镜像扫描。
2. **本地仓库状态**：前端仓库 HEAD 仍是 `e3c666581`（旧工作流），新版工作流是经 Gitea API 提交的 `0833ef1`，暂存区还留着一份改动；`pnpm-lock.yaml` 有工具链造成的改动，不建议提交。`yudao-gitops` 本地已 rebase 到 Flux 自动提交之上并推送（`9d37693`）。
3. **本机工具链**：Volta 的 pnpm 在 `turbo run typecheck` 下报 `Could not find executable "pnpm"`，本地 `git commit` 会跑约 7 分钟后失败。要恢复本地提交能力，需重装 Volta 的 pnpm 工具链（例如 `volta install pnpm`），不要跳过 lefthook。
4. **换网**：`ops/gitea-root-url.sh` 目前只改 Gitea ROOT_URL，`NORA_PUBLIC_URL` 仍需按「换网 / 换场地」表第 3 步手动同步。

## 与 gitops-k8s-mini 的分工

`gitops-k8s-mini` 是「Gitee + ACR」的方案，Gitea 在那边是停用状态，但它的 `base/services/nora.yaml` 是本环境 NORA 清单的来源。`env_local` 是 `.env` 的变量来源。本目录换成「集群内 Gitea + 集群内 NORA」，两者不要同时部署：本目录占用 5432、3000、4000。
