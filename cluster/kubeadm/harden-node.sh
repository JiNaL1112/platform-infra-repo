#!/bin/bash
# scripts/harden-node.sh
chmod 600 /lib/systemd/system/kubelet.service
chmod 600 /var/lib/kubelet/config.yaml
chmod 600 /etc/kubernetes/kubelet.conf 2>/dev/null
chmod 600 ~/.kube/config 2>/dev/null