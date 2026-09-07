#!/bin/bash

set -e
set -o pipefail

# Bepaal waar die installer werklik lê
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verbose ondersteuning
VERBOSE=false

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

LOG_FILE="$SCRIPT_DIR/installer.log"
CONFIG_FILE="$SCRIPT_DIR/config/environment.conf"
DEPLOYED_CONFIG="/opt/radio-orania/config/environment.conf"

run_step() {

    local label="$1"
    local script="$2"
    local status=0

    echo
    echo ">>> $label"

    set +e

    if [ "$VERBOSE" = true ]; then
        bash "$script" 2>&1 | tee -a "$LOG_FILE"
        status=${PIPESTATUS[0]}
    else
        bash "$script" >>"$LOG_FILE" 2>&1
        status=$?
    fi

    set -e

    if [ "$status" -ne 0 ]; then
        echo
        echo "FOUT: '$label' het misluk (kode $status)."
        echo "Sien die log vir besonderhede: $LOG_FILE"
        exit "$status"
    fi

}

echo
echo "=============================="
echo " Radio Orania Sender Installer"
echo "=============================="
echo

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

    echo "WAARSKUWING: Hierdie installer is ontwerp vir Debian 13."
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

    echo "Bestaande konfigurasie gevind."

    read -p "Herkonfigureer? (Y/N): " RECONFIGURE

    if [[ "$RECONFIGURE" =~ ^[Yy]$ ]]; then
        bash "$SCRIPT_DIR/scripts/setup.sh"
    fi

else

    bash "$SCRIPT_DIR/scripts/setup.sh"

fi

# Verifieer konfigurasie
if [ ! -f "$CONFIG_FILE" ]; then
    echo "FOUT: environment.conf ontbreek."
    exit 1
fi

# Lees konfigurasie
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Installasie
run_step "Installeer afhanklikhede" "$SCRIPT_DIR/scripts/dependencies.sh"

run_step "Skep diens-gebruiker" "$SCRIPT_DIR/scripts/user.sh"

run_step "Skep vouers" "$SCRIPT_DIR/scripts/directories.sh"

run_step "Konfigureer Liquidsoap" "$SCRIPT_DIR/scripts/liquidsoap.sh"

if [ "$INSTALL_FILEBROWSER" = "yes" ]; then
    run_step "Installeer File Browser" "$SCRIPT_DIR/scripts/filebrowser.sh"
fi

run_step "Installeer diens" "$SCRIPT_DIR/scripts/service.sh"

run_step "Monitering opstel" "$SCRIPT_DIR/scripts/monitoring.sh"

if [ "$INSTALL_RESTART_TIMER" = "yes" ]; then
    run_step "Installeer outo-restart timer" "$SCRIPT_DIR/scripts/restarttimer.sh"
elif [ -f /etc/systemd/system/radio-orania-restart.timer ]; then
    run_step "Verwyder outo-restart timer" "$SCRIPT_DIR/scripts/uninstall_restarttimer.sh"
fi

run_step "Installeer beheerpaneel" "$SCRIPT_DIR/scripts/controlpanel.sh"

run_step "Berg installer vir latere gebruik" "$SCRIPT_DIR/scripts/persist_installer.sh"

run_step "Stel toestemmings reg" "$SCRIPT_DIR/scripts/permissions.sh"

run_step "Valideer installasie" "$SCRIPT_DIR/scripts/validation.sh"

echo
echo "==================="
echo "Installasie voltooi"
echo "==================="

echo
echo "Log lêer:"
echo "$LOG_FILE"

echo
echo "Gebruik 'radioctl status' om die sender se status te sien,"
echo "of 'radioctl' vir 'n lys van alle beskikbare opdragte."
