#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

TARGET_DIR="/opt/radio-orania/liquidsoap"
TARGET_FILE="$TARGET_DIR/radio.liq"

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

progress 10 "Skep Liquidsoap gids"

mkdir -p "$TARGET_DIR"

progress 25 "Kopieer template"

cp \
    "$SCRIPT_DIR/../templates/radio.liq" \
    "$TARGET_FILE"

if [ "$INSTALL_DASHBOARD" = "yes" ]; then
    cat "$SCRIPT_DIR/../templates/radio-icecast.liq" >> "$TARGET_FILE"
fi

if [ -n "$BACKUP_STREAM_URL" ]; then
    sed -i "/^# __BACKUP_RADIO_INSERT_POINT__$/r $SCRIPT_DIR/../templates/radio-backup-stream.liq" "$TARGET_FILE"
fi

sed -i "/^# __BACKUP_RADIO_INSERT_POINT__$/d" "$TARGET_FILE"

progress 50 "Vul konfigurasie in"

sed -i "s|__STREAM_URL__|$(escape_sed_replacement "$STREAM_URL")|g" "$TARGET_FILE"

sed -i "s|__ALSA_DEVICE__|$(escape_sed_replacement "$ALSA_DEVICE")|g" "$TARGET_FILE"

sed -i "s|__MUSIC_WEIGHT__|$MUSIC_WEIGHT|g" "$TARGET_FILE"

sed -i "s|__SWEEPER_WEIGHT__|$SWEEPER_WEIGHT|g" "$TARGET_FILE"

sed -i "s|__PLAYLIST_RELOAD__|$PLAYLIST_RELOAD|g" "$TARGET_FILE"

sed -i "s|__PLAYLIST_PREFETCH__|$PLAYLIST_PREFETCH|g" "$TARGET_FILE"

if [ "$INSTALL_DASHBOARD" = "yes" ]; then
    sed -i "s|__ICECAST_PORT__|$ICECAST_PORT|g" "$TARGET_FILE"
    sed -i "s|__ICECAST_SOURCE_PASSWORD__|$(escape_sed_replacement "$ICECAST_SOURCE_PASSWORD")|g" "$TARGET_FILE"
fi

if [ -n "$BACKUP_STREAM_URL" ]; then
    sed -i "s|__BACKUP_RADIO_ENTRY__|backup_radio,|g" "$TARGET_FILE"
    sed -i "s|__BACKUP_STREAM_URL__|$(escape_sed_replacement "$BACKUP_STREAM_URL")|g" "$TARGET_FILE"
else
    sed -i "s|__BACKUP_RADIO_ENTRY__||g" "$TARGET_FILE"
fi

progress 75 "Verifieer konfigurasie"

if liquidsoap --check "$TARGET_FILE" >/dev/null 2>&1; then
    :
else
    echo
    echo "Liquidsoap konfigurasie ongeldig."
    exit 1
fi

progress 90 "Stel eienaarskap"

if id radio-orania >/dev/null 2>&1; then
    chown -R radio-orania:audio "$TARGET_DIR"
fi

progress 100 "Klaar"
