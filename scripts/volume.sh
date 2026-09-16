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

# AUDIO_PORT laat die admin 'n spesifieke fisiese uitsetpoort kies (bv.
# "Line" i.p.v. "Front") - radioctl se "set AUDIO_PORT" valideer reeds
# dat die naam werklik op die kaart bestaan. Sonder AUDIO_PORT val ons
# terug op "Master", en daarna "PCM" - nie elke kaart het 'n
# "Master"-mengertjie nie, en dit moenie die res van 'n installasie/
# "radioctl set" laat misluk nie.
if command -v amixer >/dev/null 2>&1; then

    if [ -n "${AUDIO_PORT:-}" ] && amixer -c "$CARD" sget "$AUDIO_PORT" >/dev/null 2>&1; then
        amixer -c "$CARD" sset "$AUDIO_PORT" "${VOLUME:-100}%" unmute >/dev/null
    elif amixer -c "$CARD" sget Master >/dev/null 2>&1; then
        amixer -c "$CARD" sset Master "${VOLUME:-100}%" unmute >/dev/null
    elif amixer -c "$CARD" sget PCM >/dev/null 2>&1; then
        amixer -c "$CARD" sset PCM "${VOLUME:-100}%" unmute >/dev/null
    else
        warn "geen bruikbare mengertjie op kaart $CARD gevind nie; volume nie gestel nie."
    fi

else
    warn "amixer nie geïnstalleer nie; volume nie gestel nie."
fi

progress 80 "Bewaar volume oor herbegin"

if command -v alsactl >/dev/null 2>&1; then
    alsactl store >/dev/null 2>&1 || true
fi

progress 100 "Klaar"
