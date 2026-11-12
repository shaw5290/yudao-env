# Docker 环境安装（Ubuntu 24.04）

在一台 Ubuntu 24.04 服务器上安装 Docker Engine + Docker Compose 插件，然后用本仓库的 `compose/` 拉起 yudao 依赖环境。

> Windows 本地开发直接安装 Docker Desktop（WSL2 后端）即可，不需要看本文，见根目录 `README.md`。

## 适用范围

| 项目 | 要求 |
|---|---|
| 系统 | Ubuntu 24.04 LTS（noble），x86_64 / arm64 |
| 配置 | 核心服务（MySQL + Redis）最低 2C4G；中间件全开（ELK、LGTM、Nacos 等）建议 8C16G 以上 |
| 磁盘 | 系统盘之外建议单独挂数据盘，作为 Docker 数据目录（见下文 `data-root`） |
| 账号 | 有 sudo 权限的普通账号（不直接用 root） |
| 网络 | 能访问 Docker 官方源或国内镜像源 |

以下命令用有 sudo 权限的普通账号执行，需要 root 权限的命令都已加 `sudo`；不要 `sudo -i` 切到 root 后再执行，否则 `$USER`、`$HOME` 会变成 root 的。

## 1. 卸载旧版本

系统自带的 `docker.io`、`podman-docker` 等包与 Docker 官方包冲突，先卸载（没装过会提示未安装，忽略即可）：

```bash
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  sudo apt-get remove -y $pkg
done
```

## 2. 安装 Docker Engine

软件源地址二选一。国内服务器：

```bash
DOCKER_MIRROR=https://mirrors.aliyun.com/docker-ce
```

海外服务器：

```bash
DOCKER_MIRROR=https://download.docker.com
```

确认变量（输出为空说明没赋值或换了终端，重新执行上面一行；SSH 重连后也要重新赋值）：

```bash
echo $DOCKER_MIRROR
```

安装：

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL $DOCKER_MIRROR/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
$DOCKER_MIRROR/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## 3. 配置 Docker

写 `/etc/docker/daemon.json`（`data-root` 指向的目录不存在时 Docker 会自动创建）：

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "data-root": "/data/docker",
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "registry-mirrors": []
}
EOF
```

| 配置 | 说明 |
|---|---|
| `data-root` | 镜像、容器、命名卷的存放目录，默认 `/var/lib/docker`；有数据盘时指向数据盘。**装好后再改要先迁移数据** |
| `exec-opts` | cgroup 驱动用 systemd，与 kubelet 保持一致（同一台机器以后要加入 K8s 时不用再改） |
| `log-opts` | 限制容器日志大小，避免 `docker logs` 撑满磁盘 |
| `registry-mirrors` | Docker Hub 镜像加速地址。**国内服务器基本访问不了 Docker Hub，必须配置**，否则拉镜像（包括下面的 `hello-world`）会超时。填自己可用的加速器（如阿里云容器镜像服务分配的专属地址）；也可以填本仓库 NORA 的 Docker 代理地址 |

使用 NORA（`--profile nora`）作为 HTTP 私有仓库时，还需要加 `"insecure-registries": ["<NORA 主机 IP>:4000"]`。

## 4. 启动并设置开机自启

apt 安装后 Docker 已经自动启动，改了 `daemon.json` 要重启才生效：

```bash
sudo systemctl enable docker
sudo systemctl restart docker
systemctl status docker --no-pager
```

把当前账号加入 `docker` 组，之后执行 docker 命令不用再加 sudo（**退出 SSH 重新登录后生效**；`docker` 组等同 root 权限，只给可信账号）：

```bash
sudo usermod -aG docker $USER
exit        # 退出后重新 SSH 登录
```

## 5. 验证

重新登录后执行（不加 sudo 能执行，说明 docker 组已生效）：

```bash
id | grep docker
docker version
docker compose version
docker info | grep -E "Docker Root Dir|Cgroup Driver"
docker run --rm hello-world
```

`Docker Root Dir` 应为 `daemon.json` 中的 `data-root`，`Cgroup Driver` 应为 `systemd`。

## 6. 部署 yudao-env

```bash
git clone https://gitee.com/imshaw/yudao-env.git
cd yudao-env

# 复制环境变量模板并修改口令（.env 不提交）
cp .env.temp .env
vi .env

# 多服务菜单（核心服务 / 全部中间件 / 备份还原）
chmod +x compose/yudao.sh compose/services/*.sh
./compose/yudao.sh

# 也可以单独启停某个服务，例如 MySQL
./compose/services/mysql.sh up
```

服务器部署时注意：

- `.env` 中必须修改的口令见根目录 `README.md`；`compose/yudao.sh` 开头的 `DB_PASSWORD` 要与 `MYSQL_ROOT_PASSWORD` 一致，否则备份还原失败。
- `ROCKETMQ_BROKER_IP`、`SEATA_IP` 填服务器内网 IP，不能写 `127.0.0.1`。
- 所有端口都映射到宿主机所有网卡，**不要直接暴露到公网**，见下一节。

## 7. 防火墙

本地部署不启用防火墙（最小化安装的 Ubuntu 没有 ufw，先安装，保持关闭）：

```bash
sudo apt install -y ufw
sudo ufw disable
sudo ufw status        # Status: inactive
```

不开防火墙时服务器**只能放在内网**。要暴露到公网时，用云厂商安全组只放行必要端口并限制来源 IP；注意 Docker 发布的端口通过 iptables 的 `DOCKER` 链转发，**会绕过 ufw 的规则**，靠 ufw 限制不住。

## 常见问题

### `docker compose` 提示不是 docker 命令

原因：只装了 docker-ce，没装 `docker-compose-plugin`，或者用的是旧版独立的 `docker-compose`（v1）。
解决：安装 `docker-compose-plugin`，使用 `docker compose`（中间是空格）。

### 拉取镜像超时

原因：服务器无法访问 Docker Hub / ghcr.io / docker.elastic.co。
解决：配置 `registry-mirrors`（只对 Docker Hub 生效），其他仓库的镜像通过 NORA 代理或提前在能联网的机器上 `docker save` / `docker load`。

### 改了 `data-root` 之后原来的容器和数据卷不见了

原因：Docker 只读取新目录。
解决：`sudo systemctl stop docker` 后把旧目录整体复制过去（`sudo rsync -aP /var/lib/docker/ /data/docker/`），再 `sudo systemctl start docker`。

### 普通用户执行 docker 提示 `permission denied ... docker.sock`

原因：账号不在 `docker` 组，或加入后没有重新登录。
解决：`sudo usermod -aG docker $USER` 后退出 SSH 重新登录，或在当前终端执行 `newgrp docker`。
