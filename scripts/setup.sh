#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"

source "$SCRIPT_DIR/ui.sh"

DEFAULT_STATION_NAME="Radio Orania"
DEFAULT_MUSIC_WEIGHT="4"
DEFAULT_SWEEPER_WEIGHT="1"
DEFAULT_RESTART_SCHEDULE="06:30 13:30"

#
# Validering
#
# Waardes hieronder word later in gegenereerde skripte en in
# environment.conf geskryf. Ons weier gevaarlike karakters (aanhalingstekens,
# backticks, $ en ;) sodat 'n kwaadwillige of tikfout-waarde nooit as
# shell-kode uitgevoer kan word nie, ongeag hoe dit later gebruik word.
# Spasies word wel toegelaat vir vrye-teks velde soos die sender naam.
#

contains_shell_metachars() {
    case "$1" in
        *[\"\'\`\;\\\$]*) return 0 ;;
    esac
    return 1
}

contains_unsafe_chars() {
    contains_shell_metachars "$1" && return 0
    case "$1" in
        *[[:space:]]*) return 0 ;;
    esac
    return 1
}

validate_plain_text() {
    [ -n "$1" ] && ! contains_shell_metachars "$1"
}

validate_url() {
    [[ "$1" =~ ^https?:// ]] && ! contains_unsafe_chars "$1"
}

validate_host() {
    [[ "$1" =~ ^[A-Za-z0-9.:-]+$ ]]
}

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

validate_token() {
    [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
}

validate_positive_int() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ]
}

#
# Toetse
#

# test_stream <url> -> 0 = klank ontvang, 1 = nie, 2 = nie getoets nie.
# Stel STREAM_INFO. curl stop ná 8s (kode 28) - by 'n deurlopende stroom is
# dit die verwagte uitkoms; wat tel is HTTP 2xx en genoeg grepe ontvang.
test_stream() {

    local hdr out rc=0 code size ctype br

    if ! command -v curl >/dev/null 2>&1; then
        STREAM_INFO="curl ontbreek - nie getoets nie"
        return 2
    fi

    hdr=$(mktemp)
    out=$(curl -sS -L -m 8 -A "RadioOrania-installer" -D "$hdr" -o /dev/null \
        -w '%{http_code} %{size_download} %{content_type}' "$1" 2>/dev/null) || rc=$?
    read -r code size ctype <<<"$out"
    br=$(grep -i '^icy-br:' "$hdr" | tail -1 | tr -dc '0-9,' | cut -d, -f1)
    rm -f "$hdr"

    if [[ "${code:-}" =~ ^2 ]] && [ "${size:-0}" -gt 4096 ]; then
        STREAM_INFO="${ctype%%;*}${br:+, $br kbps}, $((size / 1024)) KB in 8s"
        return 0
    fi

    if [ "${code:-000}" = "000" ]; then
        STREAM_INFO="geen verbinding (curl kode $rc)"
    elif [[ "$code" =~ ^2 ]]; then
        STREAM_INFO="bediener antwoord, maar stuur geen klank nie"
    else
        STREAM_INFO="HTTP $code"
    fi

    return 1
}

# ask_stream_url <vraag> <verstek> <opsioneel yes/no> -> ASKED_URL
ask_stream_url() {

    local url ans rc

    while true; do

        read -rp "$(ui_q "$1" "$2")" url
        url=${url:-$2}

        if [ -z "$url" ] && [ "$3" = yes ]; then
            ASKED_URL=""
            return
        fi

        if ! validate_url "$url"; then
            ui_fail "URL moet met http:// of https:// begin, sonder spasies, aanhalingstekens, \`, ;, \\ of \$."
            continue
        fi

        printf '  %s%s%s Toets stroom (8s)...' "$C_SEC" "${UI_SPIN[0]}" "$C_0"
        rc=0
        test_stream "$url" || rc=$?
        printf '\r\e[K'

        case "$rc" in
            0) ui_ok "Stroom werk: $STREAM_INFO" ;;
            2) ui_warn "$STREAM_INFO" ;;
            *)
                ui_fail "Geen klank ontvang: $STREAM_INFO"
                read -rp "$(ui_q "Tik weer (T) of gebruik dit tog (G)?" "T")" ans
                [[ "$ans" =~ ^[Gg]$ ]] || continue
                ;;
        esac

        ASKED_URL="$url"
        return
    done
}

