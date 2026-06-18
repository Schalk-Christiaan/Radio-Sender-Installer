#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

BASE_DIR="/opt/radio-orania"
FB_DIR="$BASE_DIR/filebrowser"

FB_USER="admin"

FB_PORT="$FILEBROWSER_PORT"
FB_ADDRESS="$FILEBROWSER_ADDRESS"

progress 10 "Installeer vereistes"

apt-get install -y -qq \
    curl \
    tar \
    ca-certificates

mkdir -p "$FB_DIR"

progress 25 "Laai File Browser af"

TMP_FILE="/tmp/filebrowser.tar.gz"

curl -L \
    https://github.com/filebrowser/filebrowser/releases/latest/download/linux-amd64-filebrowser.tar.gz \
    -o "$TMP_FILE"

progress 40 "Pak uit"

rm -f /tmp/filebrowser

tar -xzf "$TMP_FILE" -C /tmp

progress 55 "Installeer binary"

install -m 755 \
    /tmp/filebrowser \
    /usr/local/bin/filebrowser

progress 70 "Genereer wagwoord"

FB_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)

progress 80 "Skep databasis"

if [ -f "$FB_DIR/database.db" ]; then

    progress 82 "Verwyder ou databasis"

    systemctl stop filebrowser.service 2>/dev/null || true

    rm -f "$FB_DIR/database.db"

fi

filebrowser config init \
    --database "$FB_DIR/database.db" \
    >/dev/null 2>&1

filebrowser config set \
    --database "$FB_DIR/database.db" \
    --root "$BASE_DIR/media" \
    >/dev/null 2>&1

filebrowser users add \
    "$FB_USER" \
    "$FB_PASSWORD" \
    --perm.admin \
    --database "$FB_DIR/database.db" \
    >/dev/null 2>&1

cat > "$FB_DIR/credentials.txt" << EOF
File Browser Login

URL:
http://$FB_ADDRESS:$FB_PORT

Gebruiker:
$FB_USER

Wagwoord:
$FB_PASSWORD
EOF

progress 90 "Skep systemd diens"

cat > /etc/systemd/system/filebrowser.service << EOF
[Unit]
Description=File Browser
After=network.target

[Service]
Type=simple

ExecStart=/usr/local/bin/filebrowser \
  --address $FB_ADDRESS \
  --port $FB_PORT \
  --database $FB_DIR/database.db \
  --root $BASE_DIR/media

Restart=always
RestartSec=5

StandardOutput=append:$FB_DIR/filebrowser.log
StandardError=append:$FB_DIR/filebrowser.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >/dev/null 2>&1
systemctl enable filebrowser.service >/dev/null 2>&1
systemctl restart filebrowser.service >/dev/null 2>&1

progress 100 "Klaar"

echo
echo "===================================="
echo " File Browser"
echo "===================================="
echo
echo "URL: http://$FB_ADDRESS:$FB_PORT"
echo "Gebruiker: $FB_USER"
echo "Wagwoord : $FB_PASSWORD"
echo
echo "Bewaar:"
echo "$FB_DIR/credentials.txt"
echo