#!/usr/bin/env python3
"""在 Windows 开发机上通过 SSH 执行命令 / 上传文件（免装 sshpass）。

依赖：pip install paramiko

用法：
  set SSH_HOST=192.168.1.102 & set SSH_USER=k8s & set SSH_PASS=xxx
  python ssh-run.py -- "kubectl get nodes"              # 执行命令
  python ssh-run.py --put setup "fixed-ip-k8s/setup" -- "ls ~/setup"   # 上传后执行

环境变量（也可用同名命令行参数覆盖）：
  SSH_HOST  主机地址
  SSH_PORT  端口，默认 22
  SSH_USER  用户名
  SSH_PASS  密码
"""
import argparse
import os
import sys
import time

import paramiko


def connect():
    host = os.environ.get("SSH_HOST", "")
    user = os.environ.get("SSH_USER", "")
    pwd = os.environ.get("SSH_PASS", "")
    port = int(os.environ.get("SSH_PORT", "22"))
    if not (host and user):
        sys.exit("请先设置 SSH_HOST / SSH_USER / SSH_PASS 环境变量")
    cli = paramiko.SSHClient()
    cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    cli.connect(host, port, user, pwd, timeout=15,
                look_for_keys=False, allow_agent=False, banner_timeout=20)
    cli.get_transport().set_keepalive(15)
    return cli


def run(cli, cmd, timeout):
    chan = cli.get_transport().open_session()
    chan.settimeout(timeout)
    chan.get_pty(width=200, height=50)
    chan.exec_command('export LANG=C LC_ALL=C; ' + cmd)
    buf = b""
    while True:
        if chan.recv_ready():
            buf += chan.recv(65536)
        elif chan.exit_status_ready():
            while chan.recv_ready():
                buf += chan.recv(65536)
            break
        else:
            time.sleep(0.05)
    sys.stdout.write(buf.decode("utf-8", "replace"))
    sys.stdout.flush()
    return chan.recv_exit_status()


def put_dir(cli, local, remote):
    sftp = cli.open_sftp()

    def abspath(p):
        # 相对路径按登录用户的 home 解析，避免误建到 / 下
        return p if p.startswith("/") else sftp.normalize(".").rstrip("/") + "/" + p

    def mkdirs(path):
        path = abspath(path)
        cur = ""
        for p in path.strip("/").split("/"):
            cur += "/" + p
            try:
                sftp.stat(cur)
            except IOError:
                sftp.mkdir(cur)

    if os.path.isdir(local):
        mkdirs(remote)
        root_remote = abspath(remote)
        for root, _, files in os.walk(local):
            rel = os.path.relpath(root, local)
            dst = root_remote if rel == "." else root_remote + "/" + rel.replace(os.sep, "/")
            mkdirs(dst)
            for f in files:
                sftp.put(os.path.join(root, f), dst + "/" + f)
    else:
        sftp.put(local, abspath(remote))
    sftp.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--put", nargs=2, metavar=("LOCAL", "REMOTE"))
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("cmd", nargs="*")
    a = ap.parse_args()

    cli = connect()
    try:
        if a.put:
            put_dir(cli, a.put[0], a.put[1])
            print(f"[上传] {a.put[0]} -> {a.put[1]}")
        if a.cmd:
            cmd = " ".join(a.cmd)
            sys.exit(run(cli, cmd, a.timeout))
    finally:
        cli.close()


if __name__ == "__main__":
    main()
