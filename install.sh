#!/bin/bash

set -e

# Bepaal waar die installer werklik lê
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verbose ondersteuning
VERBOSE=false

for arg in "$@"; do
    case "$arg" in
        -v|--verbose)
            VERBOSE=true
            ;;
    esac
done

LOG_FILE="$SCRIPT_DIR/installer.log"
CONFIG_FILE="$SCRIPT_DIR/config/environment.conf"
DEPLOYED_CONFIG="/opt/radio-orania/config/environment.conf"

run_step() {

    echo
    echo ">>> $1"

    if [ "$VERBOSE" = true ]; then
        bash "$2" | tee -a "$LOG_FILE"
    else
        bash "$2" 2>>"$LOG_FILE"
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
source "$CONFIG_FILE"

# Installasie
run_step "Installeer afhanklikhede" "$SCRIPT_DIR/scripts/dependencies.sh"

run_step "Skep vouers" "$SCRIPT_DIR/scripts/directories.sh"

run_step "Konfigureer Liquidsoap" "$SCRIPT_DIR/scripts/liquidsoap.sh"

if [ "$INSTALL_FILEBROWSER" = "yes" ]; then
    run_step "Installeer File Browser" "$SCRIPT_DIR/scripts/filebrowser.sh"
fi

run_step "Installeer diens" "$SCRIPT_DIR/scripts/service.sh"

run_step "Monitering opstel" "$SCRIPT_DIR/scripts/monitoring.sh"

if [ "$INSTALL_RESTART_TIMER" = "yes" ]; then
    run_step "Installeer outo-restart timer" "$SCRIPT_DIR/scripts/restarttimer.sh"
elif systemctl list-unit-files | grep -q radio-orania-restart.timer; then
    run_step "Verwyder outo-restart timer" "$SCRIPT_DIR/scripts/uninstall_restarttimer.sh"
fi

run_step "Valideer installasie" "$SCRIPT_DIR/scripts/validation.sh"

echo
echo "==================="
echo "Installasie voltooi"
echo "==================="

echo
echo "Log lêer:"
echo "$LOG_FILE"
