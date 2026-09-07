#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"

SERVICE_USER="radio-orania"

progress 20 "Kontroleer audio-groep"

if ! getent group audio >/dev/null; then
    groupadd --system audio
fi

progress 60 "Skep diens-gebruiker"

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd \
        --system \
        --no-create-home \
        --shell /usr/sbin/nologin \
        --gid audio \
        "$SERVICE_USER"
else
    usermod -aG audio "$SERVICE_USER"
fi

progress 100 "Klaar"