# tone_test <toestel> -> 0 as die toon gespeel kon word (TONE_ERR anders).
tone_test() {

    local dev="${1/#hw:/plughw:}" out rc=0

    # 'n Vars kaart staan dikwels gedemp of op 0% - dan hoor jy niks al is
    # dit die regte kaart. volume.sh stel later die finale vlak.
    local card=0
    [[ "$1" =~ ^hw:([0-9]+) ]] && card="${BASH_REMATCH[1]}"
    amixer -q -c "$card" sset Master 80% unmute 2>/dev/null ||
        amixer -q -c "$card" sset PCM 80% unmute 2>/dev/null || true

    printf '  %s%s%s Speel toetstoon...' "$C_SEC" "${UI_SPIN[0]}" "$C_0"
    out=$(timeout 3 speaker-test -D "$dev" -c 2 -t sine -f 660 2>&1) || rc=$?
    printf '\r\e[K'

    if [ "$rc" -eq 0 ] || [ "$rc" -eq 124 ]; then
        return 0
    fi

    TONE_ERR=$(grep -im1 -E 'error|busy|no such|fout' <<<"$out" || echo "kode $rc")
    return 1
}

ui_banner_shown=false
[ -n "${UI_NO_BANNER:-}" ] && ui_banner_shown=true
[ "$ui_banner_shown" = true ] || ui_banner "Opstelling"

#
# Voorbereiding: aplay/speaker-test (alsa-utils) en curl kom eers by
# scripts/dependencies.sh, maar die assistent het hulle nou al nodig om
# klankkaarte op te lys/te toets en die stroom te toets.
#

if ! command -v aplay >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    ui_hint "Eers 'n paar hulpmiddels nodig (kan 'n minuut of twee neem)."
    ui_spin "Installeer alsa-utils en curl" "$SCRIPT_DIR/../installer.log" \
        bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq alsa-utils curl' ||
        ui_warn "Kon nie installeer nie - kaarte/stroom word nie getoets nie."
fi

#
# 1. Sender
#

ui_section 1 5 "Sender"

while true; do

    read -rp "$(ui_q "Sender naam" "$DEFAULT_STATION_NAME")" STATION_NAME
    STATION_NAME=${STATION_NAME:-$DEFAULT_STATION_NAME}

    if validate_plain_text "$STATION_NAME"; then
        break
    fi

    ui_fail "Sender naam mag nie aanhalingstekens, backticks, \$, ; of net spasies bevat nie."

done

#
# 2. Strome
#

ui_section 2 5 "Strome"

DEFAULT_STREAM_URL="https://stream.radio.co/s7adaa782c/listen"

ask_stream_url "Stroom URL" "$DEFAULT_STREAM_URL" no
STREAM_URL="$ASKED_URL"

echo
ui_hint "Rugsteun-stroom: gebruik as die hoofstroom wegval. Laat leeg om oor te slaan."
ask_stream_url "Rugsteun-stroom URL (opsioneel)" "" yes
BACKUP_STREAM_URL="$ASKED_URL"

echo
DEFAULT_STREAM_BUFFER_MAX="20"
ui_hint "Die helfte hiervan word vooraf gebuffer om netwerk-hikke te oorbrug;"
ui_hint "die maksimum keer dat FM-vertraging oor lang looptye opbou."

while true; do

    read -rp "$(ui_q "Maksimum stroom-buffer (sekondes)" "$DEFAULT_STREAM_BUFFER_MAX")" STREAM_BUFFER_MAX
    STREAM_BUFFER_MAX=${STREAM_BUFFER_MAX:-$DEFAULT_STREAM_BUFFER_MAX}

    if validate_positive_int "$STREAM_BUFFER_MAX"; then
        break
    fi

    ui_fail "Moet 'n positiewe heelgetal wees."

