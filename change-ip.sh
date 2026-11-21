#!/bin/bash
# Give the server a new public IP (same region), release the old one,
# and update every device profile. Turn OFF the VPN on this machine first.
set -euo pipefail
cd "$(dirname "$0")"; source common.sh

OLD=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" $G \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
OLD_NAME=$(gcloud compute addresses list $G --filter="address=$OLD" --format='value(name)')
NEW_NAME="$VM_NAME-ip-$(date +%s)"

gcloud compute addresses create "$NEW_NAME" --region="$REGION" --network-tier=STANDARD $G
NEW=$(gcloud compute addresses describe "$NEW_NAME" --region="$REGION" $G --format='value(address)')

gcloud compute instances delete-access-config "$VM_NAME" --zone="$ZONE" $G --access-config-name=external-nat
gcloud compute instances add-access-config "$VM_NAME" --zone="$ZONE" $G \
  --access-config-name=external-nat --address="$NEW" --network-tier=STANDARD
[ -n "$OLD_NAME" ] && gcloud compute addresses delete "$OLD_NAME" --region="$REGION" $G --quiet

vm_ssh "sudo sh -c 'sed -i \"s/^Endpoint = .*:51820/Endpoint = $NEW:51820/\" /etc/wireguard/clients/*.conf'"
for f in clients/*.conf; do [ -e "$f" ] && sed -i "s/^Endpoint = .*:51820/Endpoint = $NEW:51820/" "$f"; done

echo "IP changed: $OLD -> $NEW"
echo "Re-import profiles on your devices (or edit Endpoint to $NEW:51820)."
