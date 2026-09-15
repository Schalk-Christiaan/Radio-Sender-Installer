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

    FETCH_ERR=$(mktemp)
    trap 'rm -f "$FETCH_ERR"' EXIT

    if git -C "$INSTALLER_DIR" fetch origin main >"$FETCH_ERR" 2>&1; then

        # Waarsku eksplisiet as origin/main intussen (tussen aflaai en
        # hierdie installasie) verder beweeg het as wat werklik afgelaai
        # is - anders sou die reset hieronder die volgehoue kopie
        # stilweg na 'n ander weergawe verander as wat sopas geïnstalleer
        # is, sonder dat die operateur dit ooit sien.
        #
        # "add -N" (intent-to-add) merk die ongespoorde lêers vir diff
        # sonder om enige blob te skryf, en "diff --quiet" self skryf
        # niks nie - lees-alleen, i.p.v. add -A/write-tree wat die hele
        # boom (weer) as voorwerpe stoor net om 'n ja/nee-vraag te
        # beantwoord. Albei staan in 'n if-voorwaarde, so 'n mislukking
        # (bv. skyf vol) laat "set -e" nie die hele installasie faal
        # oor hierdie suiwer inligtingskontrole nie.
        if git -C "$INSTALLER_DIR" add -N -A 2>/dev/null &&
           ! git -C "$INSTALLER_DIR" diff --quiet origin/main -- . 2>/dev/null; then
            warn "origin/main het intussen verander sedert die aflaai - die volgehoue kopie by $INSTALLER_DIR (vir 'radioctl update'/'reconfigure') word na daardie jongste weergawe opgedateer, nie noodwendig presies wat sopas geïnstalleer is nie."
        fi

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
        warn "kon nie git-geskiedenis by $INSTALLER_DIR opstel nie:"
        FETCH_ERR_INDENTED=$(sed 's/^/  /' "$FETCH_ERR")
        echo "$FETCH_ERR_INDENTED"
        { echo "$FETCH_ERR_INDENTED"; } 2>/dev/null > /dev/tty || true
        warn "Die huidige installasie is nie geraak nie, maar 'radioctl update' sal nie outomaties werk nie totdat die repo handmatig weer afgelaai word (sien README)."
        rm -rf "$INSTALLER_DIR/.git"
    fi

    rm -f "$FETCH_ERR"
    trap - EXIT

fi

progress 90 "Stel eienaarskap"

chown -R root:root "$INSTALLER_DIR"
chmod -R go-w "$INSTALLER_DIR"

progress 100 "Klaar"
