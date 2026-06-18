#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

echo
echo "==================="
echo "Valideer stelsel..."
echo "==================="

ERRORS=0
WARNINGS=0

QUIET_MODE=true

ok() {

    if [ "$QUIET_MODE" = false ]; then
        echo "[OK] $1"
    fi

}

warn() {
    echo "[WAARSKUWING] $1"
    WARNINGS=$((WARNINGS+1))
}

fail() {
    echo "[FOUT] $1"
    ERRORS=$((ERRORS+1))
}
echo

#
# Config
#

progress 10 "Konfigurasie"

if [ -f "$SCRIPT_DIR/../config/environment.conf" ]; then
    ok "environment.conf gevind"
else
    fail "environment.conf ontbreek"
fi

#
# Liquidsoap
#

progress 25 "Liquidsoap"

if command -v liquidsoap >/dev/null 2>&1; then
    VERSION=$(liquidsoap --version | head -n1)
    ok "Liquidsoap: $VERSION"
else
    fail "Liquidsoap nie geïnstalleer nie"
fi

if [ -f /opt/radio-orania/liquidsoap/radio.liq ]; then
    ok "radio.liq gevind"
else
    fail "radio.liq ontbreek"
fi

if liquidsoap --check /opt/radio-orania/liquidsoap/radio.liq >/dev/null 2>&1; then
    ok "radio.liq sintaks geldig"
else
    fail "radio.liq sintaks fout"
fi

#
# Netwerk
#

progress 40 "Netwerk"

if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
    ok "Internet verbinding"
else
    warn "Geen internet verbinding"
fi

if curl -Is --max-time 10 "$STREAM_URL" >/dev/null 2>&1; then
    ok "Stream URL bereikbaar"
else
    warn "Stream URL antwoord nie"
fi

#
# Media
#

progress 60 "Media"

if find /opt/radio-orania/media/Musiek -type f 2>/dev/null | grep -q .; then
    COUNT=$(find /opt/radio-orania/media/Musiek -type f | wc -l)
    ok "Musiek gevind ($COUNT lêers)"
else
    warn "Geen musiek gevind nie"
fi

if find /opt/radio-orania/media/Sweepers -type f 2>/dev/null | grep -q .; then
    COUNT=$(find /opt/radio-orania/media/Sweepers -type f | wc -l)
    ok "Sweepers gevind ($COUNT lêers)"
else
    warn "Geen sweepers gevind nie"
fi

#
# ALSA
#

progress 80 "ALSA"

if command -v aplay >/dev/null 2>&1; then

    if aplay -L | grep -q "$ALSA_DEVICE"; then
        ok "ALSA toestel gevind ($ALSA_DEVICE)"
    else
        warn "ALSA toestel nie gevind nie ($ALSA_DEVICE)"
    fi

else
    warn "aplay nie beskikbaar nie"
fi

#
# Service
#

progress 90 "Dienste"

if systemctl list-unit-files | grep -q radio-orania.service; then
    ok "radio-orania.service geïnstalleer"
else
    warn "radio-orania.service ontbreek"
fi

if systemctl is-enabled radio-orania >/dev/null 2>&1; then
    ok "Service geaktiveer"
else
    warn "Service nie geaktiveer nie"
fi

#
# Heartbeat
#

if [ -n "$HEARTBEAT_URL" ]; then
    ok "Heartbeat URL ingestel"
else
    warn "Heartbeat URL nie ingestel nie"
fi

#
# File Browser
#

if [ "$INSTALL_FILEBROWSER" = "yes" ]; then

    if command -v filebrowser >/dev/null 2>&1; then
        ok "File Browser geïnstalleer"
    else
        fail "File Browser ontbreek"
    fi

    if systemctl list-unit-files | grep -q filebrowser.service; then
        ok "File Browser diens gevind"
    else
        warn "File Browser diens ontbreek"
    fi

    if systemctl is-active filebrowser >/dev/null 2>&1; then
        ok "File Browser diens loop"
    else
        warn "File Browser diens loop nie"
    fi

    if ss -tln | grep -q ":$FILEBROWSER_PORT "; then
        ok "File Browser luister op poort $FILEBROWSER_PORT"
    else
        warn "File Browser luister nie op poort $FILEBROWSER_PORT nie"
    fi

fi

#
# Skyfspasie
#

FREE=$(df -BG / | awk 'NR==2 {print $4}')

ok "Beskikbare skyfspasie: $FREE"

progress 100 "Voltooi"

echo
echo "==================="

if [ "$ERRORS" -gt 0 ]; then

    echo "RESULTAAT: MISLUK"
    echo "$ERRORS fout(e), $WARNINGS waarskuwing(s)"
    echo "==================="

    exit 1

else

    echo "RESULTAAT: GESLAAG"
    echo "$WARNINGS waarskuwing(s)"
    echo "==================="

fi

echo