#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

BASE_DIR="/opt/radio-orania"
FB_DIR="$BASE_DIR/filebrowser"
SERVICE_USER="radio-orania"

FB_USER="admin"

FB_PORT="$FILEBROWSER_PORT"
FB_ADDRESS="$FILEBROWSER_ADDRESS"

ARCH=$(uname -m)

case "$ARCH" in
    x86_64|amd64)
        FB_ARCH="amd64"
        ;;
    aarch64|arm64)
        FB_ARCH="arm64"
        ;;
    armv7l)
        FB_ARCH="armv7"
        ;;
    *)
        echo "Onondersteunde File Browser argitektuur: $ARCH"
        exit 1
        ;;
esac

progress 10 "Installeer vereistes"

apt-get install -y -qq \
    curl \
    tar \
    ca-certificates

mkdir -p "$FB_DIR"

progress 25 "Laai File Browser af"

TMP_FILE="/tmp/filebrowser.tar.gz"

curl -L \
    "https://github.com/filebrowser/filebrowser/releases/latest/download/linux-$FB_ARCH-filebrowser.tar.gz" \
    -o "$TMP_FILE"

progress 40 "Pak uit"

rm -f /tmp/filebrowser

tar -xzf "$TMP_FILE" -C /tmp

if [ ! -f /tmp/filebrowser ]; then
    echo "File Browser binary ontbreek na uitpak."
    exit 1
fi

progress 55 "Installeer binary"

install -m 755 \
    /tmp/filebrowser \
    /usr/local/bin/filebrowser

progress 70 "Kontroleer bestaande databasis"

NEW_INSTALL=true

if [ -f "$FB_DIR/database.db" ]; then
    NEW_INSTALL=false
fi

if [ "$NEW_INSTALL" = true ]; then

    progress 80 "Skep databasis"

    FB_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)

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

    chmod 600 "$FB_DIR/credentials.txt"

else
    progress 82 "Bestaande databasis en gebruikers word behou"
fi

progress 85 "Stel eienaarskap"

# database.db word deur root geskep; die diens loop egter as radio-orania
# en moet daarin kan skryf, dus moet eienaarskap voor die eerste begin reggestel word.
chown -R "$SERVICE_USER:audio" "$FB_DIR"

progress 90 "Skep systemd diens"

cat > /etc/systemd/system/filebrowser.service << EOF
[Unit]
Description=File Browser
After=network.target

[Service]
Type=simple
User=$SERVICE_USER

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

if [ "$NEW_INSTALL" = true ]; then
    echo "Gebruiker: $FB_USER"
    echo "Wagwoord : $FB_PASSWORD"
    echo
    echo "Bewaar:"
    echo "$FB_DIR/credentials.txt"
else
    echo
    echo "Bestaande gebruikers en wagwoorde is onveranderd gelaat."
    echo "Sien indien nodig: $FB_DIR/credentials.txt"
fi

echo
