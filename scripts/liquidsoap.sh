#!/bin/bash

source config/environment.conf

TARGET=/opt/radio-orania/liquidsoap/radio.liq

cp templates/radio.liq "$TARGET"

sed -i "s|__STREAM_URL__|$STREAM_URL|g" "$TARGET"
sed -i "s|__ALSA_DEVICE__|$ALSA_DEVICE|g" "$TARGET"

sed -i "s|__MUSIC_WEIGHT__|$MUSIC_WEIGHT|g" "$TARGET"
sed -i "s|__SWEEPER_WEIGHT__|$SWEEPER_WEIGHT|g" "$TARGET"

sed -i "s|__PLAYLIST_RELOAD__|$PLAYLIST_RELOAD|g" "$TARGET"
sed -i "s|__PLAYLIST_PREFETCH__|$PLAYLIST_PREFETCH|g" "$TARGET"