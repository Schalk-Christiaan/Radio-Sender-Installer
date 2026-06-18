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

# Setup indien nodig
if [ -f "$SCRIPT_DIR/config/environment.conf" ]; then

    echo "Bestaande konfigurasie gevind."

    read -p "Herkonfigureer? (Y/N): " RECONFIGURE

    if [[ "$RECONFIGURE" =~ ^[Yy]$ ]]; then
        bash "$SCRIPT_DIR/scripts/setup.sh"
    fi

else

    bash "$SCRIPT_DIR/scripts/setup.sh"

fi

# Verifieer konfigurasie
if [ ! -f "$SCRIPT_DIR/config/environment.conf" ]; then
    echo "FOUT: environment.conf ontbreek."
    exit 1
fi

# Lees konfigurasie
source "$SCRIPT_DIR/config/environment.conf"

# Installasie
run_step "Installeer afhanklikhede" "$SCRIPT_DIR/scripts/dependencies.sh"

run_step "Skep vouers" "$SCRIPT_DIR/scripts/directories.sh"

run_step "Konfigureer Liquidsoap" "$SCRIPT_DIR/scripts/liquidsoap.sh"

if [ "$INSTALL_FILEBROWSER" = "yes" ]; then
    run_step "Installeer File Browser" "$SCRIPT_DIR/scripts/filebrowser.sh"
fi

run_step "Installeer diens" "$SCRIPT_DIR/scripts/service.sh"

run_step "Monitering opstel" "$SCRIPT_DIR/scripts/monitoring.sh"

run_step "Valideer installasie" "$SCRIPT_DIR/scripts/validation.sh"

echo
echo "==================="
echo "Installasie voltooi"
echo "==================="

echo
echo "Log lêer:"
echo "$LOG_FILE"