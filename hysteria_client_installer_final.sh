#!/bin/bash

set -e

echo -e "\033[1;34m>> Installing dependencies...\033[0m"
apt update -y && apt install -y curl iperf3 jq

# Check if dependencies installed correctly
if ! command -v curl &> /dev/null || ! command -v iperf3 &> /dev/null; then
    echo -e "\033[1;31m❌ Failed to install required packages. Exiting.\033[0m"
    exit 1
fi

echo -e "\033[1;34m>> Dependencies installed successfully.\033[0m"

# Now proceed with configuration
echo -e "\033[1;32mHysteria 2 Client Installer\033[0m"
echo "1) Install client"
echo "2) Uninstall client"
echo "3) Test tunnel speed (via iperf3)"
read -rp "Choose an option: " OPTION

if [[ "$OPTION" == "2" ]]; then
    systemctl stop hysteria-client.service || true
    systemctl disable hysteria-client.service || true
    rm -f /etc/hysteria-client/client.yaml /etc/systemd/system/hysteria-client.service
    echo "Uninstalled client service."
    exit 0
elif [[ "$OPTION" == "3" ]]; then
    if ! pgrep -f "hysteria2 client" > /dev/null; then
        echo "Client not running. Install first."
        exit 1
    fi
    iperf3 -c 127.0.0.1 -p 5201
    exit 0
fi

read -rp "Server address (IP or domain): " SERVER
read -rp "Server port (default 443): " PORT
PORT=${PORT:-443}
read -rp "Reality public key: " PUB_KEY
if [[ -z "$PUB_KEY" ]]; then
    echo "❌ Public key required. You can get it from: hysteria2 keygen"
    exit 1
fi
read -rp "Reality short ID: " SHORT_ID
read -rp "SNI (Server Name): " SNI
read -rp "Upload bandwidth (e.g., 100 mbps): " BW_UP
read -rp "Download bandwidth (e.g., 100 mbps): " BW_DOWN
read -rp "How many local ports to forward: " PORT_COUNT

FWRD=""
for ((i=1; i<=PORT_COUNT; i++)); do
    read -rp "Local port #$i: " LPORT
    read -rp "Remote port #$i: " RPORT
    FWRD+="
  - local: 127.0.0.1:$LPORT
    remote: 127.0.0.1:$RPORT"
done

curl -s https://get.hy2.sh | bash

mkdir -p /etc/hysteria-client

cat <<EOF > /etc/hysteria-client/client.yaml
server: $SERVER:$PORT
obfs:
  type: reality
  settings:
    public_key: "$PUB_KEY"
    short_id: "$SHORT_ID"
    server_name: "$SNI"
auth:
  type: disabled
bandwidth:
  up: $BW_UP
  down: $BW_DOWN
socks5:
  listen: 127.0.0.1:1080
forward:$FWRD
EOF

cat <<EOF > /etc/systemd/system/hysteria-client.service
[Unit]
Description=Hysteria 2 Client
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria2 client -c /etc/hysteria-client/client.yaml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now hysteria-client.service

echo -e "\n\033[1;32m✅ Hysteria 2 Client installed and running successfully!\033[0m"
