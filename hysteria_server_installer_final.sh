#!/bin/bash

set -e

echo -e "\033[1;34m>> Installing dependencies...\033[0m"
apt update -y && apt install -y curl jq iperf3

if ! command -v curl &> /dev/null || ! command -v iperf3 &> /dev/null; then
    echo -e "\033[1;31m❌ Failed to install required packages. Exiting.\033[0m"
    exit 1
fi

echo -e "\033[1;34m>> Dependencies installed successfully.\033[0m"

echo -e "\033[1;32mHysteria 2 Server Installer\033[0m"
echo "1) Install server"
echo "2) Uninstall server"
read -rp "Choose an option: " OPTION

if [[ "$OPTION" == "2" ]]; then
    systemctl stop hysteria-server.service || true
    systemctl disable hysteria-server.service || true
    rm -f /etc/hysteria-server/config.yaml /etc/systemd/system/hysteria-server.service
    echo "✅ Server uninstalled successfully."
    exit 0
fi

read -rp "Domain (used for Reality SNI): " DOMAIN
read -rp "Port to listen on (default 443): " PORT
PORT=${PORT:-443}
read -rp "Number of tunnel ports to forward: " PORT_COUNT

FWRD=""
for ((i=1; i<=PORT_COUNT; i++)); do
    read -rp "Remote port #$i (will be tunneled): " RPORT
    FWRD+="
  - listen: 0.0.0.0:$RPORT
    remote: 127.0.0.1:$RPORT"
done

# Generate Reality keypair
KEY_OUTPUT=$(hysteria2 keygen)
PRIV_KEY=$(echo "$KEY_OUTPUT" | grep "Private key" | awk '{print $3}')
PUB_KEY=$(echo "$KEY_OUTPUT" | grep "Public key" | awk '{print $3}')

echo "Downloading Hysteria 2 binary..."

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    ARCH="amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
    ARCH="arm64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

LATEST=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep "browser_download_url" | grep "linux-$ARCH.tar.gz" | cut -d '"' -f 4)
curl -L "$LATEST" -o hysteria.tar.gz
tar -xzf hysteria.tar.gz
install -m 755 hysteria /usr/local/bin/hysteria2
rm -rf hysteria* LICENSE README.md

mkdir -p /etc/hysteria-server

cat <<EOF > /etc/hysteria-server/config.yaml
listen: :$PORT
protocol: udp
tls:
  cert: /etc/ssl/certs/$DOMAIN.pem
  key: /etc/ssl/private/$DOMAIN.key
obfs:
  type: reality
  settings:
    private_key: "$PRIV_KEY"
    short_id: "0123456789abcdef"
    server_names:
      - "$DOMAIN"
auth:
  type: disabled
masquerade:
  type: proxy
  settings:
    url: https://$DOMAIN
    rewrite_host: true
forward:$FWRD
EOF

cat <<EOF > /etc/systemd/system/hysteria-server.service
[Unit]
Description=Hysteria 2 Server
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria2 server -c /etc/hysteria-server/config.yaml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now hysteria-server.service

echo -e "\n\033[1;32m✅ Hysteria 2 Server installed and running successfully!\033[0m"
echo -e "\033[1;33mIMPORTANT: Save this public key for the client:\033[0m"
echo -e "\033[1;36m$PUB_KEY\033[0m"
