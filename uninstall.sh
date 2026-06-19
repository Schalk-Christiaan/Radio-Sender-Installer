#!/bin/bash

set -e

BASE_DIR="/opt/radio-orania"

echo
echo "=============================="
echo " Radio Orania Uninstaller"
echo "=============================="
echo

read -rp "Is jy seker? (Y/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo
    echo "Gekanselleer."
    exit 0
fi

echo
echo ">>> Stop dienste"

systemctl stop radio-orania.service 2>/dev/null || true
systemctl disable radio-orania.service 2>/dev/null || true

systemctl stop filebrowser.service 2>/dev/null || true
systemctl disable filebrowser.service 2>/dev/null || true

echo
echo ">>> Verwyder systemd"

rm -f /etc/systemd/system/radio-orania.service
rm -f /etc/systemd/system/filebrowser.service

echo
echo ">>> Verwyder monitoring"

systemctl stop radio-heartbeat.service 2>/dev/null || true
systemctl disable radio-heartbeat.service 2>/dev/null || true

rm -f /etc/systemd/system/radio-heartbeat.service
rm -f /usr/local/bin/heartbeat.sh

echo
echo ">>> Verwyder File Browser"

rm -f /usr/local/bin/filebrowser

echo
echo ">>> Verwyder data"

rm -rf "$BASE_DIR"

echo
echo ">>> Herlaai systemd"

systemctl daemon-reload
systemctl reset-failed

echo
echo "=============================="
echo " Verwydering voltooi"
echo "=============================="