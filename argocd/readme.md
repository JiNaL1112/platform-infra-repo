# ArgoCD on Minikube with NGINX Gateway API

A complete guide to installing ArgoCD on Minikube using Helm, with external access via NGINX Gateway API (HTTPRoute) instead of Ingress.

---

## Architecture

```
Browser → http://argocd.local
              │
              ▼
        127.0.0.1 (minikube tunnel)
              │
              ▼
     nginx-gateway/cluster-gateway (LoadBalancer)
              │
              ▼
     HTTPRoute (argocd.local → argocd-server:80)
              │
              ▼
     argocd-server (ClusterIP) in argocd namespace
```

---

## Prerequisites

Make sure the following are installed and running:

- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- NGINX Gateway Fabric installed on the cluster
- Gateway API CRDs installed

---

## Folder Structure

```
.
├── argocd-values.yaml         # Helm values for ArgoCD
├── argocd-referencegrant.yaml # Allows cross-namespace routing
├── argocd-httproute.yaml      # HTTPRoute for argocd.local
└── README.md
```

---

## Step 1: Start Minikube

```bash
minikube start
```

---

## Step 2: Install Gateway API CRDs

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/latest/download/standard-install.yaml
```

Verify:

```bash
kubectl get crd | grep gateway
```

Expected CRDs:

```
gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
referencegrants.gateway.networking.k8s.io
```

---

## Step 3: Install NGINX Gateway Fabric

```bash
helm install nginx-gateway oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --create-namespace \
  -n nginx-gateway \
  --set service.type=LoadBalancer
```

Verify the Gateway is programmed:

```bash
kubectl get gateway -A
```

Expected output:

```
NAMESPACE       NAME              CLASS   ADDRESS     PROGRAMMED   AGE
nginx-gateway   cluster-gateway   nginx   127.0.0.1   True         ...
```

---

## Step 4: Add ArgoCD Helm Repo

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

---

## Step 5: Install ArgoCD with Values File

```bash
helm install argocd argo/argo-cd \
  -n argocd \
  --create-namespace \
  -f argocd-values.yaml
```

### `argocd-values.yaml`

```yaml
# ============================================
# ArgoCD Helm Values
# ============================================

global:
  domain: argocd.local

server:
  # Disable TLS on ArgoCD server
  # TLS is handled by nginx-gateway
  extraArgs:
    - --insecure

  # Use ClusterIP - external access via HTTPRoute
  service:
    type: ClusterIP
    servicePortHttp: 80
    servicePortHttps: 443
    servicePortHttpName: http
    servicePortHttpsName: https

  # Ingress disabled - using Gateway API HTTPRoute instead
  ingress:
    enabled: false

configs:
  params:
    # Required when running behind a reverse proxy
    server.insecure: true
```

---

## Step 6: Apply ReferenceGrant

Required to allow the `nginx-gateway` namespace to route traffic to the `argocd` namespace.

```bash
kubectl apply -f argocd-referencegrant.yaml
```

### `argocd-referencegrant.yaml`

```yaml
# ============================================
# ReferenceGrant - allows nginx-gateway namespace
# to route traffic to argocd namespace
# ============================================
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: argocd-referencegrant
  namespace: argocd
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: nginx-gateway
  to:
  - group: ""
    kind: Service
    name: argocd-server
```

---

## Step 7: Apply HTTPRoute

```bash
kubectl apply -f argocd-httproute.yaml
```

### `argocd-httproute.yaml`

```yaml
# ============================================
# HTTPRoute - routes argocd.local to argocd-server
# ============================================
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-httproute
  namespace: nginx-gateway
spec:
  parentRefs:
  - name: cluster-gateway
    namespace: nginx-gateway
  hostnames:
  - "argocd.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: argocd-server
      namespace: argocd
      port: 80
```

---

## Step 8: Update Hosts File

### Linux / macOS

```bash
echo "127.0.0.1 argocd.local" | sudo tee -a /etc/hosts
```

### Windows

Open **Notepad as Administrator** and edit:

```
C:\Windows\System32\drivers\etc\hosts
```

Add at the bottom:

```
127.0.0.1   argocd.local
```

---

## Step 9: Start Minikube Tunnel

Run in a **separate terminal** and keep it open:

```bash
minikube tunnel
```

> ⚠️ Closing this terminal will stop external access.

---

## Step 10: Access ArgoCD

Open your browser:

```
http://argocd.local
```

---

## Step 11: Get Admin Password

### Linux / macOS / Git Bash

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### Windows PowerShell

```powershell
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

Login with:

- **Username:** `admin`
- **Password:** output from above

---

## Upgrading ArgoCD

```bash
helm upgrade argocd argo/argo-cd -n argocd -f argocd-values.yaml
```

If you encounter a stuck Helm operation:

```bash
# Fix stuck helm release
kubectl delete secret -n argocd -l status=pending-upgrade

# Then retry upgrade
helm upgrade argocd argo/argo-cd -n argocd -f argocd-values.yaml
```

---

## Verification Commands

```bash
# Check all ArgoCD pods are Running
kubectl get pods -n argocd

# Confirm service is ClusterIP
kubectl get svc argocd-server -n argocd

# Check HTTPRoute is accepted
kubectl get httproute -n nginx-gateway

# Check ReferenceGrant exists
kubectl get referencegrant -n argocd

# Check Gateway is programmed
kubectl get gateway -n nginx-gateway
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `EXTERNAL-IP` is `<pending>` | `minikube tunnel` not running | Run `minikube tunnel` in separate terminal |
| `http://argocd.local` not reachable | Hosts file not updated | Add `127.0.0.1 argocd.local` to hosts file |
| HTTPRoute not accepted | ReferenceGrant missing | Apply `argocd-referencegrant.yaml` |
| Helm upgrade stuck | Previous operation failed | Run `kubectl delete secret -n argocd -l status=pending-upgrade` |
| Port 80/443 conflict | Two LoadBalancer services on same port | Use ClusterIP for ArgoCD, route via Gateway only |
| SSL warning in browser | ArgoCD self-signed cert | Use `--insecure` flag via `server.extraArgs` |

---

## Adding More Apps via HTTPRoute

To expose any future app through the same gateway, just create a new HTTPRoute:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp-httproute
  namespace: nginx-gateway
spec:
  parentRefs:
  - name: cluster-gateway
    namespace: nginx-gateway
  hostnames:
  - "myapp.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: myapp-service
      namespace: myapp
      port: 8080
```

And add to hosts file:

```
127.0.0.1   myapp.local
```

> ✅ Only **one LoadBalancer** (`nginx-gateway`) needed for all apps — clean and production-like!

---

## References

- [ArgoCD Docs](https://argo-cd.readthedocs.io/)
- [ArgoCD Helm Chart](https://github.com/argoproj/argo-helm)
- [NGINX Gateway Fabric](https://docs.nginx.com/nginx-gateway-fabric/)
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [Minikube Docs](https://minikube.sigs.k8s.io/docs/)