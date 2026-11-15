#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
registry-delete.py —— NORA Docker 镜像手动删除工具（Registry v2 API）

背景：NORA Web UI 是只读的（浏览/搜索/复制 pull 命令，无删除按钮）；
docker 的删除走 Registry v2 标准协议：DELETE /v2/<repo>/manifests/<digest>（返回 202 即成功）。
maven2 协议无 DELETE（405），maven 制品删除见 ops/README 或用 nora retention/gc。

用法：
  python registry-delete.py --list                     # 列出全部仓库与 tags
  python registry-delete.py --list <repo>              # 列出某仓库 tags
  python registry-delete.py --delete <repo> <tag>      # 删除某仓库的某 tag
  python registry-delete.py --keep <repo> <N>          # 每仓库保留最新 N 个（latest 除外），删其余

环境变量：
  NORA_REGISTRY  默认 http://192.168.1.102:4000（换路由器后改这里或用 --host）
"""
import argparse
import json
import subprocess
import sys

DEFAULT_REGISTRY = "http://192.168.1.102:4000"
ACCEPT = ("application/vnd.docker.distribution.manifest.v2+json,"
          "application/vnd.oci.image.manifest.v1+json,"
          "application/vnd.docker.distribution.manifest.list.v2+json,"
          "application/vnd.oci.image.index.v1+json")


def curl(*args):
    p = subprocess.run(["curl", "-s", "--noproxy", "*", "--max-time", "20"] + list(args),
                       capture_output=True, text=True, timeout=30)
    return p.stdout.strip()


def token(reg, repo):
    out = curl(f"{reg}/v2/token?service=harbor&scope=repository:{repo}:pull,delete")
    try:
        return json.loads(out).get("token", "")
    except Exception:
        return ""


def list_tags(reg, repo):
    out = curl(f"{reg}/v2/{repo}/tags/list")
    return json.loads(out).get("tags") or []


def delete_tag(reg, repo, tag, tok=None):
    tok = tok or token(reg, repo)
    dg = curl("-I", "-H", "Authorization: Bearer " + tok, "-H", "Accept: " + ACCEPT,
              f"{reg}/v2/{repo}/manifests/{tag}")
    dgl = [l.split(":", 1)[1].strip() for l in dg.splitlines()
           if l.lower().startswith("docker-content-digest:")]
    if not dgl:
        print(f"FAIL {repo}:{tag} -> 未取到 digest（tag 不存在？）")
        return False
    code = curl("-o", "/dev/null", "-w", "%{http_code}", "-X", "DELETE",
                "-H", "Authorization: Bearer " + tok, f"{reg}/v2/{repo}/manifests/{dgl[0]}")
    ok = code in ("202", "200")
    print(("DEL " if ok else "FAIL ") + f"{repo}:{tag} -> {code}")
    return ok


def main():
    ap = argparse.ArgumentParser(description="NORA docker 镜像手动删除工具")
    ap.add_argument("--host", default=None, help="NORA 地址，默认 %s" % DEFAULT_REGISTRY)
    ap.add_argument("--list", nargs="?", const="*", metavar="REPO", help="列出全部或某仓库 tags")
    ap.add_argument("--delete", nargs=2, metavar=("REPO", "TAG"), help="删除某仓库某 tag")
    ap.add_argument("--keep", nargs=2, metavar=("REPO_PREFIX", "N"),
                    help="REPO_PREFIX 下每仓库保留最新 N 个 tag（latest 除外），删其余")
    args = ap.parse_args()

    import os
    reg = args.host or os.environ.get("NORA_REGISTRY", DEFAULT_REGISTRY).rstrip("/")
    if not reg.startswith("http"):
        reg = "http://" + reg

    if args.list:
        if args.list == "*":
            cat = json.loads(curl(f"{reg}/v2/_catalog?n=500")).get("repositories") or []
            for r in cat:
                tags = list_tags(reg, r)
                print(f"{r}: {tags}")
        else:
            print(f"{args.list}: {list_tags(reg, args.list)}")
    elif args.delete:
        ok = delete_tag(reg, args.delete[0], args.delete[1])
        sys.exit(0 if ok else 1)
    elif args.keep:
        prefix, n = args.keep[0], int(args.keep[1])
        cat = json.loads(curl(f"{reg}/v2/_catalog?n=500")).get("repositories") or []
        for r in [x for x in cat if x.startswith(prefix)]:
            tags = list_tags(reg, r)
            protected = {"latest"}
            ranked = sorted(t for t in tags if t not in protected)  # tag 前缀 时间戳-SHA，字典序≈时间序
            victims = ranked[:-n] if len(ranked) > n else []
            print(f"{r}: keep {ranked[-n:]}, delete {victims}" if victims else f"{r}: {len(ranked)} 个非 latest tag，无需删除")
            for t in victims:
                delete_tag(reg, r, t, token(reg, r))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
