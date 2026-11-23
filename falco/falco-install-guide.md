Falco's official Helm chart is published at `falcosecurity.github.io/charts`. Here's the standard install. It assumes a recent Kubernetes version (1.25+), Helm 3, and a kernel that supports the modern eBPF driver (5.8+ with BTF), which is the chart's default on most distros.

**1. Add the repo**

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
```

**2. Create the namespace (and allow privileged pods)**

Falco runs as a privileged DaemonSet. If your cluster enforces Pod Security Admission, the namespace needs the `privileged` level:

```bash
kubectl create namespace falco
kubectl label namespace falco pod-security.kubernetes.io/enforce=privileged
```

**3. Install**

```bash
helm install falco falcosecurity/falco \
  --namespace falco \
  --set tty=true
```

`tty=true` makes Falco flush logs immediately, so you see events right away.

For a more reproducible setup, put your settings in a values file and pin the chart version:

```yaml
# values.yaml
tty: true
driver:
  kind: modern_ebpf # alternatives: ebpf, kmod
falco:
  json_output: true
  json_include_output_property: true
# Optional: forward alerts to Slack, etc. via Falcosidekick
falcosidekick:
  enabled: true
  webui:
    enabled: true
```

```bash
helm install falco falcosecurity/falco \
  --namespace falco \
  --version <chart-version> \
  -f values.yaml
```

Find available versions with `helm search repo falcosecurity/falco --versions`.

**4. Verify**

```bash
kubectl get pods -n falco -o wide        # one pod per node
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco
```

**5. Trigger a test alert**

```bash
kubectl run test --image=alpine --restart=Never -- sleep 3600
kubectl exec -it test -- sh -c "cat /etc/shadow"
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco | grep -i shadow
```

You should see a "Read sensitive file untrusted" style alert. Clean up with `kubectl delete pod test`.

**Notes**

- **Managed clusters:**
  - Some providers (GKE Autopilot, Fargate) don't allow privileged DaemonSets or kernel access, so Falco won't work there.
  - On GKE Standard, EKS, and AKS with ordinary nodes, it works. If `modern_ebpf` fails, try `driver.kind=ebpf` or `kmod`.
- **Container runtime metadata:** Newer chart versions handle this automatically through the `collectors` settings. If container or pod names show up as `<NA>` in alerts, check `collectors.containerd.socket` (or the CRI-O/Docker equivalent) in the chart values.
- **Upgrade and rollback:**
  ```bash
  helm upgrade falco falcosecurity/falco -n falco -f values.yaml
  helm rollback falco -n falco
  ```
- **Uninstall:** `helm uninstall falco -n falco`
- **Before production:** run `helm template` or `helm install --dry-run` with your values to review the rendered manifests. Chart values change between major versions, so check the chart's README (`helm show values falcosecurity/falco`) against your version.

If you tell me your distribution (EKS, GKE, k3s, etc.) and kernel version, I can suggest the right driver and values, or help set up alert forwarding to Slack or similar.
