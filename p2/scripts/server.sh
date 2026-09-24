#!/usr/bin/env bash
set -eux

SERVER_IP="$1"


apt-get update -qq
apt-get install -y curl


curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --node-ip=${SERVER_IP} \
  --write-kubeconfig-mode=644 " sh -s -

# Wait for the API server to actually be ready before applying manifests.
until k3s kubectl get nodes >/dev/null 2>&1; do
  sleep 2
done


echo "alias k='kubectl'" >> /home/vagrant/.bashrc

# Apply the 3 apps + ingress
k3s kubectl apply -f /vagrant/confs/

echo "== k3s + 3 apps ready on ${SERVER_IP} =="