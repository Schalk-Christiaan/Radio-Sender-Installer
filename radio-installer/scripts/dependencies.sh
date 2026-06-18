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

apt-get update -qq

progress 30 "Installeer Liquidsoap"

apt-get install -y liquidsoap -qq

progress 50 "Installeer FFmpeg"

apt-get install -y ffmpeg -qq

progress 70 "Installeer ALSA"

apt-get install -y alsa-utils -qq

progress 85 "Installeer hulpmiddels"

apt-get install -y -qq \
    curl \
    wget \
    nano 

progress 95 "Verifieer installasie"

command -v liquidsoap >/dev/null
command -v ffmpeg >/dev/null
command -v aplay >/dev/null

progress 100 "Klaar"