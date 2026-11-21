# Shared settings. Override with env vars, e.g.  ZONE=asia-south1-a ./deploy.sh
PROJECT=${PROJECT:-$(gcloud config get-value project 2>/dev/null)}
ZONE=${ZONE:-us-central1-a}          # us-central1/us-west1/us-east1 = free-tier e2-micro
REGION=${ZONE%-*}
VM_NAME=${VM_NAME:-wg-vpn}
[ -n "$PROJECT" ] || { echo "Set a project: gcloud config set project <ID>  (or PROJECT=<ID>)"; exit 1; }
G="--project=$PROJECT"

vm_ssh() { gcloud compute ssh "$VM_NAME" --zone="$ZONE" $G --quiet --command="$1" 2>/dev/null; }

fetch_client() {   # fetch_client <name> -> clients/<name>.conf
  mkdir -p clients && chmod 700 clients
  vm_ssh "sudo wg-add-client $1 >/dev/null; sudo cat /etc/wireguard/clients/$1.conf" > "clients/$1.conf"
  chmod 600 "clients/$1.conf"
  grep -q '^\[Peer\]' "clients/$1.conf" || { echo "Failed to fetch profile '$1'"; return 1; }
  echo "Saved clients/$1.conf"
}
