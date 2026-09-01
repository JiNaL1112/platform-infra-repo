
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/latest/download/experimental-install.yaml





  helm install nginx-gateway oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --version 2.5.1 \
  --create-namespace \
  -n nginx-gateway \
  -f networking/gateway/ngf-values.yaml


  helm install nginx-gateway oci://ghcr.io/nginx/charts/nginx-gateway-fabric --create-namespace -n nginx-gateway -f networking/gateway/ngf-values.yaml