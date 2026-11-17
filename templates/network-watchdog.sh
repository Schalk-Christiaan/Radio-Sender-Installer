#!/bin/bash

# Loop as root (nodig vir "ip route"/"nmcli"), begin deur
# radio-network-watchdog.service. Toets elke koppelvlak se eie
# bereikbaarheid direk (--interface), ongeag watter roete tans as
# verstek geld - so hoef ons nooit die werkende roete net om te toets
# te verwyder nie (wat 'n regte onderbreking sou veroorsaak terwyl die
# ander koppelvlak reeds in gebruik is).

source /opt/radio-orania/config/environment.conf

# Twee onafhanklike teikens: een wat self afgaan, laat nie die lyn "af" lyk nie.
CHECK_URLS="https://1.1.1.1 https://8.8.8.8"
CHECK_INTERVAL=5
STATUS_FILE="/opt/radio-orania/network/active_network"

# Watter koppelvlak eerste probeer word: "ethernet" (verstek) of
# "modem". radioctl se "set PRIMARY_NETWORK" valideer die waarde;
# enigiets anders as presies "modem" word hier as "ethernet" behandel.
PRIMARY_NETWORK="${PRIMARY_NETWORK:-ethernet}"

# Wag-tydperk (hysteresis) teen "flapping" - 'n wisselvallige verbinding
# (aan-af-aan-af) moet nie elke toets-siklus (5s) 'n regte oorskakeling
# veroorsaak nie. NETWORK_FAILOVER_DELAY (sekondes, radioctl se "set
# NETWORK_FAILOVER_DELAY") bepaal hoe lank 'n koppelvlak onafgebroke
# onstabiel/stabiel moet wees voor daar (albei rigtings) oorgeskakel
# word - omgeskakel na 'n aantal 5s-toets-siklusse, afgerond op.
FAILOVER_CYCLES=$(( (${NETWORK_FAILOVER_DELAY:-60} + CHECK_INTERVAL - 1) / CHECK_INTERVAL ))
[ "$FAILOVER_CYCLES" -lt 1 ] && FAILOVER_CYCLES=1
FAIL_THRESHOLD="$FAILOVER_CYCLES"
RECOVER_THRESHOLD="$FAILOVER_CYCLES"

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
    local url
    for url in $CHECK_URLS; do
        curl -fsS --max-time 3 --interface "$iface" -o /dev/null "$url" 2>/dev/null && return 0
    done
    return 1
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

# Laaste bekende gateway per koppelvlak, bewaar op skyf sodat dit ook 'n
# herbegin van die watchdog oorleef.
GW_CACHE_DIR="/opt/radio-orania/network"

