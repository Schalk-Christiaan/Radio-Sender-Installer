#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"

BASE_DIR="/opt/radio-orania"
SERVICE_USER="radio-orania"

progress 30 "Stel eienaarskap"

# Die installer-kopie (indien teenwoordig) bly opsetlik root-besit,
# sodat die laer-bevoegde diens-gebruiker dit nie kan verander nie.
for d in config liquidsoap logs monitoring media filebrowser backups; do
    if [ -e "$BASE_DIR/$d" ]; then
        chown -R "$SERVICE_USER:audio" "$BASE_DIR/$d"
    fi
done

progress 70 "Beperk sensitiewe lêers"

if [ -f "$BASE_DIR/config/environment.conf" ]; then
    chmod 600 "$BASE_DIR/config/environment.conf"
fi

if [ -f "$BASE_DIR/filebrowser/credentials.txt" ]; then
    chmod 600 "$BASE_DIR/filebrowser/credentials.txt"
fi

progress 100 "Klaar"
