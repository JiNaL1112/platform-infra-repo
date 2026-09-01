3. SonarQube
bash
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm repo update

helm install sonarqube sonarqube/sonarqube \
  -n sonarqube \
  --create-namespace \
  -f sonarqube/sonarqube-value.yaml

Wait for pods (SonarQube is slow to start):

bash
kubectl get pods -n sonarqube -w

Then apply routing — but first double check the actual service name Helm created:

bash
kubectl get svc -n sonarqube

Your sonarqube-httproute.yaml targets sonarqube-sonarqube — confirm that matches before applying:

bash
kubectl apply -f sonarqube/sonarqube-referencegrant.yaml
kubectl apply -f sonarqube/sonarqube-httproute.yaml



# To add storageclass as local storage in sonarqube 
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml