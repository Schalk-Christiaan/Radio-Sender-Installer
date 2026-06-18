#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"

progress 20 "Kopieer systemd diens"

cp \
    "$SCRIPT_DIR/../templates/radio-orania.service" \
    /etc/systemd/system/radio-orania.service

progress 50 "Herlaai systemd"

systemctl daemon-reload

progress 80 "Aktiveer diens"

systemctl enable radio-orania.service

progress 100 "Klaar"