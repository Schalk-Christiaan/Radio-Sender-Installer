#!/bin/bash

# Stuur ntfy-kennisgewings wanneer die sender van sy normale toestand
# afwyk (of daarna terugkeer): netwerk-oorskakeling, lank op die modem,
# bron-oorskakeling en die radio-diens wat af is. Begin deur
# radio-notify.service (as radio-orania). Beszel hou die masjien self
# dop (aanlyn/CPU/skyf); hierdie diens dek die radio-spesifieke dinge
# wat Beszel nie kan sien nie.

source /opt/radio-orania/config/environment.conf

ACTIVE_SOURCE_FILE="/opt/radio-orania/liquidsoap/active_source"
ACTIVE_NETWORK_FILE="/opt/radio-orania/network/active_network"

CHECK_INTERVAL=5

# Hoe lank 'n nuwe toestand onafgebroke moet geld voor daar 'n
# kennisgewing gestuur word - sluk kort hikke en die geskeduleerde
# herbegin (radio-diens is net 'n paar sekondes af) in.
STABLE_SECS=30

# Herinnering elke N minute solank die sender op die modem is (0 = af).
MODEM_REMINDER_MINS="${NOTIFY_MODEM_REMINDER:-60}"

STATION="${STATION_NAME:-Radio Orania}"

# Boodskappe wat nie gestuur kon word nie (bv. albei netwerke af) word
# in 'n tou gehou en weer probeer sodra daar weer internet is.
QUEUE=()
QUEUE_MAX=20

send_now() {
    local priority="$1" tags="$2" title="$3" message="$4"
    local args=(-fsS --max-time 10 -o /dev/null
        -H "Title: $title"
        -H "Priority: $priority"
        -H "Tags: $tags"
        -d "$message")
    [ -n "${NTFY_TOKEN:-}" ] && args+=(-H "Authorization: Bearer $NTFY_TOKEN")
    curl "${args[@]}" "$NTFY_URL" 2>/dev/null
}

# notify <prioriteit> <tags> <boodskap>
notify() {
    local stamp
    stamp=$(date '+%H:%M')
    QUEUE+=("$1"$'\x1f'"$2"$'\x1f'"$3 ($stamp)")
    if [ "${#QUEUE[@]}" -gt "$QUEUE_MAX" ]; then
        QUEUE=("${QUEUE[@]: -$QUEUE_MAX}")
    fi
    flush_queue
}

flush_queue() {
    local item priority tags message
    while [ "${#QUEUE[@]}" -gt 0 ]; do
        item="${QUEUE[0]}"
        IFS=$'\x1f' read -r priority tags message <<< "$item"
        send_now "$priority" "$tags" "$STATION" "$message" || return
        QUEUE=("${QUEUE[@]:1}")
    done
}

read_network() {
    [ -f "$ACTIVE_NETWORK_FILE" ] && cat "$ACTIVE_NETWORK_FILE" 2>/dev/null
}

read_source() {
    case "$(cat "$ACTIVE_SOURCE_FILE" 2>/dev/null)" in
        primer)     echo "Hoofstroom" ;;
        rugsteun)   echo "Rugsteun-stroom" ;;
        noodmusiek) echo "Noodmusiek" ;;
        *)          echo "" ;;
    esac
}

read_service() {
    if systemctl is-active --quiet radio-orania.service; then
        echo "aan"
    else
        echo "af"
    fi
}

# Elke gemonitorde waarde het 'n "gerapporteerde" toestand (waaroor laas
# 'n kennisgewing gegaan het), 'n "kandidaat" (die nuutste waarde) en
# wanneer die kandidaat begin geld het. Eers wanneer die kandidaat
# STABLE_SECS lank onveranderd bly, word dit gerapporteer.
declare -A reported candidate since

