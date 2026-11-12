#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

TARGET_DIR="/opt/radio-orania/liquidsoap"
TARGET_FILE="$TARGET_DIR/radio.liq"

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

progress 10 "Skep Liquidsoap gids"

mkdir -p "$TARGET_DIR"

# Die nuwe konfigurasie word eers in 'n tydelike lêer gebou en getoets; die
# lewendige radio.liq word eers vervang as alles slaag. Sonder dit het 'n
# mislukte toets 'n stukkende radio.liq agtergelaat wat die radio by die
# volgende herbegin (ongeluk, herlaai, outo-restart timer) stil laat.
BUILD_FILE=$(mktemp "$TARGET_DIR/radio.liq.XXXXXX")
TRIAL_DIR=""
trap 'rm -rf "$BUILD_FILE" ${TRIAL_DIR:+"$TRIAL_DIR"}' EXIT

progress 25 "Kopieer template"

cp \
    "$SCRIPT_DIR/../templates/radio.liq" \
    "$BUILD_FILE"

if [ "$INSTALL_DASHBOARD" = "yes" ]; then
    cat "$SCRIPT_DIR/../templates/radio-icecast.liq" >> "$BUILD_FILE"
    cat "$SCRIPT_DIR/../templates/radio-server-socket.liq" >> "$BUILD_FILE"
fi

if [ -n "$BACKUP_STREAM_URL" ]; then
    sed -i "/^# __BACKUP_RADIO_INSERT_POINT__$/r $SCRIPT_DIR/../templates/radio-backup-stream.liq" "$BUILD_FILE"
fi

sed -i "/^# __BACKUP_RADIO_INSERT_POINT__$/d" "$BUILD_FILE"

if [ -n "$BACKUP_STREAM_URL" ]; then
    sed -i "/^# __PRIMARY_SOURCE_SWITCH_BACKUP_BRANCH__$/r $SCRIPT_DIR/../templates/radio-switch-backup-branches.liq" "$BUILD_FILE"
fi

sed -i "/^# __PRIMARY_SOURCE_SWITCH_BACKUP_BRANCH__$/d" "$BUILD_FILE"

progress 40 "Skep noodtoon"

# Ingeboude laaste-uitweg-klank (radio.liq se emergency_fallback), apart
# van die admin se eie Musiek/Sweepers, sodat daar selfs met heeltemal
# leë media-vouers nooit werklike stilte is nie. Eenmalig gegenereer -
# word nie oorskryf as dit reeds bestaan nie (bv. by 'n latere
# "radioctl set").
EMERGENCY_DIR="$TARGET_DIR/noodklank"
EMERGENCY_FILE="$EMERGENCY_DIR/noodtoon.mp3"

mkdir -p "$EMERGENCY_DIR"

if [ ! -f "$EMERGENCY_FILE" ]; then
    ffmpeg -y -f lavfi -i "sine=frequency=440:duration=15" \
        -af "volume=0.15" "$EMERGENCY_FILE" -loglevel error
fi

progress 50 "Vul konfigurasie in"

sed -i "s|__STREAM_URL__|$(escape_sed_replacement "$STREAM_URL")|g" "$BUILD_FILE"

# Liquidsoap kry "plughw:" i.p.v. die rou "hw:" uit die konfigurasie: met
# "hw:" moet die klankkaart presies Liquidsoap se monsterkoers/formaat
# ondersteun, anders hik/spring die klank. "plughw:" laat alsa-lib self
# omskakel. environment.conf (en amixer se kaartnommer) bly onveranderd.
LIQ_ALSA_DEVICE="${ALSA_DEVICE/#hw:/plughw:}"

sed -i "s|__ALSA_DEVICE__|$(escape_sed_replacement "$LIQ_ALSA_DEVICE")|g" "$BUILD_FILE"

sed -i "s|__MUSIC_WEIGHT__|$MUSIC_WEIGHT|g" "$BUILD_FILE"

sed -i "s|__SWEEPER_WEIGHT__|$SWEEPER_WEIGHT|g" "$BUILD_FILE"

sed -i "s|__PLAYLIST_RELOAD__|$PLAYLIST_RELOAD|g" "$BUILD_FILE"

sed -i "s|__PLAYLIST_PREFETCH__|$PLAYLIST_PREFETCH|g" "$BUILD_FILE"

sed -i "s|__STREAM_BUFFER_MAX__|${STREAM_BUFFER_MAX:-20}.0|g" "$BUILD_FILE"

sed -i "s|__SILENCE_THRESHOLD__|${SILENCE_THRESHOLD:-20}.0|g" "$BUILD_FILE"

