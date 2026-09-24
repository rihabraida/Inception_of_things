#!/usr/bin/env bash
set -eux

apt-get update -qq
apt-get install -y curl

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --node-ip=192.168.56.110 \
  --write-kubeconfig-mode=644 \
  --disable=traefik \
  --disable=servicelb \
  --disable=metrics-server" sh -s -

until [ -f /var/lib/rancher/k3s/server/node-token ]; do
  sleep 2
done

# HOSTNAME="$(hostname)"
HOSTNAME="$(hostname | tr '[:upper:]' '[:lower:]')"

until kubectl get node "$HOSTNAME" >/dev/null 2>&1; do
    sleep 2
done

kubectl label node "$HOSTNAME" node-role.kubernetes.io/master=true --overwrite

echo "alias k='kubectl'" >> /home/vagrant/.bashrc

cp /var/lib/rancher/k3s/server/node-token /vagrant/token