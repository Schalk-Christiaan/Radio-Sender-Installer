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

progress 70 "Stel git-koppeling op"

# 'n curl/tarball-installasie (README se aanbevole metode - vermy git/SSH/
# GitHub-aanmelding heeltemal) laat geen .git agter nie. Sonder hierdie
# stap sou "radioctl update" (wat op "git pull" staatmaak) altyd misluk.
# 'n git-kloon self het reeds .git - dan is hierdie stap 'n no-op.
if [ ! -d "$INSTALLER_DIR/.git" ] && command -v git >/dev/null 2>&1; then
    git -C "$INSTALLER_DIR" init -q
    git -C "$INSTALLER_DIR" remote add origin "https://github.com/Schalk-Christiaan/Radio-Sender-Installer.git"
    if git -C "$INSTALLER_DIR" fetch -q origin main 2>/dev/null; then
        # Die vouer bevat reeds die tarball se lêers (ongespoor) - koppel
        # dit direk aan "main" en dwing die indeks/werkboom om origin/main
        # te weerspieël, i.p.v. 'n gewone checkout wat kan kla oor
        # bestaande ongespoorde lêers.
        git -C "$INSTALLER_DIR" symbolic-ref HEAD refs/heads/main
        git -C "$INSTALLER_DIR" reset -q --hard origin/main
        # "radioctl update" loop 'n kaal "git pull --ff-only" - dit het
        # dié opstroom-opsporing nodig, wat "git init" (anders as "git
        # clone") nie self opstel nie.
        git -C "$INSTALLER_DIR" branch -q --set-upstream-to=origin/main main
    else
        rm -rf "$INSTALLER_DIR/.git"
    fi
fi

progress 90 "Stel eienaarskap"

chown -R root:root "$INSTALLER_DIR"
chmod -R go-w "$INSTALLER_DIR"

progress 100 "Klaar"
