#!/bin/bash
# Create the VPN server and download profiles for the given devices.
# Usage: ./deploy.sh [device ...]      (default: phone laptop)
set -euo pipefail
cd "$(dirname "$0")"; source common.sh
[ $# -eq 0 ] && set -- phone laptop

gcloud services enable compute.googleapis.com $G

gcloud compute addresses create "$VM_NAME-ip" --region="$REGION" --network-tier=STANDARD $G 2>/dev/null || true
IP=$(gcloud compute addresses describe "$VM_NAME-ip" --region="$REGION" $G --format='value(address)')

gcloud compute firewall-rules create allow-wireguard $G \
  --network=default --allow=udp:51820 --target-tags=wireguard 2>/dev/null || true

gcloud compute instances create "$VM_NAME" $G \
  --zone="$ZONE" \
  --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --boot-disk-size=10GB --boot-disk-type=pd-standard \
  --can-ip-forward \
  --tags=wireguard \
  --network-tier=STANDARD --address="$IP" \
  --metadata-from-file=startup-script=server-setup.sh

echo "Server at $IP. Waiting for WireGuard to install..."
for _ in $(seq 40); do
  vm_ssh 'test -x /usr/local/bin/wg-add-client && systemctl is-active -q wg-quick@wg0' && break
  sleep 10
done

for d in "$@"; do fetch_client "$d"; done
echo "Done. VPN endpoint: $IP:51820"