# Soek 'n gateway vir die koppelvlak. Volgorde: die huidige
# verstek-roete, dan die gesaghebbende bronne (NetworkManager vir die
# modem; dhcpcd - Debian 13 se ifupdown - of ouer dhclient vir
# ethernet; 'n statiese "gateway"-lyn in /etc/network/interfaces), en
# eers heel laaste die gebergde laaste bekende waarde.
# Sonder hierdie terugval het 'n roete wat een keer verlore geraak het
# (bv. terwyl die kabel uit was) 'n "default dev X scope link"-roete
# sonder gateway geword - wat op 'n gewone LAN nooit werk nie, sodat die
# koppelvlak vir altyd as onbereikbaar getoets het.
find_gateway() {
    local iface="$1" gw cache="$GW_CACHE_DIR/gw_$1"

    gw=$(ip route show default dev "$iface" 2>/dev/null | grep -oP '(?<=via )[0-9.]+' | head -1)
    if [ -z "$gw" ]; then
        gw=$(nmcli -g IP4.GATEWAY device show "$iface" 2>/dev/null | grep -oP '^[0-9.]+$' | head -1)
    fi
    if [ -z "$gw" ] && command -v dhcpcd >/dev/null 2>&1; then
        gw=$(dhcpcd -U "$iface" 2>/dev/null | grep -oP "^routers='?\K[0-9.]+" | head -1)
    fi
    if [ -z "$gw" ]; then
        gw=$(grep -ohP '(?<=option routers )[0-9.]+' "/var/lib/dhcp/dhclient.$iface.leases" /var/lib/dhcp/dhclient.leases 2>/dev/null | tail -1)
    fi
    if [ -z "$gw" ]; then
        gw=$(awk -v i="$iface" '$1 == "iface" { in_i = ($2 == i) } in_i && $1 == "gateway" { print $2; exit }' \
            /etc/network/interfaces /etc/network/interfaces.d/* 2>/dev/null)
    fi

    if [ -n "$gw" ]; then
        if [ "$(cat "$cache" 2>/dev/null)" != "$gw" ]; then
            mkdir -p "$GW_CACHE_DIR"
            printf '%s' "$gw" > "$cache"
        fi
    else
        gw=$(cat "$cache" 2>/dev/null)
    fi
    echo "$gw"
}

set_iface_metric() {
    local iface="$1" metric="$2" gw routes line m

    gw=$(find_gateway "$iface")

    # Geen gateway bekend nie en die koppelvlak is nie punt-tot-punt
    # (ppp/wwan) nie: 'n roete sonder gateway sal nie werk nie - los die
    # roetes van hierdie koppelvlak eerder heeltemal uit.
    if [ -z "$gw" ] && ! ip link show "$iface" 2>/dev/null | grep -q POINTOPOINT; then
        return 0
    fi

    routes=$(ip route show default dev "$iface" 2>/dev/null)

    # Reeds presies reg (een roete, regte gateway en metric): raak niks.
    if [ "$(printf '%s\n' "$routes" | grep -c .)" = 1 ] &&
       printf '%s' "$routes" | grep -qE "metric $metric( |\$)" &&
       { [ -z "$gw" ] || printf '%s' "$routes" | grep -q "via $gw "; }; then
        return 0
    fi

    # Voeg EERS die nuwe roete by en verwyder eers daarna die ou ene -
    # die omgekeerde volgorde het 'n gaping gelaat, en as die byvoeging
    # misluk het (bv. skakel af) was die koppelvlak heeltemal sonder roete.
    # "replace" vervang 'n bestaande roete met DIESELFDE metric (ook 'n
    # stukkende een sonder gateway).
    if [ -n "$gw" ]; then
        ip route replace default via "$gw" dev "$iface" metric "$metric" 2>/dev/null || return 0
    else
        ip route replace default dev "$iface" metric "$metric" 2>/dev/null || return 0
    fi

    # Verwyder elke ander verstek-roete vir hierdie toestel (ander
    # metric; 'n roete sonder "metric"-woord dra intern metric 0). Altyd
    # met 'n eksplisiete metric - sonder een sou "ip route del" dalk die
    # nuwe roete self tref.
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        m=$(printf '%s' "$line" | grep -oP '(?<=metric )\d+')
        m="${m:-0}"
        [ "$m" = "$metric" ] && continue
        ip route del default dev "$iface" metric "$m" 2>/dev/null || true
    done <<< "$routes"
}

# GEEN "nmcli connection up" hier nie: get_modem_device gee net 'n reeds
# gekoppelde toestel terug, en "up" op 'n aktiewe verbinding breek dit af
# en bou dit weer op (16-17 Nov: modem elke 5-10s afgesny, stroom weg).

label_for() {
    local iface="$1"
    if [ -z "$iface" ]; then
        echo "geen"
    elif [ "$iface" = "$ETH_IFACE" ]; then
        echo "Ethernet"
    else
        echo "Modem"
    fi
}

# --- Gestruktureerde netwerktoestand -----------------------------------
#
# NET_STATUS_FILE is die enigste plek wat sê hoe albei lyne en die modem
# lyk (sleutel=waarde); radioctl, die beheerpaneel-skerm en notify lees
# dit net. active_network (STATUS_FILE) bly vir ouer lesers.
NET_STATUS_FILE="/opt/radio-orania/network/status"

# Die rugsteunlyn word elke SECONDARY_EVERY siklusse (~30s) getoets, die
# modem-API elke MODEM_EVERY siklusse (~60s) gelees. Elke siklus sou bloot
# die primêre lyn se besluit vertraag wanneer die rugsteun dood is.
SECONDARY_EVERY=6
MODEM_EVERY=12

# json_get <json> <sleutel> - die ZTE-API gee plat {"k":"v",...}; geen jq nodig nie.
json_get() {
    printf '%s' "$1" | grep -oP "\"$2\":\"\K[^\"]*" | head -1
}

# read_modem_info <toestel> - skryf modem_*-reëls; niks as die modem nie
# antwoord nie.
# ponytail: net ZTE se goform-API (geen wagwoord nie); 'n Huawei
# HiLink-stokkie gee niks - voeg 'n tweede leser by as so een opdaag.
read_modem_info() {
    local dev="$1" gw json state sim rx tx
    gw=$(find_gateway "$dev")
    [ -n "$gw" ] || return 0
    json=$(curl -s --max-time 3 --interface "$dev" \
        -H "Referer: http://$gw/index.html" \
        "http://$gw/goform/goform_get_cmd_process?isTest=false&multi_data=1&cmd=modem_main_state,network_type,network_provider,signalbar,lte_rsrp,msisdn,monthly_rx_bytes,monthly_tx_bytes" \
        2>/dev/null)
    case "$json" in
        *modem_main_state*) ;;
        *) return 0 ;;
    esac

    state=$(json_get "$json" modem_main_state)
    case "$state" in
        modem_init_complete)                  sim="ok" ;;
        modem_sim_undetected|modem_undetected) sim="geen" ;;
        modem_waitpin|modem_waitpuk)          sim="pin" ;;
        *)                                    sim="${state:-onbekend}" ;;
    esac
    rx=$(json_get "$json" monthly_rx_bytes)
    tx=$(json_get "$json" monthly_tx_bytes)

    echo "modem_sim=$sim"
    echo "modem_net=$(json_get "$json" network_type)"
    echo "modem_provider=$(json_get "$json" network_provider)"
    echo "modem_bars=$(json_get "$json" signalbar)"
    echo "modem_rsrp=$(json_get "$json" lte_rsrp)"
    echo "modem_number=$(json_get "$json" msisdn)"
    echo "modem_month_mb=$(( (${rx:-0} + ${tx:-0}) / 1048576 ))"
}

write_net_status() {
    local active="$1" tmp="${NET_STATUS_FILE}.tmp"
    mkdir -p "$(dirname "$NET_STATUS_FILE")"
    {
        echo "active=$active"
        echo "primary=$(label_for "$PRIMARY_DEV")"
        echo "primary_ok=$primary_ok"
        echo "backup=$(label_for "$SECONDARY_DEV")"
        echo "backup_ok=$secondary_ok"
        [ -n "$modem_lines" ] && printf '%s\n' "$modem_lines"
        echo "updated=$(date +%s)"
    } > "$tmp"
    mv "$tmp" "$NET_STATUS_FILE"
}

pick_devices() {
    MODEM_DEV=$(get_modem_device)
    if [ "$PRIMARY_NETWORK" = "modem" ]; then
        PRIMARY_DEV="$MODEM_DEV"
        SECONDARY_DEV="$ETH_IFACE"
    else
        PRIMARY_DEV="$ETH_IFACE"
        SECONDARY_DEV="$MODEM_DEV"
    fi
}

probe() {
    if iface_reachable "$1"; then echo ja; else echo nee; fi
}

fail_count=0
success_count=0
cycle=0
modem_lines=""

# Begin-toestand uit 'n werklike toets, nie 'n aanname nie: anders kry
# 'n dooie primêre lyn (bv. PRIMARY_NETWORK=modem sonder SIM) ná elke
# herbegin al die verkeer totdat die drempel bereik is.
pick_devices
primary_ok=$(probe "$PRIMARY_DEV")
secondary_ok=$(probe "$SECONDARY_DEV")
if [ "$primary_ok" = nee ] && [ "$secondary_ok" = ja ]; then
    current_is_primary=false
else
    current_is_primary=true
fi

while true; do

    pick_devices

    primary_ok=$(probe "$PRIMARY_DEV")
    if [ "$primary_ok" = ja ]; then
        fail_count=0
        success_count=$((success_count + 1))
    else
        success_count=0
        fail_count=$((fail_count + 1))
    fi

    # Die rugsteunlyn: elke siklus terwyl dit aktief is, anders elke ~30s.
    if [ "$current_is_primary" = false ] || [ $(( cycle % SECONDARY_EVERY )) -eq 0 ]; then
        secondary_ok=$(probe "$SECONDARY_DEV")
    fi

    if [ -n "$MODEM_DEV" ]; then
        [ $(( cycle % MODEM_EVERY )) -eq 0 ] && modem_lines=$(read_modem_info "$MODEM_DEV")
    else
        modem_lines=""
    fi

    # Oorskakel net wanneer die drempel bereik is - 'n enkele
    # mislukte/suksesvolle toets alleen verander niks nie, dít voorkom
    # die heen-en-weer-"flap" by 'n wisselvallige verbinding. Skakel
    # boonop net oor na 'n rugsteunlyn wat self werk ("gekoppel" is nie
    # genoeg nie - die ZTE gee DHCP uit selfs sonder SIM), en gaan
    # dadelik terug as die rugsteun self wegval.
    if [ "$current_is_primary" = true ] && [ "$fail_count" -ge "$FAIL_THRESHOLD" ] &&
       [ "$secondary_ok" = ja ]; then
        current_is_primary=false
    elif [ "$current_is_primary" = false ] &&
         { [ "$success_count" -ge "$RECOVER_THRESHOLD" ] || [ "$secondary_ok" = nee ]; }; then
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
        active_label="Aflyn (geen bruikbare koppelvlak nie)"
    else
        set_iface_metric "$ACTIVE_DEV" "$ACTIVE_METRIC"
        [ -n "$IDLE_DEV" ] && set_iface_metric "$IDLE_DEV" "$IDLE_METRIC"
        active_label=$(label_for "$ACTIVE_DEV")
    fi
    write_status "$active_label"
    write_net_status "$active_label"

    cycle=$((cycle + 1))
    sleep "$CHECK_INTERVAL"

done
