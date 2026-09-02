1. Add the repo

bash
helm repo add metallb https://metallb.github.io/metallb
helm repo update

2. Values file

Created a file, ran a command, read a file

3. Install with Helm

bash
helm install metallb metallb/metallb \
  -n metallb-system \
  --create-namespace \
  -f metallb-values.yaml

4. Wait for it to be ready

bash
kubectl get pods -n metallb-system -w

5. Apply the IPAddressPool + L2Advertisement

This part is important to understand: IPAddressPool and L2Advertisement are custom resources (CRDs), not Helm values — they can't go inside metallb-values.yaml. MetalLB's Helm chart only manages the controller/speaker deployment, not the address configuration. So you still apply the manifest I gave you earlier separately, after the Helm install:

bash
kubectl apply -f metallb-ipaddresspool.yaml

6. Verify

bash
kubectl get svc -n nginx-gateway
kubectl get gateway -A

Why it's split this way: this mirrors exactly what you're already doing with Gatekeeper (helm install gatekeeper + separate ConstraintTemplate/Constraint YAMLs) and ArgoCD (Helm chart + separate Application/AppProject CRDs). Helm manages the workload (controller/speaker pods, RBAC, webhooks); the CRDs that configure behavior are applied as plain manifests on top — that's the standard pattern for every Kubernetes operator, not just MetalLB.

If you want to upgrade later (e.g. change resource limits):

bash
helm upgrade metallb metallb/metallb -n metallb-system -f metallb-values.yaml