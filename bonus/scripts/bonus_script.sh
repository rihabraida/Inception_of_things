#!/bin/bash
# ==============================================================================
# bonus-gitlab-setup.sh
#
# Standalone script for the Inception-of-Things BONUS part only:
#   - K3d cluster with a SINGLE port mapping (no HTTPS/443 at all)
#   - GitLab's external dependencies (CloudNativePG / Valkey / Garage)
#   - GitLab itself, installed over plain HTTP (TLS/cert-manager disabled)
#
# This does NOT include the playground app or Argo CD — those belong to P3.
# If P3 already exists in this cluster, this script coexists with it, as
# long as the SAME K3d cluster/port mapping is reused (see Stage 1 note).
#
# Requirements before running:
#   - Docker, kubectl, k3d, Helm (v4+) already installed
#   - 30GB+ free host disk, 8GB+ VM RAM, 60GB+ VM disk recommended
# ==============================================================================
set -euo pipefail

CLUSTER_NAME="iot-cluster"
DOMAIN="local.gitlab"
PORT="8888"

echo "=== Stage 0: Install environment requirements (Docker, kubectl, k3d, Helm) ==="
command -v docker >/dev/null 2>&1 || curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER" || true

command -v kubectl >/dev/null 2>&1 || {
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
}

command -v k3d >/dev/null 2>&1 || curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

command -v helm >/dev/null 2>&1 || curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash

command -v git >/dev/null 2>&1 || sudo apt-get update && sudo apt-get install -y git

echo "Installed versions:"
docker --version
kubectl version --client
k3d version
helm version
git --version


# ------------------------------------------------------------------------------
echo "=== Stage 1: K3d cluster — ONE port mapping only ==="
# NOTE: if a P3 cluster with this name already exists and you want to KEEP it
# (with playground/Argo CD already running), skip this delete/create block —
# just make sure that existing cluster already has a port mapped to 80.
if k3d cluster list | grep -q "^${CLUSTER_NAME} "; then
  echo "Cluster '${CLUSTER_NAME}' already exists — reusing it."
else
  k3d cluster create "$CLUSTER_NAME" --agent 1\
    --port "${PORT}:80@loadbalancer"
fi
kubectl get nodes -o wide

# ------------------------------------------------------------------------------
echo "=== Stage 2: Namespace ==="
kubectl apply -f "$(dirname "$0")/../confs/namespace.yaml"

# ------------------------------------------------------------------------------
echo "=== Stage 3: GitLab external dependencies (Postgres / Redis / object storage) ==="

if [ ! -d gitlab ]; then
  git clone https://gitlab.com/gitlab-org/charts/gitlab.git
fi
cd gitlab

helm version   # must be v4+, dev_dependencies.sh requires it
bash scripts/dev_dependencies.sh setup
bash scripts/dev_dependencies.sh status
cd ..

echo "Waiting for dependency pods..."
sleep 10
kubectl get pods -n gitlab

echo "=== Stage 4: Gateway API / Envoy Gateway CRDs (idempotent, avoids field-manager conflicts) ==="
helm template eg-crds oci://docker.io/envoyproxy/gateway-crds-helm \
  --version v1.9.1 \
  --set crds.gatewayAPI.enabled=true \
  --set crds.envoyGateway.enabled=true \
  | kubectl apply --server-side --force-conflicts -f -

echo "=== Stage 5: Install (or upgrade) GitLab ==="
if helm status gitlab -n gitlab >/dev/null 2>&1; then
  helm upgrade gitlab gitlab/gitlab -n gitlab \
    -f gitlab/.values/dev-external.values.yaml \
    -f "$(dirname "$0")/../confs/gitlab-values.yaml" \
    --skip-crds \
    --timeout 900s
else
  helm install gitlab gitlab/gitlab -n gitlab \
    -f gitlab/.values/dev-external.values.yaml \
    -f "$(dirname "$0")/../confs/gitlab-values.yaml" \
    --skip-crds \
    --timeout 900s
fi

echo "Waiting for GitLab pods (10-15+ minutes on first install)..."
kubectl get pods -n gitlab -w &
WATCH_PID=$!
sleep 10
kill $WATCH_PID 2>/dev/null || true

echo "Run 'kubectl get pods -n gitlab' periodically until webservice/sidekiq/gitaly are Running."
read -p "Press Enter once all GitLab pods show Running/Completed..."

kubectl get pods -n gitlab
kubectl get jobs -n gitlab


# ------------------------------------------------------------------------------
echo "=== Stage 6: /etc/hosts ==="
grep -q "${DOMAIN}" /etc/hosts 2>/dev/null || \
  sudo sh -c "echo '127.0.0.1   gitlab.${DOMAIN}' >> /etc/hosts"

# ------------------------------------------------------------------------------
echo "=== Stage 7: Credentials ==="
echo "GitLab root password:"
kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 -d
echo

# ------------------------------------------------------------------------------
echo "=== Stage 8: Verify ==="
sleep 5
echo "Testing GitLab reachability..."
curl -sS -H "Host: gitlab.${DOMAIN}" "http://localhost:${PORT}/" | head -c 300 || echo "FAILED — check pods/logs"
echo

cat << EOF

=== Bonus GitLab setup complete ===

Access:  http://gitlab.${DOMAIN}:${PORT}/
Login:   root / <password printed above>

If curl above returned actual HTML (not a connection error), GitLab is up.
If it still shows a redirect or 404, re-run:
  kubectl delete httproute gitlab-http-redirect -n gitlab --ignore-not-found
and retest.

Remaining MANUAL steps (require the browser, not scriptable):
  1. Log in, create a project, push your P3 manifests to it.
  2. Point your Argo CD Application's repoURL at GitLab's INTERNAL
     cluster DNS name (Argo CD's pod cannot resolve "gitlab.${DOMAIN}" —
     that name only exists in YOUR /etc/hosts, not the cluster's DNS):
       http://gitlab-webservice-default.gitlab.svc.cluster.local:8181/<ns>/<project>.git
EOF