done

DEFAULT_SILENCE_THRESHOLD="20"
ui_hint "Praatprogramme het soms 10s+ pouses - te kort gee musiek-blippe."

while true; do

    read -rp "$(ui_q "Stilte voor oorskakel na noodmusiek (sekondes)" "$DEFAULT_SILENCE_THRESHOLD")" SILENCE_THRESHOLD
    SILENCE_THRESHOLD=${SILENCE_THRESHOLD:-$DEFAULT_SILENCE_THRESHOLD}

    if validate_positive_int "$SILENCE_THRESHOLD"; then
        break
    fi

    ui_fail "Moet 'n positiewe heelgetal wees."

done

#
# 3. Klank & noodmusiek
#

ui_section 3 5 "Klank & noodmusiek"

DEVICES=("default")
LABELS=("Stelsel-verstek")

card_re='^card ([0-9]+): [^[]*\[([^]]*)\], device ([0-9]+): [^[]*\[([^]]*)\]'

if command -v aplay >/dev/null 2>&1; then
    while IFS= read -r line; do
        if [[ "$line" =~ $card_re ]]; then
            DEVICES+=("hw:${BASH_REMATCH[1]},${BASH_REMATCH[3]}")
            LABELS+=("${BASH_REMATCH[2]}: ${BASH_REMATCH[4]}")
        fi
    done < <(aplay -l 2>/dev/null)
fi

DEFAULT_DEVICE_CHOICE=1
[ "${#DEVICES[@]}" -gt 1 ] && DEFAULT_DEVICE_CHOICE=2

RADIO_LIVE=false
systemctl is-active --quiet radio-orania 2>/dev/null && RADIO_LIVE=true

while true; do

    ui_hint "Klankkaart wat na die FM-sender gaan:"
    for i in "${!DEVICES[@]}"; do
        printf '    %s%d)%s %-9s %s%s%s\n' "$C_SEC" "$((i + 1))" "$C_0" \
            "${DEVICES[$i]}" "$C_DIM" "${LABELS[$i]}" "$C_0"
    done
    echo

    read -rp "$(ui_q "Kies toestel" "$DEFAULT_DEVICE_CHOICE")" DEVICE_CHOICE
    DEVICE_CHOICE=${DEVICE_CHOICE:-$DEFAULT_DEVICE_CHOICE}

    if ! [[ "$DEVICE_CHOICE" =~ ^[0-9]+$ ]] ||
       [ "$DEVICE_CHOICE" -lt 1 ] ||
       [ "$DEVICE_CHOICE" -gt "${#DEVICES[@]}" ]; then
        ui_fail "Ongeldige keuse."
        continue
    fi

    ALSA_DEVICE="${DEVICES[$((DEVICE_CHOICE - 1))]}"

    # Met die radio aan sou die toon (via "default"/dmix) op die lug gaan.
    if [ "$RADIO_LIVE" = true ]; then
        ui_hint "Die radio saai tans uit - toetstoon oorgeslaan."
        break
    fi

    if ! command -v speaker-test >/dev/null 2>&1; then
        break
    fi

    read -rp "$(ui_q "Speel 'n toetstoon op $ALSA_DEVICE? (Y/N)" "Y")" ans
    [[ "$ans" =~ ^[Nn]$ ]] && break

    if ! tone_test "$ALSA_DEVICE"; then
        ui_fail "Kon nie op $ALSA_DEVICE speel nie: $TONE_ERR"
        echo
        continue
    fi

    read -rp "$(ui_q "Hoor jy die toon? (Y/N)" "Y")" ans
    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
        ui_ok "Klankkaart $ALSA_DEVICE bevestig"
        break
    fi

    ui_hint "Kies 'n ander toestel, of kyk na die kabel en die volume."
    echo

done

echo
ui_hint "Noodmusiek: hoeveel liedjies per sweeper (bv. 4 en 1 = 4 liedjies, dan 'n sweeper)."

