#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

TARGET_FILE="/etc/systemd/system/radio-orania.service"

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

progress 20 "Kopieer systemd diens"

cp \
    "$SCRIPT_DIR/../templates/radio-orania.service" \
    "$TARGET_FILE"

progress 35 "Vul stasienaam in"

sed -i "s|__STATION_NAME__|$(escape_sed_replacement "$STATION_NAME")|g" "$TARGET_FILE"

progress 50 "Herlaai systemd"

systemctl daemon-reload

progress 80 "Aktiveer diens"

systemctl enable radio-orania.service

progress 90 "Begin diens"

systemctl restart radio-orania.service

progress 100 "Klaar"