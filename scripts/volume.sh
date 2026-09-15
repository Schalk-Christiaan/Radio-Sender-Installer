#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

progress 20 "Bepaal klankkaart"

# ALSA_DEVICE is "default" of "hw:N,0" - die mengertjie ("Master") sit op
# die onderliggende kaart N, nie op "default" self nie.
CARD=0

if [[ "${ALSA_DEVICE:-default}" =~ ^(plug)?hw:([0-9]+) ]]; then
    CARD="${BASH_REMATCH[2]}"
fi

progress 50 "Stel volume"

# Nie elke kaart het 'n "Master"-mengertjie nie - val terug na "PCM" as
# dit ontbreek, i.p.v. met 'n fout te breek en die res van 'n
# installasie/"radioctl set" te laat misluk.
if command -v amixer >/dev/null 2>&1; then

    if amixer -c "$CARD" sget Master >/dev/null 2>&1; then
        amixer -c "$CARD" sset Master "${VOLUME:-100}%" unmute >/dev/null
    elif amixer -c "$CARD" sget PCM >/dev/null 2>&1; then
        amixer -c "$CARD" sset PCM "${VOLUME:-100}%" unmute >/dev/null
    else
        echo "Waarskuwing: geen 'Master'- of 'PCM'-mengertjie op kaart $CARD gevind nie; volume nie gestel nie."
    fi

else
    echo "Waarskuwing: amixer nie geïnstalleer nie; volume nie gestel nie."
fi

progress 80 "Bewaar volume oor herbegin"

if command -v alsactl >/dev/null 2>&1; then
    alsactl store >/dev/null 2>&1 || true
fi

progress 100 "Klaar"
