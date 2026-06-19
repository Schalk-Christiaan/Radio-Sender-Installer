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

progress 95 "Skep File Browser"

mkdir -p "$BASE_DIR/filebrowser"
mkdir -p "$BASE_DIR/backups"

progress 100 "Klaar"