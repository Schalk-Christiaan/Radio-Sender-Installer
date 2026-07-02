#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"

DEFAULT_STATION_NAME="Radio Orania"
DEFAULT_MUSIC_WEIGHT="4"
DEFAULT_SWEEPER_WEIGHT="1"
DEFAULT_INSTALL_FILEBROWSER="yes"
DEFAULT_RESTART_SCHEDULE="06:30 13:30"

echo
echo "===================================="
echo " Radio Orania Sender Opstelling"
echo "===================================="
echo

#
# Sender Naam
#

read -rp "Sender Naam [$DEFAULT_STATION_NAME]: " STATION_NAME
STATION_NAME=${STATION_NAME:-$DEFAULT_STATION_NAME}

#
# Stream URL
#

DEFAULT_STREAM_URL="https://stream.radio.co/s7adaa782c/listen"

while true; do

    read -rp "Stroom URL [$DEFAULT_STREAM_URL]: " STREAM_URL

    STREAM_URL=${STREAM_URL:-$DEFAULT_STREAM_URL}

    if [ -n "$STREAM_URL" ]; then
        break
    fi

    echo "Stroom URL is verpligtend."

done

#
# Gewigte
#

read -rp "Musiek gewig [$DEFAULT_MUSIC_WEIGHT]: " MUSIC_WEIGHT
MUSIC_WEIGHT=${MUSIC_WEIGHT:-$DEFAULT_MUSIC_WEIGHT}

read -rp "Sweeper gewig [$DEFAULT_SWEEPER_WEIGHT]: " SWEEPER_WEIGHT
SWEEPER_WEIGHT=${SWEEPER_WEIGHT:-$DEFAULT_SWEEPER_WEIGHT}

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
# Heartbeat
#

echo
read -rp "Heartbeat URL (opsioneel): " HEARTBEAT_URL

#
# File Browser
#

read -rp "Installeer File Browser? (Y/N) [Y]: " FB

if [[ ! "$FB" =~ ^[Nn]$ ]]; then

    INSTALL_FILEBROWSER="yes"

    echo

    read -rp "File Browser Adres [0.0.0.0]: " FILEBROWSER_ADDRESS
    FILEBROWSER_ADDRESS=${FILEBROWSER_ADDRESS:-0.0.0.0}

    read -rp "File Browser Poort [8081]: " FILEBROWSER_PORT
    FILEBROWSER_PORT=${FILEBROWSER_PORT:-8081}

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

    read -rp "Uptime Kuma Push URL (opsioneel): " RESTART_PUSH_URL

else

    INSTALL_RESTART_TIMER="no"
    RESTART_SCHEDULE="$DEFAULT_RESTART_SCHEDULE"
    RESTART_PUSH_URL=""

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
echo "Musiek Gewig     : $MUSIC_WEIGHT"
echo "Sweeper Gewig    : $SWEEPER_WEIGHT"
echo "ALSA Device      : $ALSA_DEVICE"

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

cat > "$CONFIG_DIR/environment.conf" << EOF
STATION_NAME="$STATION_NAME"

STREAM_URL="$STREAM_URL"

ALSA_DEVICE="$ALSA_DEVICE"

MUSIC_WEIGHT="$MUSIC_WEIGHT"
SWEEPER_WEIGHT="$SWEEPER_WEIGHT"

PLAYLIST_RELOAD="$PLAYLIST_RELOAD"
PLAYLIST_PREFETCH="$PLAYLIST_PREFETCH"

HEARTBEAT_URL="$HEARTBEAT_URL"

INSTALL_FILEBROWSER="$INSTALL_FILEBROWSER"

FILEBROWSER_ADDRESS="$FILEBROWSER_ADDRESS"
FILEBROWSER_PORT="$FILEBROWSER_PORT"

INSTALL_RESTART_TIMER="$INSTALL_RESTART_TIMER"
RESTART_SCHEDULE="$RESTART_SCHEDULE"
RESTART_PUSH_URL="$RESTART_PUSH_URL"
EOF

install -m 600 \
    "$CONFIG_DIR/environment.conf" \
    /opt/radio-orania/config/environment.conf

echo
echo "Konfigurasie geskep:"
echo
echo "$CONFIG_DIR/environment.conf"
echo
