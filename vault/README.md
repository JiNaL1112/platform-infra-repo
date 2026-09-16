# Vault on Kubernetes

3-node Vault HA cluster, integrated Raft storage, deployed via the official
HashiCorp Helm chart onto a 2-node kubeadm cluster (1 control-plane + 1 worker).

Related files:
- `values.yaml` — Helm values used for this deployment
- `policies/secret-readwrite.hcl` — scoped policy for the `secret/` KV mount
- `../cluster-config/taints.md` — why the control-plane taint was removed
- `../cluster-config/kubelet-config-patch.yaml` — kubelet TLS fix required for `kubectl exec` to work against Vault pods
- `../manifests/kubelet-serving-cert-approver.yaml` — automates CSR approval from the above fix

## Prerequisites this deployment depends on

Before installing Vault, the cluster needed two changes (see linked files above):
1. Control-plane taint removed (2 nodes, 3 replicas needs both schedulable)
2. `serverTLSBootstrap: true` set cluster-wide so `kubectl exec`/`logs` work against pods on both nodes

## Install

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

kubectl create namespace vault

helm install vault hashicorp/vault --namespace vault -f values.yaml
```

To apply future changes to `values.yaml`:
```bash
helm upgrade vault hashicorp/vault -n vault -f values.yaml
```

> ⚠️ `helm upgrade` only updates the StatefulSet's pod template. Already-running
> pods keep their old spec until recreated. If a values change doesn't seem to
> take effect, compare revisions and delete any pod stuck on the old one:
> ```bash
> kubectl get pods -n vault -o custom-columns=NAME:.metadata.name,REVISION:.metadata.labels.controller-revision-hash
> kubectl delete pod <pod-name> -n vault
> ```

## Initialize (run once, only on vault-0)

```bash
kubectl exec -n vault -it vault-0 -- vault operator init
```

Save the 5 Unseal Keys and Initial Root Token somewhere secure (password
manager). **Do not commit these to git, even encrypted, unless you know what
you're doing with `sops`/`git-secret`.**

## Unseal and join the raft cluster

```bash
# vault-0
kubectl exec -n vault -it vault-0 -- vault operator unseal   # x3, different key each time

# vault-1
kubectl exec -n vault -it vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault -it vault-1 -- vault operator unseal   # x3

# vault-2
kubectl exec -n vault -it vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault -it vault-2 -- vault operator unseal   # x3
```

## Verify cluster health

```bash
kubectl get pods -n vault
kubectl exec -n vault -it vault-0 -- vault status
```

Check raft peers (requires auth first):
```bash
kubectl exec -n vault -it vault-0 -- sh -c 'VAULT_TOKEN=<root-token> vault operator raft list-peers'
```

## Access the UI

```bash
kubectl get svc -n vault vault-ui
```
Browse to `http://<any-node-ip>:<nodeport>` and log in with the root token
(or a scoped token once an auth method is set up).

## Enable secrets engine and apply policy

```bash
vault secrets enable -path=secret kv-v2
vault policy write secret-readwrite policies/secret-readwrite.hcl
```

## Restarts / node reboots

Vault pods restart **sealed** — raft data persists (PVC), but the in-memory
unseal state does not. After any pod restart you must re-run
`vault operator unseal` (3 of 5 keys) on that pod before it rejoins serving
traffic. See "Suggested next steps" below for removing this manual step.

## Suggested next steps

- Rotate the root token and unseal keys generated during initial setup
- Set up a real auth method (userpass to start) instead of using the root token day-to-day
- Set up auto-unseal (cloud KMS or Transit engine) to remove the manual unseal step on restart
- Test failover: `kubectl delete pod vault-0 -n vault` and confirm raft elects a new leader among `vault-1`/`vault-2`