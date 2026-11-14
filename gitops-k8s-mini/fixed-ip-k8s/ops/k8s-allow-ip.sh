#!/usr/bin/env bash
# k8s-allow-ip.sh —— 把指定 IP（缺省为当前局域网 IP）加入 apiserver 证书 SAN
# 用途：换路由器后想用「局域网 IP:6443」直连集群时执行一次，可重复执行
set -uo pipefail
CFG=/root/kubeadm-config.yaml
IP="${1:-}"
export KUBECONFIG=${KUBECONFIG:-/home/k8s/.kube/config}

if [ "$(id -u)" -ne 0 ]; then echo "请用 sudo 运行"; exit 1; fi
if ! command -v kubectl >/dev/null 2>&1; then
  PATH=$PATH:/usr/bin; export PATH
fi
if [ -z "$IP" ]; then
  IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
fi
if ! echo "$IP" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  echo "无法确定有效 IP，请手动指定：sudo k8s-allow-ip.sh 192.168.1.102"; exit 1
fi
echo "目标 IP: $IP"

if openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text 2>/dev/null | grep -q "IP Address:$IP"; then
  echo "证书里已包含 $IP，无需处理"
  exit 0
fi

# 1) 更新本地 kubeadm 配置
cp "$CFG" "$CFG.bak.$(date +%s)"
python3 - "$CFG" "$IP" <<'PY'
import sys
cfg, ip = sys.argv[1], sys.argv[2]
lines = open(cfg).read().splitlines()
if any(l.strip() == f"- {ip}" for l in lines):
    sys.exit(0)
for i, l in enumerate(lines):
    if l.strip() == "certSANs:":
        lines.insert(i + 1, f"    - {ip}")
        break
else:
    for i, l in enumerate(lines):
        if l.strip() == "apiServer: {}":
            lines[i:i+1] = ["apiServer:", "  certSANs:", f"    - {ip}"]
            break
    else:
        print("配置文件中找不到 apiServer 段，请人工检查")
        sys.exit(2)
open(cfg, "w").write("\n".join(lines) + "\n")
PY
[ $? -ne 0 ] && exit 1

# 2) 同步集群里的 kubeadm-config ConfigMap（保证以后 kubeadm upgrade 不会丢）
TMP=$(mktemp)
kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' > "$TMP" 2>/dev/null
if [ -s "$TMP" ]; then
  python3 - "$TMP" "$IP" <<'PY'
import sys
p, ip = sys.argv[1], sys.argv[2]
lines = open(p).read().splitlines()
if any(l.strip() == f"- {ip}" for l in lines):
    sys.exit(0)
for i, l in enumerate(lines):
    if l.strip() == "certSANs:":
        lines.insert(i + 1, f"  - {ip}")
        break
else:
    for i, l in enumerate(lines):
        if l.strip() == "apiServer: {}":
            lines[i:i+1] = ["apiServer:", "  certSANs:", f"  - {ip}"]
            break
open(p, "w").write("\n".join(lines) + "\n")
PY
  kubectl -n kube-system create cm kubeadm-config --from-file=ClusterConfiguration="$TMP" \
    --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - >/dev/null 2>&1 \
    && echo "已同步 kubeadm-config ConfigMap" || echo "警告：ConfigMap 同步失败（不影响证书）"
fi
rm -f "$TMP"

# 3) 强制重签 apiserver 证书
OUT=$(kubeadm certs renew apiserver 2>&1)
if ! openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text 2>/dev/null | grep -q "IP Address:$IP"; then
  echo "certs renew 未生效，改用 init phase 重签"
  mv -f /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.crt.pre-$(date +%s)
  mv -f /etc/kubernetes/pki/apiserver.key /etc/kubernetes/pki/apiserver.key.pre-$(date +%s)
  kubeadm init phase certs apiserver --config "$CFG" >/dev/null 2>&1
fi

if openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text 2>/dev/null | grep -q "IP Address:$IP"; then
  echo "证书已重新签发："
  openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -A1 'Subject Alternative Name' | tail -1
  echo
  echo "apiserver 会在 1 分钟内自动加载新证书（也可 systemctl restart kubelet 立即生效）。"
  echo "局域网其它电脑用法：把 ~/.kube/config 里 server 改成 https://$IP:6443 后拷贝过去即可。"
else
  echo "失败：证书未包含 $IP"; echo "$OUT" | tail -5; exit 1
fi
