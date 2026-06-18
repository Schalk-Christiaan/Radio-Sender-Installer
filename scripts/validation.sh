#!/bin/bash

echo
echo "==================="
echo "Valideer stelsel..."
echo "==================="

source config/environment.conf

ERRORS=0
WARNINGS=0

ok() {
    echo "[OK] $1"
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

if [ -f config/environment.conf ]; then
    ok "environment.conf gevind"
else
    fail "environment.conf ontbreek"
fi

#
# Liquidsoap
#

if command -v liquidsoap >/dev/null 2>&1; then
    VERSION=$(liquidsoap --version | head -n1)
    ok "Liquidsoap: $VERSION"
else
    fail "Liquidsoap nie geïnstalleer nie"
fi

#
# radio.liq
#

if [ -f /opt/radio-orania/liquidsoap/radio.liq ]; then
    ok "radio.liq gevind"
else
    fail "radio.liq ontbreek"
fi

#
# Liquidsoap sintaks
#

if liquidsoap --check /opt/radio-orania/liquidsoap/radio.liq >/dev/null 2>&1; then
    ok "radio.liq sintaks geldig"
else
    fail "radio.liq sintaks fout"
fi

#
# Internet
#

if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
    ok "Internet verbinding"
else
    warn "Geen internet verbinding"
fi

#
# Stream URL
#

if curl -Is --max-time 10 "$STREAM_URL" >/dev/null 2>&1; then
    ok "Stream URL bereikbaar"
else
    warn "Stream URL antwoord nie"
fi

#
# Noodmusiek
#

if find /opt/radio-orania/emergency/Musiek -type f 2>/dev/null | grep -q .; then
    COUNT=$(find /opt/radio-orania/emergency/Musiek -type f | wc -l)
    ok "Noodmusiek gevind ($COUNT lêers)"
else
    warn "Geen noodmusiek gevind nie"
fi

#
# Sweepers
#

if find /opt/radio-orania/emergency/Sweepers -type f 2>/dev/null | grep -q .; then
    COUNT=$(find /opt/radio-orania/emergency/Sweepers -type f | wc -l)
    ok "Sweepers gevind ($COUNT lêers)"
else
    warn "Geen sweepers gevind nie"
fi

#
# ALSA toestel
#

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
# Skyfspasie
#

FREE=$(df -BG / | awk 'NR==2 {print $4}')

ok "Beskikbare skyfspasie: $FREE"

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