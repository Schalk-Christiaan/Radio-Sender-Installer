#!/bin/bash

# Loop as root (nodig vir "ip route"/"nmcli"), begin deur
# radio-network-watchdog.service. Toets elke koppelvlak se eie
# bereikbaarheid direk (--interface), ongeag watter roete tans as
# verstek geld - so hoef ons nooit die werkende roete net om te toets
# te verwyder nie (wat 'n regte onderbreking sou veroorsaak terwyl die
# ander koppelvlak reeds in gebruik is).

source /opt/radio-orania/config/environment.conf

CHECK_URL="https://1.1.1.1"
CHECK_INTERVAL=20
STATUS_FILE="/opt/radio-orania/network/active_network"

# Watter koppelvlak eerste probeer word: "ethernet" (verstek) of
# "modem". radioctl se "set PRIMARY_NETWORK" valideer die waarde;
# enigiets anders as presies "modem" word hier as "ethernet" behandel.
PRIMARY_NETWORK="${PRIMARY_NETWORK:-ethernet}"

# Wag-tydperk (hysteresis) teen "flapping" - 'n wisselvallige verbinding
# (aan-af-aan-af) moet nie elke 20s 'n regte oorskakeling veroorsaak
# nie. Vereis eers 'n paar OPEENVOLGENDE mislukkings voor daar na die
# ander koppelvlak oorgeskakel word, en 'n paar opeenvolgende suksesse
# voor daar teruggeskakel word.
FAIL_THRESHOLD=3
RECOVER_THRESHOLD=3

# Roete-metric wanneer 'n koppelvlak AKTIEF in gebruik is (moet laag
# genoeg wees om verkies te word), en wanneer dit slegs batig staan
# (moet HOOG genoeg wees om NOOIT per ongeluk voor die aktiewe
# koppelvlak verkies te word nie).
ACTIVE_METRIC=50
IDLE_METRIC=4000

ETH_IFACE=$(awk '/^iface/ && $2 != "lo" {print $2; exit}' /etc/network/interfaces 2>/dev/null)

write_status() {
    mkdir -p "$(dirname "$STATUS_FILE")"
    printf '%s' "$1" > "${STATUS_FILE}.tmp"
    mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
}

iface_reachable() {
    local iface="$1"
    [ -n "$iface" ] || return 1
    curl -fsS --max-time 6 --interface "$iface" -o /dev/null "$CHECK_URL" 2>/dev/null
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

set_iface_metric() {
    local iface="$1" metric="$2" gw existing_metrics m

    gw=$(ip route show default dev "$iface" 2>/dev/null | grep -oP '(?<=via )\S+' | head -1)

    # "ip route replace" vervang net 'n roete met DIESELFDE metric - dit
    # sou 'n bestaande (dalk laer) verstek-roete vir hierdie toestel NIE
    # oorskryf nie, net 'n bykomende een langsaan skep, en die kern
    # verkies steeds die laagste metric van die twee. Verwyder dus eers
    # elke bestaande verstek-roete vir hierdie toestel, ongeag watter
    # metric dit tans het.
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

# Die bekabelde koppelvlak (ifupdown) is altyd reeds opgestel en
# benodig nie hierdie stap nie - net 'n NetworkManager-bestuurde
# modem-verbinding moet eers eksplisiet geaktiveer word.
activate_if_needed() {
    local iface="$1"
    [ "$iface" = "$ETH_IFACE" ] && return 0
    local conn
    conn=$(get_connection_for_device "$iface")
    if [ -n "$conn" ]; then
        nmcli connection up "$conn" >/dev/null 2>&1 || true
    fi
}

label_for() {
    local iface="$1"
    if [ "$iface" = "$ETH_IFACE" ]; then
        echo "Ethernet"
    else
        echo "Modem"
    fi
}

current_is_primary=true
fail_count=0
success_count=0

while true; do

    MODEM_DEV=$(get_modem_device)

    if [ "$PRIMARY_NETWORK" = "modem" ]; then
        PRIMARY_DEV="$MODEM_DEV"
        SECONDARY_DEV="$ETH_IFACE"
    else
        PRIMARY_DEV="$ETH_IFACE"
        SECONDARY_DEV="$MODEM_DEV"
    fi

    if iface_reachable "$PRIMARY_DEV"; then
        fail_count=0
        success_count=$((success_count + 1))
    else
        success_count=0
        fail_count=$((fail_count + 1))
    fi

    # Oorskakel net wanneer die drempel bereik is - 'n enkele
    # mislukte/suksesvolle toets alleen verander niks nie, dít voorkom
    # die heen-en-weer-"flap" by 'n wisselvallige verbinding.
    if [ "$current_is_primary" = true ] && [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
        current_is_primary=false
    elif [ "$current_is_primary" = false ] && [ "$success_count" -ge "$RECOVER_THRESHOLD" ]; then
        current_is_primary=true
    fi

    if [ "$current_is_primary" = true ]; then
        ACTIVE_DEV="$PRIMARY_DEV"
        IDLE_DEV="$SECONDARY_DEV"
    else
        ACTIVE_DEV="$SECONDARY_DEV"
        IDLE_DEV="$PRIMARY_DEV"
    fi

    if [ -z "$ACTIVE_DEV" ]; then
        write_status "Aflyn (geen bruikbare koppelvlak nie)"
    else
        activate_if_needed "$ACTIVE_DEV"
        set_iface_metric "$ACTIVE_DEV" "$ACTIVE_METRIC"
        [ -n "$IDLE_DEV" ] && set_iface_metric "$IDLE_DEV" "$IDLE_METRIC"
        write_status "$(label_for "$ACTIVE_DEV")"
    fi

    sleep "$CHECK_INTERVAL"

done
