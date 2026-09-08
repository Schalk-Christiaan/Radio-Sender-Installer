#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"

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

validate_positive_int() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ]
}

echo
echo "===================================="
echo " Radio Orania Sender Opstelling"
echo "===================================="
echo

#
# Sender Naam
#

while true; do

    read -rp "Sender Naam [$DEFAULT_STATION_NAME]: " STATION_NAME
    STATION_NAME=${STATION_NAME:-$DEFAULT_STATION_NAME}

    if validate_plain_text "$STATION_NAME"; then
        break
    fi

    echo "Sender naam mag nie aanhalingstekens, backticks, \$, ; of spasies-alleen bevat nie."

done

#
# Stream URL
#

DEFAULT_STREAM_URL="https://stream.radio.co/s7adaa782c/listen"

while true; do

    read -rp "Stroom URL [$DEFAULT_STREAM_URL]: " STREAM_URL

    STREAM_URL=${STREAM_URL:-$DEFAULT_STREAM_URL}

    if validate_url "$STREAM_URL"; then
        break
    fi

    echo "Stroom URL moet met http:// of https:// begin en geen aanhalingstekens bevat nie."

done

#
# Rugsteun-stroom URL
#

echo

while true; do

    read -rp "Rugsteun-stroom URL (opsioneel): " BACKUP_STREAM_URL

    if [ -z "$BACKUP_STREAM_URL" ] || validate_url "$BACKUP_STREAM_URL"; then
        break
    fi

    echo "Rugsteun-stroom URL moet met http:// of https:// begin en geen aanhalingstekens bevat nie."

done

#
# Gewigte
#

while true; do

    read -rp "Musiek gewig [$DEFAULT_MUSIC_WEIGHT]: " MUSIC_WEIGHT
    MUSIC_WEIGHT=${MUSIC_WEIGHT:-$DEFAULT_MUSIC_WEIGHT}

    if validate_positive_int "$MUSIC_WEIGHT"; then
        break
    fi

    echo "Musiek gewig moet 'n positiewe heelgetal wees."

done

while true; do

    read -rp "Sweeper gewig [$DEFAULT_SWEEPER_WEIGHT]: " SWEEPER_WEIGHT
    SWEEPER_WEIGHT=${SWEEPER_WEIGHT:-$DEFAULT_SWEEPER_WEIGHT}

    if validate_positive_int "$SWEEPER_WEIGHT"; then
        break
    fi

    echo "Sweeper gewig moet 'n positiewe heelgetal wees."

done

#
# ALSA Toestelle
#

echo
echo "Beskikbare ALSA toestelle:"
echo

DEVICES=("default")

if command -v aplay >/dev/null 2>&1; then

    while read -r line; do

        CARD=$(echo "$line" | sed -n 's/^card \([0-9]\+\).*/\1/p')

        if [ -n "$CARD" ]; then
            DEVICES+=("hw:${CARD},0")
        fi

    done < <(aplay -l 2>/dev/null)

fi

for i in "${!DEVICES[@]}"; do
    echo "$((i+1))) ${DEVICES[$i]}"
done

echo

while true; do

    read -rp "Kies toestel [1]: " DEVICE_CHOICE

    DEVICE_CHOICE=${DEVICE_CHOICE:-1}

    if [[ "$DEVICE_CHOICE" =~ ^[0-9]+$ ]] &&
       [ "$DEVICE_CHOICE" -ge 1 ] &&
       [ "$DEVICE_CHOICE" -le "${#DEVICES[@]}" ]; then

        ALSA_DEVICE="${DEVICES[$((DEVICE_CHOICE-1))]}"
        break

    fi

    echo "Ongeldige keuse."

done

#
# Stroom-buffer
#

echo

DEFAULT_STREAM_BUFFER_MAX="10"

while true; do

    read -rp "Maksimum stroom-buffer in sekondes (voorkom opbou van FM-vertraging by lang looptye) [$DEFAULT_STREAM_BUFFER_MAX]: " STREAM_BUFFER_MAX
    STREAM_BUFFER_MAX=${STREAM_BUFFER_MAX:-$DEFAULT_STREAM_BUFFER_MAX}

    if validate_positive_int "$STREAM_BUFFER_MAX"; then
        break
    fi

    echo "Moet 'n positiewe heelgetal wees."

done

#
# Heartbeat
#

echo

while true; do

    read -rp "Heartbeat URL (opsioneel): " HEARTBEAT_URL

    if [ -z "$HEARTBEAT_URL" ] || validate_url "$HEARTBEAT_URL"; then
        break
    fi

    echo "Heartbeat URL moet met http:// of https:// begin en geen aanhalingstekens bevat nie."

done

#
# File Browser
#

read -rp "Installeer File Browser? (Y/N) [Y]: " FB

if [[ ! "$FB" =~ ^[Nn]$ ]]; then

    INSTALL_FILEBROWSER="yes"

    echo

    while true; do
        read -rp "File Browser Adres [0.0.0.0]: " FILEBROWSER_ADDRESS
        FILEBROWSER_ADDRESS=${FILEBROWSER_ADDRESS:-0.0.0.0}

        if validate_host "$FILEBROWSER_ADDRESS"; then
            break
        fi

        echo "Ongeldige adres."
    done

    while true; do
        read -rp "File Browser Poort [8081]: " FILEBROWSER_PORT
        FILEBROWSER_PORT=${FILEBROWSER_PORT:-8081}

        if validate_port "$FILEBROWSER_PORT"; then
            break
        fi

        echo "Poort moet 'n getal tussen 1 en 65535 wees."
    done

