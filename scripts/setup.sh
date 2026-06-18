#!/bin/bash

echo
echo "===================================="
echo " Radio Orania Sender Opstelling"
echo "===================================="
echo

read -p "Stroom URL: " STREAM_URL

read -p "ALSA toestel [default]: " ALSA_DEVICE
ALSA_DEVICE=${ALSA_DEVICE:-default}

read -p "Musiek gewig [4]: " MUSIC_WEIGHT
MUSIC_WEIGHT=${MUSIC_WEIGHT:-4}

read -p "Sweeper gewig [1]: " SWEEPER_WEIGHT
SWEEPER_WEIGHT=${SWEEPER_WEIGHT:-1}

read -p "Playlist reload [1000]: " PLAYLIST_RELOAD
PLAYLIST_RELOAD=${PLAYLIST_RELOAD:-1000}

read -p "Playlist prefetch [10]: " PLAYLIST_PREFETCH
PLAYLIST_PREFETCH=${PLAYLIST_PREFETCH:-10}

read -p "Heartbeat URL: " HEARTBEAT_URL

mkdir -p config

cat > config/environment.conf << EOF
STREAM_URL="$STREAM_URL"

ALSA_DEVICE="$ALSA_DEVICE"

MUSIC_WEIGHT=$MUSIC_WEIGHT
SWEEPER_WEIGHT=$SWEEPER_WEIGHT

PLAYLIST_RELOAD=$PLAYLIST_RELOAD
PLAYLIST_PREFETCH=$PLAYLIST_PREFETCH

HEARTBEAT_URL="$HEARTBEAT_URL"
EOF

echo
echo "Konfigurasie geskep:"
echo
cat config/environment.conf
echo