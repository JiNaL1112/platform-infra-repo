#!/usr/bin/env bash
#
# init-control-plane.sh
# Run this ONLY on the control-plane node, AFTER common-node-setup.sh.
#
# Usage:
#   sudo ./init-control-plane.sh
#
set -euo pipefail

POD_NETWORK_CIDR="192.168.0.0/16"   # matches Calico's default IP pool
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

echo "=== [1/5] Initializing the control plane ==="
kubeadm init --pod-network-cidr="${POD_NETWORK_CIDR}"

echo "=== [2/5] Setting up kubectl for user '${REAL_USER}' ==="
mkdir -p "${REAL_HOME}/.kube"
cp -i /etc/kubernetes/admin.conf "${REAL_HOME}/.kube/config"
chown "$(id -u "$REAL_USER")":"$(id -g "$REAL_USER")" "${REAL_HOME}/.kube/config"

# Also make kubectl usable as root in this session
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "=== [3/5] Installing Helm (if not already installed) ==="
if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm version

echo "=== [4/5] Installing Calico via Helm ==="
helm repo add projectcalico https://projectcalico.docs.tigera.io/charts
helm repo update

# CRDs must be installed before the operator chart (Calico v3.32+)
helm template calico-crds projectcalico/crd.projectcalico.org.v1 | kubectl apply --server-side -f -

kubectl create namespace tigera-operator --dry-run=client -o yaml | kubectl apply -f -

helm install calico projectcalico/tigera-operator \
  --namespace tigera-operator \
  --set installation.cni.type=Calico

echo "=== [5/5] Waiting for Calico to become ready ==="
kubectl -n tigera-operator wait --for=condition=Ready pod -l k8s-app=tigera-operator --timeout=180s || true
echo "Waiting for calico-node pods (this can take a couple of minutes)..."
sleep 15
kubectl get pods -n calico-system

echo ""
echo "=== Control plane ready ==="
kubectl get nodes
echo ""
echo "=== Save this join command — run it on each worker node ==="
kubeadm token create --print-join-command