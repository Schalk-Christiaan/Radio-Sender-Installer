#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"

DEFAULT_STATION_NAME="Radio Orania"
DEFAULT_MUSIC_WEIGHT="4"
DEFAULT_SWEEPER_WEIGHT="1"
DEFAULT_INSTALL_FILEBROWSER="yes"

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

while true; do

    read -rp "Stroom URL: " STREAM_URL

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

    read -rp "File Browser Adres [127.0.0.1]: " FILEBROWSER_ADDRESS
    FILEBROWSER_ADDRESS=${FILEBROWSER_ADDRESS:-127.0.0.1}

    read -rp "File Browser Poort [8081]: " FILEBROWSER_PORT
    FILEBROWSER_PORT=${FILEBROWSER_PORT:-8081}

else

    INSTALL_FILEBROWSER="no"

    FILEBROWSER_ADDRESS="127.0.0.1"
    FILEBROWSER_PORT="8081"

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
EOF

echo
echo "Konfigurasie geskep:"
echo
echo "$CONFIG_DIR/environment.conf"
echo