Here's the standard Helm-based Istio install, split into the three charts (base, istiod, gateway) with values files. It works the same on-prem as anywhere else, with a few on-prem-specific notes at the end.

## 1. Add the repo and create the namespace

```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

kubectl create namespace istio-system
```

## 2. Install the base chart (CRDs and cluster-wide resources)

```bash
helm install istio-base istio/base \
  -n istio-system \
  --set defaultRevision=default
```

## 3. Install istiod with a values file

Create `istiod-values.yaml`:

```yaml
pilot:
  autoscaleEnabled: true
  autoscaleMin: 2
  autoscaleMax: 5
  resources:
    requests:
      cpu: 500m
      memory: 2Gi
    limits:
      memory: 4Gi

meshConfig:
  accessLogFile: /dev/stdout
  enableTracing: false
  defaultConfig:
    holdApplicationUntilProxyStarts: true
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY   # use ALLOW_ANY if you want open egress

global:
  logAsJson: true
  proxy:
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        memory: 512Mi

# If you use a private/internal registry (common on-prem), uncomment:
# global:
#   hub: registry.mycompany.local/istio
#   tag: 1.24.0
#   imagePullSecrets:
#     - my-registry-secret
```

Install:

```bash
helm install istiod istio/istiod \
  -n istio-system \
  -f istiod-values.yaml \
  --wait
```

## 4. Install the ingress gateway with a values file

Gateways should go in their own namespace, not `istio-system`.

```bash
kubectl create namespace istio-ingress
kubectl label namespace istio-ingress istio-injection=enabled
```

Create `gateway-values.yaml`:

```yaml
service:
  type: NodePort          # or LoadBalancer if you run MetalLB / kube-vip
  ports:
    - name: status-port
      port: 15021
      targetPort: 15021
    - name: http2
      port: 80
      targetPort: 80
      nodePort: 30080
    - name: https
      port: 443
      targetPort: 443
      nodePort: 30443

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    memory: 512Mi
```

Install:

```bash
helm install istio-ingress istio/gateway \
  -n istio-ingress \
  -f gateway-values.yaml \
  --wait
```

## 5. Verify

```bash
helm ls -A
kubectl get pods -n istio-system
kubectl get pods -n istio-ingress
kubectl get svc -n istio-ingress
```

Enable sidecar injection for your app namespaces:

```bash
kubectl label namespace <app-ns> istio-injection=enabled
```

## On-prem notes

- **LoadBalancer service:** without a cloud provider, `type: LoadBalancer` will sit in `<pending>`. Use MetalLB or kube-vip, or stick with NodePort and put your own external LB (HAProxy, F5, etc.) in front.
- **Air-gapped / private registry:** mirror the `istio/pilot` and `istio/proxyv2` images, then set `global.hub`, `global.tag` and `imagePullSecrets` as shown above. For an offline install, pull the charts with `helm pull istio/istiod --version X` and install from the local `.tgz`.
- **Pin versions:** use `--version 1.24.0` (or whatever you've validated) on every `helm install` so the three charts stay in sync.
- **Admission webhook:** istiod needs to be reachable from the API server on port 15017. On-prem firewalls or custom CNI setups sometimes block this, which causes injection failures.
- **Upgrades:** upgrade in order: base, then istiod, then gateways, using `helm upgrade -f <values>`.

## GitOps option

If you're managing this via Argo CD, each of the three charts maps cleanly to its own Application, with the values files living in Git. Use sync waves (base → istiod → gateway) so ordering is respected.

If you tell me your setup (CNI, how you expose services, whether the cluster is air-gapped, and whether you want ambient mode instead of sidecars), I can tailor the values files more precisely.




## 1. `base`: cluster-wide resources and CRDs

This chart installs things that are **cluster-scoped** and shared by everything else:

- Istio CRDs (VirtualService, DestinationRule, Gateway, PeerAuthentication, etc.)
- Cluster roles and role bindings
- Validation webhook configuration

These change rarely and must exist before anything else can work. Keeping them separate also matters for **revision-based (canary) upgrades**. You can run two versions of istiod side by side (e.g., `1.23` and `1.24`), and both share the same single `base` install. If CRDs were bundled into istiod, you couldn't run two istiods without them fighting over ownership of the same cluster-wide objects.

## 2. `istiod`: the control plane

This is the actual brain: it pushes config to the Envoy sidecars, issues certificates for mTLS, and handles sidecar injection. It is a normal namespaced Deployment, and it's the part you upgrade most often. Separating it from `base` means you can upgrade, roll back, or run multiple revisions of the control plane without touching CRDs.

## 3. `gateway`: the data plane entry point

The ingress gateway is just an Envoy proxy Deployment plus a Service. It's separate because:

- **Different lifecycle:** you may want to upgrade gateways independently of the control plane, or run several (public, internal, per-team).
- **Different namespace and security boundary:** gateways are exposed to outside traffic, so they belong in their own namespace (`istio-ingress`) with tighter RBAC, not in `istio-system` next to the control plane.
- **Different scaling:** gateways scale with traffic, while istiod scales with mesh size.
- **Optional:** if you only need service-to-service mesh traffic with no ingress, you can skip it entirely.

## Why not one big chart?

Istio used to ship a single monolithic chart, and it caused real problems: CRDs couldn't be upgraded safely with Helm, canary upgrades were awkward, and gateways were tied to control plane releases. Splitting them follows the principle that **things with different lifecycles and blast radius get different releases**.

## Summary

|Chart|Scope|Changes how often|Namespace|
|---|---|---|---|
|`base`|Cluster-wide (CRDs, RBAC)|Rarely|`istio-system`|
|`istiod`|Control plane|Each Istio upgrade|`istio-system`|
|`gateway`|Data plane ingress|Independently, as needed|`istio-ingress`|

