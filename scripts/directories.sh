#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"

if [ "$EUID" -ne 0 ]; then
    echo "Hierdie installer moet as root loop."
    exit 1
fi

progress 10 "Werk pakketlyste op"

apt-get update

progress 40 "Installeer vereiste pakkette"

apt-get install -y \
    liquidsoap \
    ffmpeg \
    alsa-utils \
    curl \
    wget \
    nano \
    tar \
    ca-certificates

progress 80 "Verifieer installasie"

command -v liquidsoap >/dev/null
command -v ffmpeg >/dev/null
command -v aplay >/dev/null
command -v curl >/dev/null
command -v wget >/dev/null

progress 100 "Klaar"