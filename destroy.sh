#!/bin/bash
# Delete the VPN server, its IP(s) and the firewall rule. Stops all charges.
set -euo pipefail
cd "$(dirname "$0")"; source common.sh
read -rp "Delete $VM_NAME and its IPs in project $PROJECT? [y/N] " a; [ "$a" = y ] || exit 1

gcloud compute instances delete "$VM_NAME" --zone="$ZONE" $G --quiet || true
for ip in $(gcloud compute addresses list $G --filter="name~^$VM_NAME-ip" --format='value(name)'); do
  gcloud compute addresses delete "$ip" --region="$REGION" $G --quiet
done
gcloud compute firewall-rules delete allow-wireguard $G --quiet || true
echo "Deleted. (To remove the whole project: gcloud projects delete $PROJECT)"
