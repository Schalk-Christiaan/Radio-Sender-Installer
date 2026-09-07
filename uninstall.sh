#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_DIR="/opt/radio-orania"

echo
echo "=============================="
echo " Radio Orania Uninstaller"
echo "=============================="
echo

if [ "$EUID" -ne 0 ]; then
    echo "Hierdie uninstaller moet as root loop."
    echo "Gebruik: sudo bash uninstall.sh"
    exit 1
fi

read -rp "Is jy seker? (Y/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo
    echo "Gekanselleer."
    exit 0
fi

if [ -d "$BASE_DIR/media" ] && find "$BASE_DIR/media" -type f 2>/dev/null | grep -q .; then

    echo
    read -rp "Wil jy die media (musiek/sweepers) eers rugsteun? (Y/N) [Y]: " BACKUP

    if [[ ! "$BACKUP" =~ ^[Nn]$ ]]; then

        # As hierdie skrip vanuit die volgehoue kopie in $BASE_DIR/installer
        # loop, sal 'n rugsteun daar dadelik weer deur "rm -rf $BASE_DIR"
        # hieronder uitgevee word. Kies dan eerder 'n plek buite $BASE_DIR.
        BACKUP_DIR="$SCRIPT_DIR"

        case "$SCRIPT_DIR" in
            "$BASE_DIR"|"$BASE_DIR"/*)
                BACKUP_DIR="/root"
                ;;
        esac

        mkdir -p "$BACKUP_DIR" 2>/dev/null || BACKUP_DIR="/tmp"

        BACKUP_FILE="$BACKUP_DIR/radio-orania-media-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

        tar -czf "$BACKUP_FILE" -C "$BASE_DIR" media

        echo "Rugsteun gestoor: $BACKUP_FILE"

    fi

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

echo
echo ">>> Verwyder restart timer"

systemctl stop radio-orania-restart.timer 2>/dev/null || true
systemctl disable radio-orania-restart.timer 2>/dev/null || true
systemctl stop radio-orania-restart.service 2>/dev/null || true

rm -f /etc/systemd/system/radio-orania-restart.timer
rm -f /etc/systemd/system/radio-orania-restart.service
rm -f /usr/local/bin/restart-radio.sh

echo
echo ">>> Verwyder File Browser"

rm -f /usr/local/bin/filebrowser

echo
echo ">>> Verwyder beheerpaneel"

rm -f /usr/local/bin/radioctl

echo
echo ">>> Verwyder data"

rm -rf "$BASE_DIR"

echo
echo ">>> Verwyder diens-gebruiker"

if id radio-orania >/dev/null 2>&1; then
    userdel radio-orania 2>/dev/null || true
fi

echo
echo ">>> Herlaai systemd"

systemctl daemon-reload
systemctl reset-failed

echo
echo "=============================="
echo " Verwydering voltooi"
echo "=============================="
