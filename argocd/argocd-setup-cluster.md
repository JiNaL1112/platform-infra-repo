1. ArgoCD
bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  -n argocd \
  --create-namespace \
  -f argocd/argocd-values.yaml

Wait for pods:

bash
kubectl get pods -n argocd -w

Then:

bash
kubectl apply -f argocd/argocd-referencegrant.yaml
kubectl apply -f argocd/argocd-httproute.yaml
kubectl apply -f argocd/argocd-grpcroute.yaml