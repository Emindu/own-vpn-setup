#!/bin/bash
# Runs on the GCP VM as its startup script. Installs and configures WireGuard.
# Safe to re-run: skips setup if already done.
set -euo pipefail

if [ -f /etc/wireguard/wg0.conf ]; then
  systemctl enable --now wg-quick@wg0
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y wireguard qrencode iptables curl

# Enable IP forwarding
cat > /etc/sysctl.d/99-wireguard.conf <<EOF
net.ipv4.ip_forward=1
EOF
sysctl --system

WAN_IF=$(ip -4 route show default | awk '{print $5; exit}')
umask 077
mkdir -p /etc/wireguard/clients
cd /etc/wireguard
wg genkey | tee server.key | wg pubkey > server.pub

cat > wg0.conf <<EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $(cat server.key)
PostUp   = iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $WAN_IF -j MASQUERADE; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o $WAN_IF -j MASQUERADE; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT
EOF

# Helper to add clients: sudo wg-add-client <name>
cat > /usr/local/bin/wg-add-client <<'SCRIPT'
#!/bin/bash
set -euo pipefail
NAME=${1:?usage: wg-add-client <name>}
cd /etc/wireguard
umask 077
[ -f "clients/$NAME.conf" ] && { cat "clients/$NAME.conf"; exit 0; }
N=$(( $(grep -c '^\[Peer\]' wg0.conf || true) + 2 ))
[ "$N" -gt 254 ] && { echo "subnet full"; exit 1; }
PRIV=$(wg genkey); PUB=$(echo "$PRIV" | wg pubkey); PSK=$(wg genpsk)
ENDPOINT=$(curl -s -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
cat >> wg0.conf <<EOF

[Peer]
# $NAME
PublicKey = $PUB
PresharedKey = $PSK
AllowedIPs = 10.8.0.$N/32
EOF
cat > "clients/$NAME.conf" <<EOF
[Interface]
PrivateKey = $PRIV
Address = 10.8.0.$N/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $(cat server.pub)
PresharedKey = $PSK
Endpoint = $ENDPOINT:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
wg syncconf wg0 <(wg-quick strip wg0) 2>/dev/null || true
cat "clients/$NAME.conf"
echo
qrencode -t ansiutf8 < "clients/$NAME.conf"
SCRIPT
chmod +x /usr/local/bin/wg-add-client

systemctl enable --now wg-quick@wg0
/usr/local/bin/wg-add-client phone >/dev/null
/usr/local/bin/wg-add-client laptop >/dev/null
