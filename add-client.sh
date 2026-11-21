#!/bin/bash
# Add a device (or re-download an existing one) and show its QR code.
# Usage: ./add-client.sh <name>
set -euo pipefail
cd "$(dirname "$0")"; source common.sh
D=${1:?usage: ./add-client.sh <name>}
fetch_client "$D"
vm_ssh "sudo qrencode -t ansiutf8 < /etc/wireguard/clients/$D.conf"
