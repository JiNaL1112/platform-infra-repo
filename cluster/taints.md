# Node Taints

## Change made

Removed the default control-plane taint so it could also schedule workloads:

```bash
kubectl taint nodes jinal-hp-prodesk-600-g3-sff node-role.kubernetes.io/control-plane:NoSchedule-
```

## Why

Cluster has only 2 nodes:
- `jinal-hp-prodesk-600-g3-sff` (control-plane)
- `jinal-hp-laptop-15g-br1xx` (worker)

Vault's Helm chart deploys 3 replicas in HA mode. With the control-plane
taint in place, only 1 node (the worker) was schedulable — combined with
Vault's default hard pod anti-affinity (see `vault/values.yaml`), this left
`vault-1`/`vault-2` permanently `Pending`:

```
0/2 nodes are available: 1 node(s) didn't match pod anti-affinity rules,
1 node(s) had untolerated taint(s)
```

Removing the taint unblocked scheduling onto the control-plane node.

## Trade-off accepted

Control-plane node now shares CPU/memory with workloads. Not recommended
for a real production cluster (isolate control-plane from general workloads
there), but reasonable for a 2-node home lab.

## To re-apply the taint later (e.g. after adding a 3rd node)

```bash
kubectl taint nodes jinal-hp-prodesk-600-g3-sff node-role.kubernetes.io/control-plane:NoSchedule
```

## Verify current state on the live cluster

```bash
kubectl describe node jinal-hp-prodesk-600-g3-sff | grep -A5 Taints
kubectl describe node jinal-hp-laptop-15g-br1xx | grep -A5 Taints
```

⚠️ This removal does **not** persist automatically. Re-running `kubeadm init`
on this node, or joining a brand-new control-plane node later, re-applies the
default taint — check and re-remove if you rebuild the control-plane.