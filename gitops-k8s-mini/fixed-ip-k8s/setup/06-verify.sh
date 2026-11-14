#!/usr/bin/env bash
# ================= 06 端到端连通性验证 =================
# 作用：起一个 busybox 测试 Pod，检查 DNS(cluster.local)、Service 直连、apiserver 可达、外网出口。
# 幂等：可随时执行，结束时清理测试 Pod。
set -uo pipefail

DOCKER_HUB_MIRROR="${DOCKER_HUB_MIRROR:-docker.m.daocloud.io}"
TEST_IMAGE="${TEST_IMAGE:-${DOCKER_HUB_MIRROR}/library/busybox:1.36}"

info() { echo -e "\n[信息] $*"; }
ok()   { echo "[成功] $*"; }
warn() { echo "[注意] $*"; }
die()  { echo "[错误] $*" >&2; exit 1; }
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

info "节点状态"
kubectl get nodes -o wide

info "启动测试 Pod（$TEST_IMAGE）"
kubectl delete pod nettest --ignore-not-found > /dev/null 2>&1
kubectl run nettest --image="$TEST_IMAGE" --restart=Never --command -- sleep 600 > /dev/null
kubectl wait --for=condition=Ready pod/nettest --timeout=90s || die "测试 Pod 起不来，先看 kubectl describe pod nettest"
kubectl get pod nettest -o wide

info "1) DNS：解析 cluster.local"
kubectl exec nettest -- nslookup kubernetes.default.svc.cluster.local 2>&1 | tail -5

info "2) Service：ClusterIP 10.96.0.1:443 与固定地址 10.10.10.10:6443 的 TCP 可达性"
kubectl exec nettest -- sh -c 'nc -z -w3 10.96.0.1 443; echo "  10.96.0.1:443   exit=$?"; nc -z -w3 10.10.10.10 6443; echo "  10.10.10.10:6443 exit=$?"'

info "3) 外网：DNS + HTTP"
kubectl exec nettest -- nslookup www.aliyun.com 2>&1 | tail -3
kubectl exec nettest -- sh -c 'wget -q -T 8 -O /dev/null http://www.aliyun.com && echo "  外网 HTTP 正常" || echo "  外网 HTTP 失败"'

info "4) Pod 网络参数"
kubectl exec nettest -- sh -c 'ip -4 -o addr show eth0 | awk "{print \"  Pod IP: \"\$4}"; ip route | sed "s/^/  /"'

info "5) 控制面组件健康"
kubectl -n kube-system get pods -l component=kube-apiserver -o wide 2>/dev/null
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide 2>/dev/null

info "清理"
kubectl delete pod nettest --ignore-not-found > /dev/null 2>&1
warn "注：busybox 的 wget 自带老 TLS 栈，直接 wget https 会报 alert 47，这属正常；上面第 2 步用 nc 测 TCP 已足够"
ok "验证完成"
