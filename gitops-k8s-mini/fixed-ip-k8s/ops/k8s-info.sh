#!/usr/bin/env bash
# k8s-info.sh —— 集群与网络状态总览
export KUBECONFIG=${KUBECONFIG:-/home/k8s/.kube/config}
LANIP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
echo "================ Kubernetes 状态 ================"
echo "当前局域网 IP : ${LANIP:-未知}"
echo "固定集群身份  : 10.10.10.10 (dummy0, 永不变化)"
echo "kubectl 入口  : https://127.0.0.1:6443"
printf "dummy0        : "; ip -4 -o addr show dummy0 2>/dev/null | awk '{print $4}' || echo "缺失！systemctl start k8s-dummy0"
echo
kubectl get nodes -o wide 2>&1
echo
kubectl get pods -A -o wide 2>&1 | head -20
echo
echo "证书中的 IP   : $(openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text 2>/dev/null | grep -o 'IP Address:[0-9.]*' | sed 's/IP Address://' | paste -sd' ')"
if [ -n "$LANIP" ] && ! openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text 2>/dev/null | grep -q "IP Address:$LANIP"; then
  echo
  echo "注意：当前局域网 IP $LANIP 不在证书 SAN 中。"
  echo "      只用本机 kubectl 的话无需处理；想让局域网其它电脑直连，执行： sudo k8s-allow-ip.sh"
fi
