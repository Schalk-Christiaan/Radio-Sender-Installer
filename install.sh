#!/bin/bash

set -e
set -o pipefail

# Bepaal waar die installer werklik lê
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verbose ondersteuning - uitgevoer sodat stap-skripte (via progress.sh se
# warn()) kan weet of hulle eie /dev/tty-skryf oorbodig sou wees (die
# --verbose "tee" hieronder wys stdout reeds op die skerm).
export VERBOSE=false

for arg in "$@"; do
    case "$arg" in
        -v|--verbose)
            VERBOSE=true
            ;;
        -h|--help)
            echo "Gebruik: sudo bash install.sh [--verbose]"
            echo
            echo "  --verbose, -v   Wys volledige uitset van elke stap op die skerm"
            echo "                  (word in elk geval altyd na installer.log geskryf)"
            exit 0
            ;;
    esac
done

source "$SCRIPT_DIR/scripts/ui.sh"

LOG_FILE="$SCRIPT_DIR/installer.log"
CONFIG_FILE="$SCRIPT_DIR/config/environment.conf"
DEPLOYED_CONFIG="/opt/radio-orania/config/environment.conf"

run_step() {

    local label="$1"
    local script="$2"
    local status=0

    set +e

    if [ "$VERBOSE" = true ]; then
        echo
        echo ">>> $label"
        bash "$script" 2>&1 | tee -a "$LOG_FILE"
        status=${PIPESTATUS[0]}
    else
        ui_spin "$label" "$LOG_FILE" bash "$script"
        status=$?
    fi

    set -e

    if [ "$status" -ne 0 ]; then
        [ "$VERBOSE" = true ] && ui_fail "'$label' het misluk (kode $status)."
        ui_hint "Volledige log: $LOG_FILE"
        exit "$status"
    fi

}

ui_banner "Sender-installeerder  ${UI_ARROW} internetstroom na FM, 24/7"

if [ "$EUID" -ne 0 ]; then
    echo "Hierdie installer moet as root loop."
    echo "Gebruik: sudo bash install.sh"
    exit 1
fi

# Bedryfstelsel-kontrole
DEBIAN_OK=false

if [ -f /etc/os-release ]; then

    . /etc/os-release

    if [ "${ID:-}" = "debian" ] &&
       [[ "${VERSION_ID:-}" =~ ^([0-9]+) ]] &&
       [ "${BASH_REMATCH[1]}" -ge 13 ]; then
        DEBIAN_OK=true
    fi

fi

if [ "$DEBIAN_OK" = false ]; then

    ui_warn "Hierdie installer is ontwerp vir Debian 13."
    echo "Bespeur: ${PRETTY_NAME:-onbekend}"
    echo

    read -rp "Wil jy voortgaan ten spyte hiervan? (Y/N): " CONTINUE_ANYWAY

    if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
        exit 1
    fi

fi

# Setup indien nodig
if [ ! -f "$CONFIG_FILE" ] && [ -f "$DEPLOYED_CONFIG" ]; then
    mkdir -p "$SCRIPT_DIR/config"
    cp "$DEPLOYED_CONFIG" "$CONFIG_FILE"
fi

if [ -f "$CONFIG_FILE" ]; then

    ui_ok "Bestaande konfigurasie gevind."

    read -rp "$(ui_q "Herkonfigureer? (Y/N)" "N")" RECONFIGURE

    if [[ "$RECONFIGURE" =~ ^[Yy]$ ]]; then
        UI_NO_BANNER=1 bash "$SCRIPT_DIR/scripts/setup.sh"
    fi

else

    UI_NO_BANNER=1 bash "$SCRIPT_DIR/scripts/setup.sh"

fi

# Verifieer konfigurasie
if [ ! -f "$CONFIG_FILE" ]; then
    echo "FOUT: environment.conf ontbreek."
    exit 1
fi