while true; do

    read -rp "$(ui_q "Musiek gewig" "$DEFAULT_MUSIC_WEIGHT")" MUSIC_WEIGHT
    MUSIC_WEIGHT=${MUSIC_WEIGHT:-$DEFAULT_MUSIC_WEIGHT}

    if validate_positive_int "$MUSIC_WEIGHT"; then
        break
    fi

    ui_fail "Musiek gewig moet 'n positiewe heelgetal wees."

done

while true; do

    read -rp "$(ui_q "Sweeper gewig" "$DEFAULT_SWEEPER_WEIGHT")" SWEEPER_WEIGHT
    SWEEPER_WEIGHT=${SWEEPER_WEIGHT:-$DEFAULT_SWEEPER_WEIGHT}

    if validate_positive_int "$SWEEPER_WEIGHT"; then
        break
    fi

    ui_fail "Sweeper gewig moet 'n positiewe heelgetal wees."

done

#
# 4. Kennisgewings (ntfy)
#

ui_section 4 5 "Kennisgewings"

ui_hint "ntfy-kennisgewings by netwerk-/bron-oorskakeling en as die radio-diens afgaan."
ui_hint "Volle topic-URL, bv. https://ntfy.sh/radio-orania-xyz. Laat leeg om af te skakel."

while true; do

    read -rp "$(ui_q "ntfy topic-URL (opsioneel)")" NTFY_URL

    if [ -z "$NTFY_URL" ] || validate_url "$NTFY_URL"; then
        break
    fi

    ui_fail "URL moet met http:// of https:// begin en geen aanhalingstekens bevat nie."

done

NTFY_TOKEN=""
NOTIFY_MODEM_REMINDER="60"

