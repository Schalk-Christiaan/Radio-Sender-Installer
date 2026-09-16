#!/bin/bash

# Loop as root (nodig vir "ip route"/"nmcli"), begin deur
# radio-network-watchdog.service. Toets die BEKABELDE koppelvlak se eie
# bereikbaarheid direk (--interface), ongeag watter roete tans as
# verstek geld - so hoef ons nooit die werkende roete net om te toets
# te verwyder nie (wat 'n regte onderbreking sou veroorsaak terwyl die
# modem reeds in gebruik is).

CHECK_URL="https://1.1.1.1"
CHECK_INTERVAL=20
STATUS_FILE="/opt/radio-orania/network/active_network"

ETH_IFACE=$(awk '/^iface/ && $2 != "lo" {print $2; exit}' /etc/network/interfaces 2>/dev/null)

write_status() {
    mkdir -p "$(dirname "$STATUS_FILE")"
    printf '%s' "$1" > "${STATUS_FILE}.tmp"
    mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
}

eth_reachable() {
    [ -n "$ETH_IFACE" ] || return 1
    curl -fsS --max-time 6 --interface "$ETH_IFACE" -o /dev/null "$CHECK_URL" 2>/dev/null
}

get_gsm_connection() {
    nmcli -t -f TYPE,NAME connection show 2>/dev/null | awk -F: '$1 == "gsm" {print $2; exit}'
}

is_override_active() {
    ip route show default 2>/dev/null | grep -q "metric 50\b"
}

ensure_ethernet_default() {
    if is_override_active; then
        ip route del default metric 50 2>/dev/null || true
    fi
}

ensure_modem_default() {
    local gsm_conn gsm_iface gsm_gw

    gsm_conn=$(get_gsm_connection)
    [ -z "$gsm_conn" ] && return 1

    nmcli connection up "$gsm_conn" >/dev/null 2>&1 || true

    # "device status" (nie "connection show" se GENERAL.DEVICES-veld nie)
    # is die betroubaarste manier om die toestel agter 'n aktiewe
    # verbinding te vind.
    gsm_iface=$(nmcli -t -f DEVICE,CONNECTION device status 2>/dev/null | awk -F: -v conn="$gsm_conn" '$2 == conn {print $1; exit}')
    [ -z "$gsm_iface" ] && return 1

    gsm_gw=$(ip route show dev "$gsm_iface" 2>/dev/null | awk '/^default/ {print $3; exit}')

    if [ -n "$gsm_gw" ]; then
        ip route replace default via "$gsm_gw" dev "$gsm_iface" metric 50 2>/dev/null
    else
        ip route replace default dev "$gsm_iface" metric 50 2>/dev/null
    fi
}

while true; do

    if eth_reachable; then
        ensure_ethernet_default
        write_status "Ethernet"
    elif ensure_modem_default; then
        write_status "Modem"
    else
        write_status "Aflyn (geen modem beskikbaar nie)"
    fi

    sleep "$CHECK_INTERVAL"

done
