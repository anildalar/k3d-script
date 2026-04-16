#!/bin/bash
set -e

echo "🚀 Starting full automated setup (No Helm)..."

export DEBIAN_FRONTEND=noninteractive

# -------------------------------
# 1. System Update
# -------------------------------
apt-get update -y
apt-get upgrade -y

# -------------------------------
# 2. Dependencies
# -------------------------------
apt-get install -y ca-certificates curl gnupg lsb-release

# -------------------------------
# 3. Docker Install
# -------------------------------
apt-get remove -y docker docker-engine docker.io containerd runc || true

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
> /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

# -------------------------------
# 4. Install k3d
# -------------------------------
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# -------------------------------
# 5. Install kubectl
# -------------------------------
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

# -------------------------------
# 6. Create k3d cluster
# -------------------------------
if ! k3d cluster list | grep -q prod; then
  k3d cluster create prod \
    -s 1 -a 1 \
    --k3s-arg "--disable=traefik@server:0" \
    -p "80:80@loadbalancer" \
    -p "443:443@loadbalancer"
fi

# Wait for nodes
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# Namespace
kubectl create ns prod --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace=prod

# -------------------------------
# 7. Install NGINX Ingress (NO HELM)
# -------------------------------
echo "🌐 Installing NGINX Ingress Controller..."

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

# Wait for ingress controller
kubectl wait --namespace ingress-nginx \
  --for=condition=available deployment \
  ingress-nginx-controller \
  --timeout=180s

# -------------------------------
# 8. Install Cert-Manager (NO HELM)
# -------------------------------
echo "🔐 Installing Cert-Manager..."

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# Wait for cert-manager
kubectl wait --namespace cert-manager \
  --for=condition=available deployment \
  --all --timeout=180s

echo "✅ Verifying setup..."

kubectl get nodes
kubectl get pods -A
kubectl get svc -A

echo "🎉 DONE: Cluster + Ingress + Cert-Manager Ready!"
