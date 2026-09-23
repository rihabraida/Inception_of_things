#!/usr/bin/env bash
set -euo pipefail

### Uninstall color helpers (optional)
RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; BLUE="\033[0;34m"; NC="\033[0m"
log()   { echo -e "${BLUE}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

##############################
# Remove k3d and Kubernetes
##############################

log "Deleting all k3d clusters"
if command -v k3d >/dev/null 2>&1; then
    k3d cluster delete --all || warn "Failed to delete k3d clusters"
else
    warn "k3d not found — skipping k3d cluster deletion"
fi

log "Removing k3d binary"
sudo rm -f /usr/local/bin/k3d

log "Removing Kubernetes config"
rm -f ~/.kube/config

##############################
# Remove Docker
##############################

log "Stopping Docker"
sudo systemctl stop docker || warn "Could not stop Docker"

log "Removing Docker containers, images, volumes"
sudo docker rm -f $(docker ps -aq) 2>/dev/null || true
sudo docker rmi -f $(docker images -aq) 2>/dev/null || true
sudo docker volume prune -f || true

log "Uninstalling Docker packages"
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker.io || true
sudo apt-get autoremove -y
sudo rm -rf /var/lib/docker /etc/docker

##############################
# Remove kubectl
##############################

log "Removing kubectl"
sudo rm -f /usr/local/bin/kubectl

##############################
# Remove Git
##############################

log "Removing Git"
sudo apt-get purge -y git || true
sudo apt-get autoremove -y

##############################
# Remove Helm and GitLab
##############################

log "Removing Helm"
sudo rm -f /usr/local/bin/helm

# If you installed Helm through package manager:
sudo apt-get purge -y helm || true

log "Uninstalling GitLab Helm release"
# Uninstall GitLab helm release and its Kubernetes resources
kubectl delete namespace gitlab --ignore-not-found || warn "namespace gitlab not found"
helm uninstall gitlab -n gitlab --ignore-not-found || warn "GitLab release not found"
# Delete leftover PVCs & secrets (may contain stateful data you want removed) :contentReference[oaicite:0]{index=0}
kubectl delete pvc,secret -l release=gitlab --all --ignore-not-found || true

##############################
# Remove ArgoCD
##############################

log "Removing ArgoCD installation from Kubernetes"
# Delete ArgoCD manifests installed by script
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found || warn "ArgoCD manifests might not exist"
# Remove ArgoCD namespace
kubectl delete namespace argocd --ignore-not-found || warn "ArgoCD namespace not found" :contentReference[oaicite:1]{index=1}

log "Removing ArgoCD CLI"
sudo rm -f /usr/local/bin/argocd

##############################
# Clean up hosts entry
##############################

log "Cleaning /etc/hosts entry for GitLab"
sudo sed -i '/gitlab.k3d.gitlab.com/d' /etc/hosts

##############################
# Final cleanup
##############################

log "Auto-removing unused packages"
sudo apt-get autoremove -y

log "${GREEN}Uninstall complete!${NC}"
