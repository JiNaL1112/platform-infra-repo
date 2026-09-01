# Installing Calico via Helm on a kubeadm Cluster

This documents how Calico was installed on our 2-node kubeadm cluster
(1 control-plane + 1 worker) using the official Tigera Operator Helm chart.

## Cluster context

- Kubernetes v1.37.0 (both nodes)
- containerd v2.x (both nodes)
- Pod network CIDR: `192.168.0.0/16` (set at `kubeadm init` time)
- Calico was originally installed via raw manifest (`calico.yaml`), then
  switched to the Helm-based install described below.

## Step 1 — Remove the old manifest-based Calico install

If Calico was previously installed via `kubectl apply -f calico.yaml`,
remove it first to avoid conflicting resources:

```bash
kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
```

## Step 2 — Install Helm (if not already installed)

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

## Step 3 — Add the Calico Helm repo

> **Note:** The URL in the official docs (`https://docs.tigera.io/calico/charts`)
> returned a `502 Bad Gateway` for us. The working alternate URL was:

```bash
helm repo add projectcalico https://projectcalico.docs.tigera.io/charts
helm repo update
```

## Step 4 — Install the CRDs (required for Calico v3.32+)

As of Calico v3.32, the chart's CRDs were split into a separate chart.
Installing the operator chart directly without this step fails with
errors like:

```
resource mapping not found for name: "default" ... no matches for kind "Installation" in version "operator.tigera.io/v1"
ensure CRDs are installed first
```

Fix — install the CRDs first:

```bash
helm template calico-crds projectcalico/crd.projectcalico.org.v1 | kubectl apply --server-side -f -
```

## Step 5 — Create the namespace and install the operator chart

```bash
kubectl create namespace tigera-operator

helm install calico projectcalico/tigera-operator \
  --namespace tigera-operator \
  --set installation.cni.type=Calico
```

This installs:
- The **Tigera Operator** (`tigera-operator` namespace) — manages Calico's lifecycle
- **Calico itself** (`calico-system` namespace) — `calico-node`, `calico-typha`,
  `calico-kube-controllers`, `calico-apiserver`, `goldmane`, `whisker`, etc.

## Step 6 — Watch the rollout

```bash
kubectl get pods -n tigera-operator -w
kubectl get pods -n calico-system -o wide
```

Expect the `calico-node` pod on each node to briefly show `Init:x/3` while
its init containers (`flexvol-driver`, `ebpf-bootstrap`, `install-cni`) pull
images and run, followed by the main container's **startup probe**
(checks BIRD/Felix readiness) taking anywhere from a few seconds up to
several minutes on a slow image pull. This is normal — the startup probe
allows up to 5 minutes (`failureThreshold=150`, `period=2s`) before it's
considered a real failure.

## Step 7 — Verify nodes go Ready

```bash
kubectl get nodes
```

Both nodes should transition to `Ready` once every `calico-node` pod
reaches `1/1 Running`.

## Step 8 — Smoke test

Deploy a throwaway pod to confirm scheduling + pod networking works
end-to-end:

```bash
kubectl run test-nginx --image=nginx
kubectl get pods -o wide   # confirm it gets a pod IP in the 192.168.x.x range
kubectl delete pod test-nginx
```

## Final result

```
NAME                          STATUS   ROLES           VERSION
jinal-hp-laptop-15g-br1xx     Ready    <none>          v1.37.0
jinal-hp-prodesk-600-g3-sff   Ready    control-plane   v1.37.0
```

All Calico pods (`calico-node`, `calico-typha`, `calico-kube-controllers`,
`calico-apiserver`, `goldmane`, `whisker`) running `1/1` or `2/2` in the
`calico-system` namespace.

## Troubleshooting notes / gotchas hit along the way

- **`docs.tigera.io` Helm repo URL 502'd** — used `projectcalico.docs.tigera.io/charts` instead.
- **"Chart.yaml file is missing"** — happens if `helm install calico .` is run
  from a directory that isn't an actual chart (e.g. your home directory).
  Install straight from the repo (`projectcalico/tigera-operator`) instead
  of trying to reference a local path.
- **"ensure CRDs are installed first"** — Calico v3.32+ requires installing
  the `crd.projectcalico.org.v1` chart before the `tigera-operator` chart.
- **Node stuck `NotReady` after Calico install** — check
  `kubectl describe pod -n calico-system <calico-node-pod>`; a startup
  probe still converging (BIRD/Felix not ready yet) is normal for the
  first minute or two after image pulls finish.