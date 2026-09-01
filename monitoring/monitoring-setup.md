helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prom-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  -f monitoring/prometheus-grafana-value.yaml

Wait for pods:

bash
kubectl get pods -n monitoring -w

Then:

bash
kubectl apply -f monitoring/monitoring-referencegrant.yaml
kubectl apply -f monitoring/grafana-httproute.yaml
kubectl apply -f monitoring/prometheus-httproute.yaml