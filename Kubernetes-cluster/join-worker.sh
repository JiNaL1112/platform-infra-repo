#!/usr/bin/env bash
#
# join-worker.sh
# Run this ONLY on a worker node, AFTER common-node-setup.sh.
#
# Usage:
#   sudo ./join-worker.sh <control-plane-host>:<port> --token <token> \
#        --discovery-token-ca-cert-hash sha256:<hash>
#
# Get the exact join command by running this on the control-plane:
#   kubeadm token create --print-join-command
#
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: sudo $0 <control-plane-host>:<port> --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
  echo ""
  echo "Get this exact command by running on the control-plane:"
  echo "  kubeadm token create --print-join-command"
  exit 1
fi

echo "=== Resetting any previous kubeadm state (safe if none exists) ==="
kubeadm reset -f || true
rm -rf /etc/cni/net.d
systemctl restart containerd

echo "=== Joining the cluster ==="
kubeadm join "$@"

echo ""
echo "=== Done ==="
echo "Verify from the control-plane with: kubectl get nodes"