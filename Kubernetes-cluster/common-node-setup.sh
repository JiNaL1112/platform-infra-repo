#!/usr/bin/env bash
#
# common-node-setup.sh
# Run this on EVERY node (control-plane AND worker) before kubeadm init/join.
# Tested on Ubuntu 24.04 (noble).
#
# Usage:
#   sudo ./common-node-setup.sh
#
set -euo pipefail

K8S_VERSION="v1.37"   # kubeadm/kubelet/kubectl repo track — must match on every node

echo "=== [1/6] Disabling swap ==="
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

echo "=== [2/6] Loading required kernel modules ==="
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo "=== [3/6] Setting required sysctl params ==="
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

echo "=== [4/6] Installing containerd (via Docker's repo for a current version) ==="
apt-get update
apt-get remove -y containerd containerd.io 2>/dev/null || true
apt-get install -y apt-transport-https ca-certificates curl gpg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y containerd.io

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

echo "=== [5/6] Installing kubeadm, kubelet, kubectl (${K8S_VERSION}) ==="
apt-get install -y apt-transport-https ca-certificates curl gpg
mkdir -p /etc/apt/keyrings

curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" \
  | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y --allow-change-held-packages kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "=== [6/6] Opening required firewall ports (if ufw is active) ==="
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow 6443/tcp        # API server
  ufw allow 2379:2380/tcp   # etcd client API
  ufw allow 10250/tcp       # kubelet API
  ufw allow 10251/tcp       # kube-scheduler
  ufw allow 10252/tcp       # kube-controller-manager
  ufw allow 30000:32767/tcp # NodePort range
  echo "ufw rules added."
else
  echo "ufw not active — skipping firewall rules."
fi

echo ""
echo "=== Done ==="
echo "containerd version: $(containerd --version)"
echo "kubeadm version:    $(kubeadm version -o short 2>/dev/null || kubeadm version)"
echo ""
echo "Next steps:"
echo "  - On the CONTROL-PLANE node, run: ./init-control-plane.sh"
echo "  - On WORKER nodes, run the 'kubeadm join ...' command printed by that script"