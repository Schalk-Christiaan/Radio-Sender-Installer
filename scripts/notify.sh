#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

BASE_DIR="/opt/radio-orania"

progress 10 "Verwyder ou Uptime Kuma-heartbeat"

# Vervang deur ntfy (hierdie diens) en Beszel - ruim ou installasies op.
if [ -f /etc/systemd/system/radio-heartbeat.service ]; then
    systemctl stop radio-heartbeat.service 2>/dev/null || true
    systemctl disable radio-heartbeat.service 2>/dev/null || true
    rm -f /etc/systemd/system/radio-heartbeat.service
    systemctl daemon-reload
fi
rm -f "$BASE_DIR/monitoring/heartbeat.sh"

progress 25 "Kontroleer kennisgewings"

if [ -z "${NTFY_URL:-}" ]; then

    if [ -f /etc/systemd/system/radio-notify.service ]; then
        systemctl stop radio-notify.service 2>/dev/null || true
        systemctl disable radio-notify.service 2>/dev/null || true
        rm -f /etc/systemd/system/radio-notify.service
        systemctl daemon-reload
    fi

    progress 100 "Geen kennisgewings ingestel"
    exit 0
fi

progress 50 "Installeer kennisgewings"

mkdir -p "$BASE_DIR/monitoring"

cp \
    "$SCRIPT_DIR/../templates/notify.sh" \
    "$BASE_DIR/monitoring/notify.sh"

chmod +x \
    "$BASE_DIR/monitoring/notify.sh"

if id radio-orania >/dev/null 2>&1; then
    chown radio-orania:audio "$BASE_DIR/monitoring/notify.sh"
fi

progress 75 "Installeer kennisgewings diens"

cp \
    "$SCRIPT_DIR/../templates/radio-notify.service" \
    /etc/systemd/system/radio-notify.service

systemctl daemon-reload

systemctl enable radio-notify.service >/dev/null 2>&1
systemctl restart radio-notify.service >/dev/null 2>&1

progress 100 "Klaar"