# check <naam> <huidige waarde> - gee 0 terug (en werk "reported" by)
# wanneer 'n stabiele verandering gerapporteer moet word.
check() {
    local name="$1" value="$2" now
    now=$(date +%s)

    if [ "$value" != "${candidate[$name]}" ]; then
        candidate[$name]="$value"
        since[$name]="$now"
    fi

    if [ "${candidate[$name]}" != "${reported[$name]}" ] &&
       [ $(( now - since[$name] )) -ge "$STABLE_SECS" ]; then
        PREVIOUS="${reported[$name]}"
        reported[$name]="${candidate[$name]}"
        return 0
    fi
    return 1
}

on_network_change() {
    local new="$1" old="$2"
    case "$new" in
        Ethernet) notify default "white_check_mark" "Terug op Ethernet (was: ${old:-onbekend})." ;;
        Modem)    notify high "warning" "Oorgeskakel na die MODEM - Ethernet het uitgeval. Die sender gebruik nou mobiele data." ;;
        "")       ;;
        *)        notify urgent "rotating_light" "Netwerk: $new" ;;
    esac
}

on_source_change() {
    local new="$1" old="$2"
    case "$new" in
        Hoofstroom)      notify default "white_check_mark" "Terug op die hoofstroom (was: ${old:-onbekend})." ;;
        Rugsteun-stroom) notify high "warning" "Oorgeskakel na die RUGSTEUN-stroom (was: ${old:-onbekend})." ;;
        Noodmusiek)      notify urgent "rotating_light" "Speel NOODMUSIEK - geen stroom bereikbaar nie (was: ${old:-onbekend})." ;;
    esac
}

on_service_change() {
    case "$1" in
        af)  notify urgent "rotating_light" "Die radio-diens is AF - daar gaan niks uit nie." ;;
        aan) notify default "white_check_mark" "Die radio-diens loop weer." ;;
    esac
}

# Begin-toestand: rapporteer dit een keer sodat 'n herlaai (of eerste
# installasie) sigbaar is, en sodat die eerste regte verandering 'n
# korrekte "was: ..." het.
reported[network]=$(read_network)
reported[source]=$(read_source)
reported[service]=$(read_service)
for n in network source service; do
    candidate[$n]="${reported[$n]}"
    since[$n]=$(date +%s)
done

start_msg="Kennisgewings aktief. Diens: ${reported[service]}"
[ -n "${reported[source]}" ] && start_msg="$start_msg, bron: ${reported[source]}"
[ -n "${reported[network]}" ] && start_msg="$start_msg, netwerk: ${reported[network]}"
notify low "radio" "$start_msg."

modem_since=""
[ "${reported[network]}" = "Modem" ] && modem_since=$(date +%s)
last_reminder=0

while true; do

    service=$(read_service)
    if check service "$service"; then
        on_service_change "$service"
    fi

    # Terwyl die diens af is, is die bron-lêer verouderd - moenie
    # daaroor rapporteer nie (die diens-kennisgewing dek dit reeds).
    if [ "$service" = "aan" ]; then
        source_now=$(read_source)
        if [ -n "$source_now" ] && check source "$source_now"; then
            on_source_change "$source_now" "$PREVIOUS"
        fi
    fi

    network=$(read_network)
    if check network "$network"; then
        on_network_change "$network" "$PREVIOUS"
        if [ "$network" = "Modem" ]; then
            modem_since=$(date +%s)
            last_reminder=$modem_since
        else
            modem_since=""
        fi
    fi

    if [ -n "$modem_since" ] && [ "$MODEM_REMINDER_MINS" -gt 0 ]; then
        now=$(date +%s)
        [ "$last_reminder" -eq 0 ] && last_reminder=$modem_since
        if [ $(( now - last_reminder )) -ge $(( MODEM_REMINDER_MINS * 60 )) ]; then
            notify high "hourglass" "Steeds op die MODEM - al $(( (now - modem_since) / 60 )) minute."
            last_reminder=$now
        fi
    fi

    flush_queue

    sleep "$CHECK_INTERVAL"

done