else

    INSTALL_FILEBROWSER="no"

    FILEBROWSER_ADDRESS="0.0.0.0"
    FILEBROWSER_PORT="8081"

fi

#
# Outo-restart
#

echo
read -rp "Installeer outo-restart timer? (Y/N) [N]: " RESTART_TIMER

if [[ "$RESTART_TIMER" =~ ^[Yy]$ ]]; then

    INSTALL_RESTART_TIMER="yes"

    while true; do

        read -rp "Restart tye (spasie-geskei) [$DEFAULT_RESTART_SCHEDULE]: " RESTART_SCHEDULE
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

        echo "Gebruik 24-uur tye soos 06:30 13:30"

    done

    while true; do

        read -rp "Uptime Kuma Push URL (opsioneel): " RESTART_PUSH_URL

        if [ -z "$RESTART_PUSH_URL" ] || validate_url "$RESTART_PUSH_URL"; then
            break
        fi

        echo "Push URL moet met http:// of https:// begin en geen aanhalingstekens bevat nie."

    done

else

    INSTALL_RESTART_TIMER="no"
    RESTART_SCHEDULE="$DEFAULT_RESTART_SCHEDULE"
    RESTART_PUSH_URL=""

fi

#
# Beheerpaneel
#

echo
read -rp "Installeer beheerpaneel-skerm (radio-admin, SSH + fisiese skerm)? (Y/N) [N]: " DASHBOARD

if [[ "$DASHBOARD" =~ ^[Yy]$ ]]; then
    INSTALL_DASHBOARD="yes"
    ICECAST_PORT="8008"
    ICECAST_SOURCE_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
else
    INSTALL_DASHBOARD="no"
    ICECAST_PORT="8008"
    ICECAST_SOURCE_PASSWORD=""
fi

#
# Opsomming
#

echo
echo "===================================="
echo " Konfigurasie Opsomming"
echo "===================================="
echo

echo "Sender Naam      : $STATION_NAME"
echo "Stream URL       : $STREAM_URL"

if [ -n "$BACKUP_STREAM_URL" ]; then
    echo "Rugsteun Stream  : $BACKUP_STREAM_URL"
else
    echo "Rugsteun Stream  : Nie ingestel"
fi

echo "Musiek Gewig     : $MUSIC_WEIGHT"
echo "Sweeper Gewig    : $SWEEPER_WEIGHT"
echo "ALSA Device      : $ALSA_DEVICE"
echo "Stroom-buffer    : ${STREAM_BUFFER_MAX}s"

if [ -n "$HEARTBEAT_URL" ]; then
    echo "Heartbeat URL    : $HEARTBEAT_URL"
else
    echo "Heartbeat URL    : Nie ingestel"
fi

if [ "$INSTALL_FILEBROWSER" = "yes" ]; then
    echo "File Browser     : Ja"
    echo "FB Adres         : $FILEBROWSER_ADDRESS"
    echo "FB Poort         : $FILEBROWSER_PORT"
else
    echo "File Browser     : Nee"
fi

if [ "$INSTALL_RESTART_TIMER" = "yes" ]; then
    echo "Outo-restart     : Ja"
    echo "Restart Tye      : $RESTART_SCHEDULE"
    if [ -n "$RESTART_PUSH_URL" ]; then
        echo "Kuma Push URL    : Ingestel"
    else
        echo "Kuma Push URL    : Nie ingestel"
    fi
else
    echo "Outo-restart     : Nee"
fi

if [ "$INSTALL_DASHBOARD" = "yes" ]; then
    echo "Beheerpaneel     : Ja"
else
    echo "Beheerpaneel     : Nee"
fi

echo

read -rp "Stoor konfigurasie? (Y/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo
    echo "Opstelling gekanselleer."
    exit 1
fi

#
# Skep config gids
#

mkdir -p "$CONFIG_DIR"
mkdir -p /opt/radio-orania/config

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
    echo
    printf '%s=%q\n' PLAYLIST_RELOAD "$PLAYLIST_RELOAD"
    printf '%s=%q\n' PLAYLIST_PREFETCH "$PLAYLIST_PREFETCH"
    echo
    printf '%s=%q\n' HEARTBEAT_URL "$HEARTBEAT_URL"
    echo
    printf '%s=%q\n' INSTALL_FILEBROWSER "$INSTALL_FILEBROWSER"
    echo
    printf '%s=%q\n' FILEBROWSER_ADDRESS "$FILEBROWSER_ADDRESS"
    printf '%s=%q\n' FILEBROWSER_PORT "$FILEBROWSER_PORT"
    echo
    printf '%s=%q\n' INSTALL_RESTART_TIMER "$INSTALL_RESTART_TIMER"
    printf '%s=%q\n' RESTART_SCHEDULE "$RESTART_SCHEDULE"
    printf '%s=%q\n' RESTART_PUSH_URL "$RESTART_PUSH_URL"
    echo
    printf '%s=%q\n' INSTALL_DASHBOARD "$INSTALL_DASHBOARD"
    printf '%s=%q\n' ICECAST_PORT "$ICECAST_PORT"
    printf '%s=%q\n' ICECAST_SOURCE_PASSWORD "$ICECAST_SOURCE_PASSWORD"
} > "$CONFIG_DIR/environment.conf"

install -m 600 \
    "$CONFIG_DIR/environment.conf" \
    /opt/radio-orania/config/environment.conf

echo
echo "Konfigurasie geskep:"
echo
echo "$CONFIG_DIR/environment.conf"
echo
