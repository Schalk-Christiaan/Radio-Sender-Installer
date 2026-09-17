#!/bin/bash

source /opt/radio-orania/config/environment.conf

# Uptime Kuma se "push"-monitor formaat: ?status=up|down&msg=...&ping=
# - status=down laat Kuma 'n kennisgewing stuur, sodat 'n operateur net
# opgelet word wanneer iets werklik van die norm afwyk (nie 'n stille
# ping wat altyd net "aanlyn" beteken nie).
BASE_PUSH_URL="${HEARTBEAT_URL%%\?*}"

ACTIVE_SOURCE_FILE="/opt/radio-orania/liquidsoap/active_source"
ACTIVE_NETWORK_FILE="/opt/radio-orania/network/active_network"

# Pure-bash persentasie-enkodering - vermy 'n bykomende afhanklikheid
# (jq/python) net vir hierdie een doel.
urlencode() {
    local string="$1" length=${#1} char i
    for (( i = 0; i < length; i++ )); do
        char="${string:i:1}"
        case "$char" in
            [a-zA-Z0-9.~_-]) printf '%s' "$char" ;;
            ' ') printf '%%20' ;;
            *) printf '%%%02X' "'$char" ;;
        esac
    done
}

while true; do

    systemctl is-active --quiet radio-orania.service || exit 1

    source_label="onbekend"
    if [ -f "$ACTIVE_SOURCE_FILE" ]; then
        case "$(cat "$ACTIVE_SOURCE_FILE" 2>/dev/null)" in
            primer)     source_label="Hoofstroom" ;;
            rugsteun)   source_label="Rugsteun-stroom" ;;
            noodmusiek) source_label="Noodmusiek" ;;
        esac
    fi

    network_label=""
    [ -f "$ACTIVE_NETWORK_FILE" ] && network_label=$(cat "$ACTIVE_NETWORK_FILE" 2>/dev/null)

    status="up"
    [ "$source_label" != "Hoofstroom" ] && status="down"
    [ -n "$network_label" ] && [ "$network_label" != "Ethernet" ] && status="down"

    message="$source_label"
    [ -n "$network_label" ] && message="${message} (${network_label})"

    curl \
        -fsS \
        -o /dev/null \
        "${BASE_PUSH_URL}?status=${status}&msg=$(urlencode "$message")&ping="

    sleep 5

done
