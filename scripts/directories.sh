#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"

BASE_DIR="/opt/radio-orania"

progress 10 "Skep hoofgids"

mkdir -p "$BASE_DIR"

progress 25 "Skep config"

mkdir -p "$BASE_DIR/config"

progress 40 "Skep Liquidsoap"

mkdir -p "$BASE_DIR/liquidsoap"

progress 55 "Skep logs"

mkdir -p "$BASE_DIR/logs"

progress 70 "Skep monitoring"

mkdir -p "$BASE_DIR/monitoring"

progress 85 "Skep media"

mkdir -p "$BASE_DIR/media/Musiek"
mkdir -p "$BASE_DIR/media/Sweepers"

progress 90 "Skep File Browser"

mkdir -p "$BASE_DIR/filebrowser"
mkdir -p "$BASE_DIR/backups"

progress 97 "Stel eienaarskap"

# Die diens-gebruiker moet reeds bestaan (user.sh loop voor hierdie skrip).
# Dit gebeur hier, vroeg, sodat dienste wat later as radio-orania herbegin
# word (bv. File Browser) reeds toegang tot hul vouers het.
if id radio-orania >/dev/null 2>&1; then
    chown -R radio-orania:audio \
        "$BASE_DIR/config" \
        "$BASE_DIR/liquidsoap" \
        "$BASE_DIR/logs" \
        "$BASE_DIR/monitoring" \
        "$BASE_DIR/media" \
        "$BASE_DIR/filebrowser" \
        "$BASE_DIR/backups"
fi

progress 100 "Klaar"