
#!/bin/bash

set -e

HYSTERIA_BIN="/usr/local/bin/hysteria2"
CONFIG_DIR="/etc/hysteria-client"
CONFIG_FILE="$CONFIG_DIR/client.yaml"
SERVICE_FILE="/etc/systemd/system/hysteria-client.service"

echo -e "\033[1;32mHysteria 2 Client Installer\033[0m"
echo "1) Install client"
echo "2) Uninstall client"
echo "3) Test tunnel speed (via iperf3)"
read -rp "Choose an option: " OPTION

if [[ "$OPTION" == "2" ]]; then
    echo "Stopping and disabling client service..."
    systemctl stop hysteria-client.service || true
    systemctl disable hysteria-client.service || true
    rm -f "$CONFIG_FILE" "$SERVICE_FILE"
    echo "Do you want to remove the binaries too? [y/N]"
    read -r RM_BIN
    if [[ "$RM_BIN" =~ ^[Yy]$ ]]; then
        rm -f "$HYSTERIA_BIN" "$(which iperf3)"
    fi
    echo "Uninstallation complete."
    exit 0
elif [[ "$OPTION" == "3" ]]; then
    echo "Running iperf3 speed test over hysteria tunnel..."
    if ! pgrep -f "hysteria2 client" > /dev/null; then
        echo "Client is not running. Please run install first."
        exit 1
    fi
    if ! command -v iperf3 &> /dev/null; then
        echo "iperf3 not found, installing..."
        apt update -y && apt install -y iperf3
    fi
    iperf3 -c 127.0.0.1 -p 5201
    exit 0
fi

read -rp "Enter server address (IP or domain): " SERVER
read -rp "Enter server port (default 443): " PORT
PORT=${PORT:-443}
read -rp "Enter Reality public key: " PUB_KEY
read -rp "Enter Reality short ID: " SHORT_ID
read -rp "Enter server name (SNI): " SNI

read -rp "Enter your estimated upload bandwidth (e.g., 100 mbps): " BW_UP
read -rp "Enter your estimated download bandwidth (e.g., 100 mbps): " BW_DOWN

read -rp "How many local ports do you want to forward? " PORT_COUNT

FWRD=""
for ((i=1; i<=PORT_COUNT; i++)); do
    read -rp "Local listen port #$i: " LPORT
    read -rp "Target port on server #$i: " TPORT
    FWRD+="
  - local: 127.0.0.1:$LPORT
    remote: 127.0.0.1:$TPORT"
done

echo "Installing dependencies..."
apt update -y && apt install -y curl iperf3

echo "Downloading Hysteria 2 client..."
curl -s https://get.hy2.sh | bash

mkdir -p "$CONFIG_DIR"

cat <<EOF > "$CONFIG_FILE"
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

cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Hysteria 2 Client
After=network.target

[Service]
ExecStart=$HYSTERIA_BIN client -c $CONFIG_FILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "Enabling and starting hysteria client..."
systemctl daemon-reload
systemctl enable --now hysteria-client.service

echo -e "\n\033[1;32mClient installation complete!\033[0m"
echo "Tunnel is active. Run this script again and choose option 3 to test speed."
