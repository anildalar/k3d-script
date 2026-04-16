#!/bin/bash
set -e  # Exit on error

echo "🚀 Starting full automated setup..."

# Avoid interactive prompts
export DEBIAN_FRONTEND=noninteractive

# -------------------------------
# 1. System Update
# -------------------------------
echo "📦 Updating system..."
apt-get update -y
apt-get upgrade -y

# -------------------------------
# 2. Install Dependencies
# -------------------------------
echo "🔧 Installing dependencies..."
apt-get install -y ca-certificates curl gnupg lsb-release

# -------------------------------
# 3. Install Docker
# -------------------------------
echo "🐳 Installing Docker..."

# Remove old versions if exist
apt-get remove -y docker docker-engine docker.io containerd runc || true

# Add Docker GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg

chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repo
echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

# Install Docker
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable & start Docker
systemctl enable docker
systemctl start docker

# -------------------------------
# 4. Install k3d
# -------------------------------
echo "☸️ Installing k3d..."
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# -------------------------------
# 5. Install kubectl (Better than snap)
# -------------------------------
echo "📡 Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

# -------------------------------
# 6. Create k3d cluster (idempotent)
# -------------------------------
echo "⚙️ Creating k3d cluster..."

if ! k3d cluster list | grep -q prod; then
  k3d cluster create prod \
    -s 1 -a 1 \
    --k3s-arg "--disable=traefik@server:0" \
    -p "80:80@loadbalancer" \
    -p "443:443@loadbalancer"
else
  echo "⚠️ Cluster already exists. Skipping creation."
fi

# -------------------------------
# 7. Kubernetes Setup
# -------------------------------
echo "📦 Setting up Kubernetes namespace..."

kubectl wait --for=condition=Ready nodes --all --timeout=120s

kubectl create ns prod --dry-run=client -o yaml | kubectl apply -f -

kubectl config set-context --current --namespace=prod

# -------------------------------
# 8. Verify Setup
# -------------------------------
echo "✅ Verifying installation..."

docker --version
kubectl version --client
k3d version

kubectl get nodes
kubectl get ns

echo "🎉 Setup completed successfully!"
