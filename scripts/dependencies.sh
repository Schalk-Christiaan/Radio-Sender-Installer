#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"

# Root kontrole
if [ "$EUID" -ne 0 ]; then
    echo "Hierdie installer moet as root loop."
    echo "Gebruik: sudo ./install.sh"
    exit 1
fi

progress 10 "Werk pakketlyste op"

apt-get update

progress 30 "Installeer Liquidsoap"

apt-get install -y liquidsoap

progress 50 "Installeer FFmpeg"

apt-get install -y ffmpeg

progress 70 "Installeer ALSA"

apt-get install -y alsa-utils

progress 85 "Installeer hulpmiddels"

apt-get install -y \
    curl \
    wget \
    nano

progress 95 "Verifieer installasie"

command -v liquidsoap >/dev/null
command -v ffmpeg >/dev/null
command -v aplay >/dev/null

progress 100 "Klaar"