if [ -n "$NTFY_URL" ]; then

    while true; do

        read -rp "$(ui_q "ntfy toegangs-token (opsioneel, net vir 'n beskermde topic)")" NTFY_TOKEN

        if [ -z "$NTFY_TOKEN" ] || validate_token "$NTFY_TOKEN"; then
            break
        fi

        ui_fail "Token mag net letters, syfers, _ en - bevat."

    done

    while true; do

        read -rp "$(ui_q "Herinner elke hoeveel minute solank op die modem (0 = af)" "60")" NOTIFY_MODEM_REMINDER
        NOTIFY_MODEM_REMINDER=${NOTIFY_MODEM_REMINDER:-60}

        if [[ "$NOTIFY_MODEM_REMINDER" =~ ^[0-9]+$ ]]; then
            break
        fi

        ui_fail "Moet 'n heelgetal wees (0 of meer)."

    done

fi

#
# 5. Ekstras
#

ui_section 5 5 "Ekstras"

read -rp "$(ui_q "Installeer File Browser (media oplaai via webblaaier)? (Y/N)" "Y")" FB

if [[ ! "$FB" =~ ^[Nn]$ ]]; then

    INSTALL_FILEBROWSER="yes"

    while true; do
        read -rp "$(ui_q "  File Browser adres" "0.0.0.0")" FILEBROWSER_ADDRESS
        FILEBROWSER_ADDRESS=${FILEBROWSER_ADDRESS:-0.0.0.0}

        if validate_host "$FILEBROWSER_ADDRESS"; then
            break
        fi

        ui_fail "Ongeldige adres."
    done

    while true; do
        read -rp "$(ui_q "  File Browser poort" "8081")" FILEBROWSER_PORT
        FILEBROWSER_PORT=${FILEBROWSER_PORT:-8081}

        if validate_port "$FILEBROWSER_PORT"; then
            break
        fi

        ui_fail "Poort moet 'n getal tussen 1 en 65535 wees."
    done

else

    INSTALL_FILEBROWSER="no"

    FILEBROWSER_ADDRESS="0.0.0.0"
    FILEBROWSER_PORT="8081"

fi

echo
read -rp "$(ui_q "Installeer outo-restart timer? (Y/N)" "N")" RESTART_TIMER

if [[ "$RESTART_TIMER" =~ ^[Yy]$ ]]; then

    INSTALL_RESTART_TIMER="yes"

    while true; do

        read -rp "$(ui_q "  Restart tye (spasie-geskei)" "$DEFAULT_RESTART_SCHEDULE")" RESTART_SCHEDULE
        RESTART_SCHEDULE=${RESTART_SCHEDULE:-$DEFAULT_RESTART_SCHEDULE}

        VALID_SCHEDULE=true

        for slot in $RESTART_SCHEDULE; do
            if [[ ! "$slot" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                VALID_SCHEDULE=false
                break
            fi
        done

        if [ "$VALID_SCHEDULE" = true ]; then
            break
        fi

        ui_fail "Gebruik 24-uur tye soos 06:30 13:30"

    done

else

    INSTALL_RESTART_TIMER="no"
    RESTART_SCHEDULE="$DEFAULT_RESTART_SCHEDULE"

fi

echo
read -rp "$(ui_q "Installeer beheerpaneel-skerm (radio-admin, SSH + fisiese skerm)? (Y/N)" "N")" DASHBOARD

if [[ "$DASHBOARD" =~ ^[Yy]$ ]]; then
    INSTALL_DASHBOARD="yes"
    ICECAST_PORT="8008"
    ICECAST_SOURCE_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
else
    INSTALL_DASHBOARD="no"
    ICECAST_PORT="8008"
    ICECAST_SOURCE_PASSWORD=""
fi

echo
read -rp "$(ui_q "Oorskakel na 'n LTE-modem-stokkie as die internet afgaan? (Y/N)" "N")" MODEM

if [[ "$MODEM" =~ ^[Yy]$ ]]; then

    INSTALL_MODEM_FAILOVER="yes"

    read -rp "$(ui_q "  Primêre netwerk - ethernet of modem?" "ethernet")" PRIMARY_NETWORK
    PRIMARY_NETWORK=${PRIMARY_NETWORK:-ethernet}

    case "$PRIMARY_NETWORK" in
        ethernet|modem) ;;
        *) PRIMARY_NETWORK="ethernet" ;;
    esac

    while true; do

        read -rp "$(ui_q "  Sekondes onstabiel voor oorskakel" "60")" NETWORK_FAILOVER_DELAY
        NETWORK_FAILOVER_DELAY=${NETWORK_FAILOVER_DELAY:-60}

        if validate_positive_int "$NETWORK_FAILOVER_DELAY"; then
            break
        fi

        ui_fail "Moet 'n positiewe heelgetal wees."

    done

else
    INSTALL_MODEM_FAILOVER="no"
    PRIMARY_NETWORK="ethernet"
    NETWORK_FAILOVER_DELAY="60"
fi

#
# Opsomming
#

ui_section "Opsomming"

yes_no() { if [ "$1" = "yes" ]; then printf '%s%s%s Ja' "$C_OK" "$UI_OK" "$C_0"; else printf '%s- Nee%s' "$C_DIM" "$C_0"; fi; }
not_set() { printf '%sNie ingestel%s' "$C_DIM" "$C_0"; }

ui_kv "Sender naam" "$C_B$STATION_NAME$C_0"
ui_kv "Stroom" "$STREAM_URL"
ui_kv "Rugsteun-stroom" "${BACKUP_STREAM_URL:-$(not_set)}"
ui_kv "Stroom-buffer" "${STREAM_BUFFER_MAX}s"
ui_kv "Stilte-drempel" "${SILENCE_THRESHOLD}s"
ui_kv "Klankkaart" "$ALSA_DEVICE"
ui_kv "Musiek : sweeper" "$MUSIC_WEIGHT : $SWEEPER_WEIGHT"

if [ -n "$NTFY_URL" ]; then
    ui_kv "ntfy" "$NTFY_URL  (modem-herinnering ${NOTIFY_MODEM_REMINDER} min)"
else
    ui_kv "ntfy" "$(not_set)"
fi

if [ "$INSTALL_FILEBROWSER" = "yes" ]; then
    ui_kv "File Browser" "$(yes_no yes)  $FILEBROWSER_ADDRESS:$FILEBROWSER_PORT"
else
    ui_kv "File Browser" "$(yes_no no)"
fi

if [ "$INSTALL_RESTART_TIMER" = "yes" ]; then
    ui_kv "Outo-restart" "$(yes_no yes)  $RESTART_SCHEDULE"
else
    ui_kv "Outo-restart" "$(yes_no no)"
fi

ui_kv "Beheerpaneel" "$(yes_no "$INSTALL_DASHBOARD")"

if [ "$INSTALL_MODEM_FAILOVER" = "yes" ]; then
    ui_kv "Modem-failover" "$(yes_no yes)  primêr: $PRIMARY_NETWORK, ${NETWORK_FAILOVER_DELAY}s"
else
    ui_kv "Modem-failover" "$(yes_no no)"
fi

echo

read -rp "$(ui_q "Stoor konfigurasie? (Y/N)")" CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo
    ui_warn "Opstelling gekanselleer."
    exit 1
fi

#
# Skep config gids
#

mkdir -p "$CONFIG_DIR"

#
# Interne waardes
#

PLAYLIST_RELOAD="1000"
PLAYLIST_PREFETCH="10"

#
# Skryf environment.conf
#
# Elke waarde word met printf %q veilig ge-kwoteer voordat dit geskryf word,
# sodat 'n waarde met spesiale karakters nooit as bykomende shell-opdragte
# uitgevoer kan word wanneer die lêer later ge-`source` word (as root).
#

{
    printf '%s=%q\n' STATION_NAME "$STATION_NAME"
    echo
    printf '%s=%q\n' STREAM_URL "$STREAM_URL"
    printf '%s=%q\n' BACKUP_STREAM_URL "$BACKUP_STREAM_URL"
    echo
    printf '%s=%q\n' ALSA_DEVICE "$ALSA_DEVICE"
    echo
    printf '%s=%q\n' MUSIC_WEIGHT "$MUSIC_WEIGHT"
    printf '%s=%q\n' SWEEPER_WEIGHT "$SWEEPER_WEIGHT"
    echo
    printf '%s=%q\n' STREAM_BUFFER_MAX "$STREAM_BUFFER_MAX"
    printf '%s=%q\n' SILENCE_THRESHOLD "$SILENCE_THRESHOLD"
    echo
    printf '%s=%q\n' PLAYLIST_RELOAD "$PLAYLIST_RELOAD"
    printf '%s=%q\n' PLAYLIST_PREFETCH "$PLAYLIST_PREFETCH"
    echo
    printf '%s=%q\n' NTFY_URL "$NTFY_URL"
    printf '%s=%q\n' NTFY_TOKEN "$NTFY_TOKEN"
    printf '%s=%q\n' NOTIFY_MODEM_REMINDER "$NOTIFY_MODEM_REMINDER"
    echo
    printf '%s=%q\n' INSTALL_FILEBROWSER "$INSTALL_FILEBROWSER"
    echo
    printf '%s=%q\n' FILEBROWSER_ADDRESS "$FILEBROWSER_ADDRESS"
    printf '%s=%q\n' FILEBROWSER_PORT "$FILEBROWSER_PORT"
    echo
    printf '%s=%q\n' INSTALL_RESTART_TIMER "$INSTALL_RESTART_TIMER"
    printf '%s=%q\n' RESTART_SCHEDULE "$RESTART_SCHEDULE"
    echo
    printf '%s=%q\n' INSTALL_DASHBOARD "$INSTALL_DASHBOARD"
    printf '%s=%q\n' ICECAST_PORT "$ICECAST_PORT"
    printf '%s=%q\n' ICECAST_SOURCE_PASSWORD "$ICECAST_SOURCE_PASSWORD"
    echo
    printf '%s=%q\n' INSTALL_MODEM_FAILOVER "$INSTALL_MODEM_FAILOVER"
    printf '%s=%q\n' PRIMARY_NETWORK "$PRIMARY_NETWORK"
    printf '%s=%q\n' NETWORK_FAILOVER_DELAY "$NETWORK_FAILOVER_DELAY"
} > "$CONFIG_DIR/environment.conf"

echo
ui_ok "Konfigurasie gestoor: $CONFIG_DIR/environment.conf"