# Altyd na /opt ontplooi (radioctl lees dit daar), ook as die opstelling
# oorgeslaan is - bv. herinstallasie met 'n bewaarde konfigurasie.
install -D -m 600 "$CONFIG_FILE" "$DEPLOYED_CONFIG"

# Lees konfigurasie
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Installasie
ui_section "Installeer"
INSTALL_T0=$SECONDS

run_step "Installeer afhanklikhede" "$SCRIPT_DIR/scripts/dependencies.sh"

run_step "Skep diens-gebruiker" "$SCRIPT_DIR/scripts/user.sh"

run_step "Skep vouers" "$SCRIPT_DIR/scripts/directories.sh"

run_step "Stel monitor-aftakking op" "$SCRIPT_DIR/scripts/icecast.sh"

run_step "Konfigureer Liquidsoap" "$SCRIPT_DIR/scripts/liquidsoap.sh"

run_step "Stel volume" "$SCRIPT_DIR/scripts/volume.sh"

if [ "$INSTALL_FILEBROWSER" = "yes" ]; then
    run_step "Installeer File Browser" "$SCRIPT_DIR/scripts/filebrowser.sh"
fi

run_step "Installeer diens" "$SCRIPT_DIR/scripts/service.sh"

run_step "Modem-failover opstel" "$SCRIPT_DIR/scripts/modem.sh"

run_step "Kennisgewings opstel" "$SCRIPT_DIR/scripts/notify.sh"

if [ "$INSTALL_RESTART_TIMER" = "yes" ]; then
    run_step "Installeer outo-restart timer" "$SCRIPT_DIR/scripts/restarttimer.sh"
elif [ -f /etc/systemd/system/radio-orania-restart.timer ]; then
    run_step "Verwyder outo-restart timer" "$SCRIPT_DIR/scripts/uninstall_restarttimer.sh"
fi

run_step "Installeer radioctl" "$SCRIPT_DIR/scripts/controlpanel.sh"

if [ "$INSTALL_DASHBOARD" = "yes" ]; then
    run_step "Installeer beheerpaneel-skerm" "$SCRIPT_DIR/scripts/dashboard.sh"
    run_step "Stel data-verbruik-monitering op" "$SCRIPT_DIR/scripts/vnstat.sh"
fi

run_step "Berg installer vir latere gebruik" "$SCRIPT_DIR/scripts/persist_installer.sh"

run_step "Stel toestemmings reg" "$SCRIPT_DIR/scripts/permissions.sh"

run_step "Valideer installasie" "$SCRIPT_DIR/scripts/validation.sh"

# "install"/"cp" se sukses beteken net dat die skryf in die
# bestuurstelsel se geheue-kas is, nie noodwendig reeds werklik op skyf
# nie - "sync" dwing dit deur voordat "Installasie voltooi" hieronder
# gewys word, sodat 'n kragonderbreking net daarna nie enige geskrewe
# lêer (soos die File Browser-binêre) kan korrupteer nie.
sync

MINS=$(( (SECONDS - INSTALL_T0) / 60 ))
SECS=$(( (SECONDS - INSTALL_T0) % 60 ))
IP=$(hostname -I 2>/dev/null | awk '{print $1}')

echo
printf '  %s%s Installasie voltooi%s %s(%dm %02ds)%s\n\n' "$C_OK$C_B" "$UI_OK" "$C_0" "$C_DIM" "$MINS" "$SECS" "$C_0"

ui_kv "Status" "radioctl status"
ui_kv "Alle opdragte" "radioctl"

if [ "$INSTALL_DASHBOARD" = "yes" ]; then
    ui_kv "Beheerpaneel" "radioctl dash  (of teken in as radio-admin)"
fi

if [ "$INSTALL_FILEBROWSER" = "yes" ] && [ -n "$IP" ]; then
    ui_kv "File Browser" "http://$IP:$FILEBROWSER_PORT"
fi

ui_kv "Log" "$LOG_FILE"
echo
