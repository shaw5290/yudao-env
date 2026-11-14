#!/usr/bin/env bash
# ================= 05 本地存储 local-path =================
# 作用：装 rancher/local-path-provisioner 并设为默认 StorageClass（PVC 才能自动绑定）
# 用量：bash 05-storage.sh
#       优先用 manifests/local-path-storage.yaml；没有则读 ~/local-path-storage.yaml；再没有才联网下载
set -uo pipefail

LOCAL_PATH_VER="${LOCAL_PATH_VER:-v0.0.32}"
DOCKER_HUB_MIRROR="${DOCKER_HUB_MIRROR:-docker.m.daocloud.io}"
TEST_IMAGE="${TEST_IMAGE:-${DOCKER_HUB_MIRROR}/library/busybox:1.36}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${LOCAL_PATH_YAML:-}" ]; then
  if [ -f "$SCRIPT_DIR/../manifests/local-path-storage.yaml" ]; then
    LOCAL_PATH_YAML="$SCRIPT_DIR/../manifests/local-path-storage.yaml"
  else
    LOCAL_PATH_YAML="$HOME/local-path-storage.yaml"
  fi
fi

info() { echo -e "\n[信息] $*"; }
ok()   { echo "[成功] $*"; }
die()  { echo "[错误] $*" >&2; exit 1; }
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

info "准备 local-path 清单"
if [ ! -f "$LOCAL_PATH_YAML" ]; then
  curl -fsSL -o "$LOCAL_PATH_YAML" \
    "https://raw.githubusercontent.com/rancher/local-path-provisioner/${LOCAL_PATH_VER}/deploy/local-path-storage.yaml" \
    || die "下载失败，请手动把 local-path-storage.yaml 放到 $LOCAL_PATH_YAML"
  sed -i "s#image: rancher/local-path-provisioner#image: ${DOCKER_HUB_MIRROR}/rancher/local-path-provisioner#" "$LOCAL_PATH_YAML"
fi
echo "  清单: $LOCAL_PATH_YAML"

info "安装并设为默认 StorageClass"
kubectl apply -f "$LOCAL_PATH_YAML" 2>&1 | tail -4
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>&1 | tail -1

info "PVC 读写验证（local-path 是 WaitForFirstConsumer，必须有 Pod 消费才会绑定）"
kubectl delete pod verify-pvc-pod --ignore-not-found > /dev/null 2>&1
kubectl delete pvc verify-pvc --ignore-not-found > /dev/null 2>&1
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: verify-pvc
  namespace: default
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: verify-pvc-pod
  namespace: default
spec:
  restartPolicy: Never
  containers:
    - name: verify
      image: ${TEST_IMAGE}
      command: ["sh", "-c", "echo ok > /data/verify.txt && sleep 300"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: verify-pvc
EOF

kubectl wait --for=condition=Ready pod/verify-pvc-pod --timeout=90s \
  || die "验证 Pod 起不来：kubectl describe pod verify-pvc-pod"
kubectl get pvc verify-pvc
echo -n "  写入内容: "; kubectl exec verify-pvc-pod -- cat /data/verify.txt

phase=$(kubectl get pvc verify-pvc -o jsonpath='{.status.phase}')
if [ "$phase" = "Bound" ]; then
  ok "存储可用（PVC $phase）"
else
  die "PVC 状态 $phase，检查 kubectl -n local-path-storage logs -l app=local-path-provisioner"
fi

info "清理验证资源"
kubectl delete pod verify-pvc-pod --ignore-not-found > /dev/null 2>&1
kubectl delete pvc verify-pvc --ignore-not-found > /dev/null 2>&1
kubectl get sc
ok "完成，接下来执行 06-verify.sh"
