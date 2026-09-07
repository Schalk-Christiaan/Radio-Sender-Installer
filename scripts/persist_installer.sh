#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER_DIR="/opt/radio-orania/installer"

if [ "$REPO_DIR" = "$INSTALLER_DIR" ]; then
    progress 100 "Installer is reeds op sy plek"
    exit 0
fi

progress 20 "Skep installer-kopie"

rm -rf "$INSTALLER_DIR"
mkdir -p "$INSTALLER_DIR"

progress 50 "Kopieer lêers"

cp -a "$REPO_DIR/." "$INSTALLER_DIR/"

rm -f "$INSTALLER_DIR/installer.log"
rm -f "$INSTALLER_DIR/config/environment.conf"

progress 80 "Stel eienaarskap"

chown -R root:root "$INSTALLER_DIR"
chmod -R go-w "$INSTALLER_DIR"

progress 100 "Klaar"