sed -i "s|__PRIMARY_SOURCE__|${PRIMARY_SOURCE:-1}|g" "$BUILD_FILE"

if [ "$INSTALL_DASHBOARD" = "yes" ]; then
    sed -i "s|__ICECAST_PORT__|$ICECAST_PORT|g" "$BUILD_FILE"
    sed -i "s|__ICECAST_SOURCE_PASSWORD__|$(escape_sed_replacement "$ICECAST_SOURCE_PASSWORD")|g" "$BUILD_FILE"
fi

if [ -n "$BACKUP_STREAM_URL" ]; then
    sed -i "s|__BACKUP_RADIO_ENTRY__|backup_radio,|g" "$BUILD_FILE"
    sed -i "s|__BACKUP_STREAM_URL__|$(escape_sed_replacement "$BACKUP_STREAM_URL")|g" "$BUILD_FILE"
else
    sed -i "s|__BACKUP_RADIO_ENTRY__||g" "$BUILD_FILE"
fi

progress 75 "Verifieer konfigurasie"

if ! liquidsoap --check "$BUILD_FILE" >/dev/null 2>&1; then
    echo
    echo "Liquidsoap konfigurasie ongeldig - bestaande radio.liq onveranderd:"
    liquidsoap --check "$BUILD_FILE" 2>&1 | tail -15
    exit 1
fi

progress 80 "Proefloop (geen klank)"

# --check vang nie alles nie (bv. 'n bron wat eers by aanskakel geweier
# word). Die proefloop begin die nuwe konfigurasie werklik vir 'n paar
# sekondes, langs die lewendige radio, maar met 'n dummy-uitset i.p.v. die
# klankkaart, sonder Icecast, en met eie socket-/statuslêers - die
# lewendige uitsending, beheer-socket en handmatige bron-wissel word dus
# nie aangeraak nie. Slaag as Liquidsoap nog loop wanneer die tyd verstryk
# en reeds 'n aktiewe bron gerapporteer het.
TRIAL_SECS="${LIQ_TRIAL_SECS:-15}"
TRIAL_DIR=$(mktemp -d)
LIVE="/opt/radio-orania/liquidsoap"
sed -e 's/^output\.alsa(/output.dummy(/' \
    -e '/^  device=alsa_device,$/d' \
    -e '/^output\.icecast(/,/^)$/d' \
    -e "s|$LIVE/source_override|$TRIAL_DIR/source_override|" \
    -e "s|$LIVE/active_source|$TRIAL_DIR/active_source|" \
    -e "s|$LIVE/socket|$TRIAL_DIR/socket|" \
    -e "s|temp_dir=\"$LIVE\"|temp_dir=\"$TRIAL_DIR\"|" \
    "$BUILD_FILE" > "$TRIAL_DIR/trial.liq"

if grep -qE "output\.alsa|$LIVE/(socket|active_source|source_override)|temp_dir=\"$LIVE\"" "$TRIAL_DIR/trial.liq"; then
    echo
    echo "Proefloop sou die lewendige radio raak (onverwagte radio.liq-struktuur) - gestaak."
    exit 1
fi

if id radio-orania >/dev/null 2>&1; then
    chown -R radio-orania "$TRIAL_DIR"
    TRIAL_RUN=(runuser -u radio-orania --)
else
    sed -i '1i settings.init.allow_root := true' "$TRIAL_DIR/trial.liq"
    TRIAL_RUN=()
fi

trial_rc=0
"${TRIAL_RUN[@]}" timeout "$TRIAL_SECS" liquidsoap "$TRIAL_DIR/trial.liq" \
    > "$TRIAL_DIR/trial.log" 2>&1 || trial_rc=$?

if [ "$trial_rc" -ne 124 ] || [ ! -s "$TRIAL_DIR/active_source" ]; then
    echo
    echo "Proefloop het misluk - bestaande radio.liq onveranderd:"
    grep -vE '^\s*$' "$TRIAL_DIR/trial.log" | tail -15
    exit 1
fi

if [ "${LIQ_CHECK_ONLY:-}" = "1" ]; then
    progress 100 "Toets geslaag (aktiewe bron: $(cat "$TRIAL_DIR/active_source")) - niks vervang nie"
    exit 0
fi

mv "$BUILD_FILE" "$TARGET_FILE"

progress 90 "Stel eienaarskap"

if id radio-orania >/dev/null 2>&1; then
    chown -R radio-orania:audio "$TARGET_DIR"
fi

progress 100 "Klaar"
