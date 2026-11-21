# ==================== OrcaSlicer 切片服务 ====================
# OrcaSlicer 命令行 + HTTP 包装（server.py）：上传模型和预设 → 切片 → 返回耗材重量、打印时间、打印参数，并可下载 G-code
# 构建：docker compose -f compose/services/orca-slicer.yaml --env-file .env --profile orca-slicer build
# 说明见同目录 README.md
# 基础镜像（Docker Hub 访问不了时改为镜像站地址，如 docker.1panel.live/library/ubuntu:24.04）
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

# apt 源（选填），如 http://mirrors.aliyun.com/ubuntu
ARG APT_MIRROR=

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ORCA_HOME=/opt/orca-slicer

RUN if [ -n "$APT_MIRROR" ]; then sed -i "s#http://archive.ubuntu.com/ubuntu#$APT_MIRROR#g; s#http://security.ubuntu.com/ubuntu#$APT_MIRROR#g" /etc/apt/sources.list.d/ubuntu.sources; fi \
    && apt-get -o Acquire::Retries=5 update \
    && apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
        ca-certificates curl python3 xvfb xauth \
        libgtk-3-0t64 libwebkit2gtk-4.1-0 libgl1 libegl1 libglu1-mesa libosmesa6 libgl1-mesa-dri \
        libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 libsecret-1-0 libnotify4 libsoup-3.0-0 \
    && rm -rf /var/lib/apt/lists/*

# OrcaSlicer 版本放在系统依赖之后：升级版本时只重新下载 OrcaSlicer，不重装系统依赖
ARG ORCA_VERSION=2.5.1
# 下载地址可改为镜像站（GitHub 访问慢时）
ARG ORCA_URL=https://github.com/OrcaSlicer/OrcaSlicer/releases/download/v${ORCA_VERSION}/OrcaSlicer_Linux_AppImage_Ubuntu2404_V${ORCA_VERSION}.AppImage
ENV ORCA_VERSION=${ORCA_VERSION}

# AppImage 解包后直接运行，容器内不需要 FUSE
RUN curl -fL --retry 3 -o /tmp/orca.AppImage "$ORCA_URL" \
    && chmod +x /tmp/orca.AppImage \
    && cd /tmp && ./orca.AppImage --appimage-extract > /dev/null \
    && mv /tmp/squashfs-root "$ORCA_HOME" \
    && rm -f /tmp/orca.AppImage

# 预设 JSON：OrcaSlicer 2.5 起安装包中的预设打包为 .opc（自定义压缩格式），切片服务需要读 JSON 展开继承，
# 从同版本的源码包中只解压 resources/profiles 下的 JSON（约 66MB）；命令行切片仍使用安装包自带的预设
ARG ORCA_PROFILES_URL=https://codeload.github.com/OrcaSlicer/OrcaSlicer/tar.gz/refs/tags/v${ORCA_VERSION}
RUN mkdir -p /tmp/orca-src \
    && curl -fL --retry 3 "$ORCA_PROFILES_URL" | tar -xz -C /tmp/orca-src --wildcards "*/resources/profiles/*.json" \
    && mv /tmp/orca-src/*/resources/profiles /opt/orca-profiles \
    && rm -rf /tmp/orca-src
ENV ORCA_PROFILES_DIR=/opt/orca-profiles

COPY server.py preview.py /app/

# 自定义预设（从 OrcaSlicer 导出的机型 / 工艺 / 耗材 JSON）挂载到这里，按子目录 machine / process / filament 存放
VOLUME ["/presets"]
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s CMD curl -fs http://localhost:8080/health || exit 1
CMD ["python3", "/app/server.py"]
