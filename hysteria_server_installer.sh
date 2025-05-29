
#!/bin/bash

set -e

HYSTERIA_BIN="/usr/local/bin/hysteria2"
CONFIG_DIR="/etc/hysteria"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
SERVICE_FILE="/etc/systemd/system/hysteria2.service"
IPERF3_SERVICE="/etc/systemd/system/iperf3-server.service"

echo -e "\033[1;32mHysteria 2 Server Installer\033[0m"
echo "1) Install"
echo "2) Uninstall"
read -rp "Choose an option: " OPTION

if [[ "$OPTION" == "2" ]]; then
    echo "Stopping and disabling Hysteria 2 and iperf3 service..."
    systemctl stop hysteria2.service iperf3-server.service || true
    systemctl disable hysteria2.service iperf3-server.service || true
    echo "Removing config and service files..."
    rm -f "$CONFIG_FILE" "$SERVICE_FILE" "$IPERF3_SERVICE"
    echo "Do you want to remove the binaries too? [y/N]"
    read -r RM_BIN
    if [[ "$RM_BIN" =~ ^[Yy]$ ]]; then
        rm -f "$HYSTERIA_BIN" "$(which iperf3)"
    fi
    echo "Uninstallation complete."
    exit 0
fi

read -rp "Is this the Iran server or Abroad server? (iran/abroad): " LOCATION
read -rp "Enter your Reality server name (e.g., cloudflare.com): " DOMAIN
read -rp "Enter the listen port (default 443): " PORT
PORT=${PORT:-443}
read -rp "How many ports do you want to tunnel (including iperf3 test)? " PORT_COUNT

FORWARDS=""
for ((i=1; i<=PORT_COUNT; i++)); do
    read -rp "Enter local listen port #$i: " LPORT
    read -rp "Enter target destination port #$i: " TPORT
    FORWARDS+="
  - type: tcp
    listen: 127.0.0.1:$LPORT
    target: 127.0.0.1:$TPORT"
done

echo "Installing dependencies..."
apt update -y && apt install -y curl iperf3

echo "Downloading Hysteria 2 binary..."
curl -s https://get.hy2.sh | bash

echo "Generating Reality key pair..."
KEYS=$($HYSTERIA_BIN genkey)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 4)

mkdir -p "$CONFIG_DIR"

cat <<EOF > "$CONFIG_FILE"
listen: :$PORT
protocol: udp
obfs:
  type: reality
  settings:
    private_key: "$PRIVATE_KEY"
    short_id: "$SHORT_ID"
    server_name: "$DOMAIN"
auth:
  type: disabled
forward:$FORWARDS
tls:
  enabled: false
EOF

cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Hysteria 2 Server
After=network.target

[Service]
ExecStart=$HYSTERIA_BIN server -c $CONFIG_FILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > "$IPERF3_SERVICE"
[Unit]
Description=iperf3 Server Service
After=network.target

[Service]
ExecStart=/usr/bin/iperf3 -s -p 5201
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "Enabling and starting services..."
systemctl daemon-reload
systemctl enable --now hysteria2.service iperf3-server.service

echo -e "\n\033[1;32mInstallation complete!\033[0m"
echo "Public key (for client): $PUBLIC_KEY"
echo "Short ID (for client): $SHORT_ID"
echo "Server name (SNI): $DOMAIN"
echo "Listening on port: $PORT"
echo "iperf3 server running on port 5201 (make sure it’s forwarded in hysteria config)"
