#!/bin/bash

set -e

if [ -f config/environment.conf ]; then
    echo "Bestaande konfigurasie gevind."
    read -p "Herkonfigureer? (Y/N): " RECONFIGURE

    if [[ "$RECONFIGURE" =~ ^[Yy]$ ]]; then
        bash scripts/setup.sh
    fi
else
    bash scripts/setup.sh
fi

if [ ! -f config/environment.conf ]; then
    echo "FOUT: Geen environment.conf geskep nie. Skep dit met nano config/environment.conf"
    exit 1
fi

echo
echo "=============================="
echo " Radio Orania Sender Installer"
echo "=============================="
echo

bash scripts/dependencies.sh
bash scripts/directories.sh
bash scripts/liquidsoap.sh
bash scripts/service.sh
bash scripts/monitoring.sh
bash scripts/validation.sh

echo
echo "==================="
echo "Installasie voltooi"
echo "==================="
echo