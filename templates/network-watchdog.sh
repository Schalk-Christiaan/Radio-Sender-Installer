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

# Roete-metric wanneer die modem AKTIEF in gebruik is (moet laer as
# ethernet s'n wees, sodat dit verkies word), en wanneer dit slegs
# batig staan (moet HOOG genoeg wees om NOOIT per ongeluk voor 'n
# werkende ethernet-verbinding verkies te word nie).
MODEM_METRIC_ACTIVE=50
MODEM_METRIC_IDLE=4000

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

# Enige nmcli-toestel wat gekoppel is, NIE die bekende bekabelde
# koppelvlak is nie, en nie 'n lus-/VPN-koppelvlak is nie, word as die
# modem beskou. LTE-stokkies verskyn dikwels doodgewoon as 'n
# USB-Ethernet-toestel (RNDIS/USB-tuistehering) - NIE noodwendig as 'n
# ModemManager "gsm"-tipe toestel nie - so ons filter doelbewus nie op
# toestel-tipe nie.
get_modem_device() {
    nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null | awk -F: -v eth="$ETH_IFACE" '
        $1 == eth { next }
        $2 == "loopback" || $2 == "wireguard" { next }
        $3 ~ /^connected/ { print $1; exit }
    '
}

get_connection_for_device() {
    nmcli -t -f DEVICE,CONNECTION device status 2>/dev/null | awk -F: -v dev="$1" '$1 == dev { print $2; exit }'
}

set_modem_metric() {
    local iface="$1" metric="$2" gw existing_metrics m

    gw=$(ip route show default dev "$iface" 2>/dev/null | grep -oP '(?<=via )\S+' | head -1)

    # "ip route replace" vervang net 'n roete met DIESELFDE metric - dit
    # sou NetworkManager se eie (dalk laer) verstek-roete vir hierdie
    # toestel NIE oorskryf nie, net 'n bykomende een langsaan skep, en
    # die kern verkies steeds die laagste metric van die twee. Verwyder
    # dus eers elke bestaande verstek-roete vir hierdie toestel,
    # ongeag watter metric dit tans het.
    existing_metrics=$(ip route show default dev "$iface" 2>/dev/null | grep -oP '(?<=metric )\d+')
    for m in $existing_metrics; do
        ip route del default dev "$iface" metric "$m" 2>/dev/null || true
    done
    # 'n verstek-roete heeltemal sonder 'n eksplisiete "metric"-woord
    # dra intern metric 0 - probeer ook daardie vorm verwyder.
    ip route del default dev "$iface" 2>/dev/null || true

    if [ -n "$gw" ]; then
        ip route replace default via "$gw" dev "$iface" metric "$metric" 2>/dev/null
    else
        ip route replace default dev "$iface" metric "$metric" 2>/dev/null
    fi
}

remove_modem_override() {
    ip route del default metric "$MODEM_METRIC_ACTIVE" 2>/dev/null || true
}

while true; do

    MODEM_DEV=$(get_modem_device)

    if eth_reachable; then

        remove_modem_override

        # Selfs sonder 'n regte failover moet die modem se EIE
        # (NetworkManager-geskepte) roete afgeskaal bly - party
        # stokkies se DHCP-metric is laer as ethernet s'n, wat sou
        # beteken verkeer stilweg via mobiele data loop al werk
        # ethernet perfek.
        if [ -n "$MODEM_DEV" ]; then
            set_modem_metric "$MODEM_DEV" "$MODEM_METRIC_IDLE"
        fi

        write_status "Ethernet"

    elif [ -n "$MODEM_DEV" ]; then

        MODEM_CONN=$(get_connection_for_device "$MODEM_DEV")
        if [ -n "$MODEM_CONN" ]; then
            nmcli connection up "$MODEM_CONN" >/dev/null 2>&1 || true
        fi
        set_modem_metric "$MODEM_DEV" "$MODEM_METRIC_ACTIVE"
        write_status "Modem"

    else
        write_status "Aflyn (geen modem beskikbaar nie)"
    fi

    sleep "$CHECK_INTERVAL"

done
