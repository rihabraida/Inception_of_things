#!/bin/bash

curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# K3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Argo CD CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 0755 argocd /usr/local/bin/argocd

# Helm (for bonus)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash