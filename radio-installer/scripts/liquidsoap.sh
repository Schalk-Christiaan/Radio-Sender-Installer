#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

TARGET_DIR="/opt/radio-orania/liquidsoap"
TARGET_FILE="$TARGET_DIR/radio.liq"

progress 10 "Skep Liquidsoap gids"

mkdir -p "$TARGET_DIR"

progress 25 "Kopieer template"

cp \
    "$SCRIPT_DIR/../templates/radio.liq" \
    "$TARGET_FILE"

progress 50 "Vul konfigurasie in"

sed -i "s|__STREAM_URL__|$STREAM_URL|g" "$TARGET_FILE"

sed -i "s|__ALSA_DEVICE__|$ALSA_DEVICE|g" "$TARGET_FILE"

sed -i "s|__MUSIC_WEIGHT__|$MUSIC_WEIGHT|g" "$TARGET_FILE"

sed -i "s|__SWEEPER_WEIGHT__|$SWEEPER_WEIGHT|g" "$TARGET_FILE"

sed -i "s|__PLAYLIST_RELOAD__|$PLAYLIST_RELOAD|g" "$TARGET_FILE"

sed -i "s|__PLAYLIST_PREFETCH__|$PLAYLIST_PREFETCH|g" "$TARGET_FILE"

progress 75 "Verifieer konfigurasie"

if liquidsoap --check "$TARGET_FILE" >/dev/null 2>&1; then
    :
else
    echo
    echo "Liquidsoap konfigurasie ongeldig."
    exit 1
fi

progress 100 "Klaar"