#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update -qq
sudo apt-get install -y ca-certificates curl gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -qq
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

curl -fsSLo /tmp/kubectl https://dl.k8s.io/release/v1.35.1/bin/linux/amd64/kubectl
sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl

curl -fsSLo /tmp/kind https://kind.sigs.k8s.io/dl/v0.31.0/kind-linux-amd64
sudo install -m 0755 /tmp/kind /usr/local/bin/kind

sg docker -c "kind create cluster --config k8s/kind-config.yaml"
kubectl config use-context kind-skillpulse

kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.9/manifests/install.yaml

kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8080,"nodePort":30088}]}}'

kubectl apply -f k8s/argocd-app.yaml

echo "✅ Done!"
echo ""
echo "SkillPulse  → http://<EC2-IP>:8888"
echo "Argo CD UI  → https://<EC2-IP>:30088"
echo "Argo CD     → user: admin"
echo -n "             pass: "
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
