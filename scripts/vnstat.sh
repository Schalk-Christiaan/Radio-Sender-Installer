#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"

progress 30 "Aktiveer vnstat-diens"

systemctl enable --now vnstat.service >/dev/null 2>&1

progress 70 "Registreer netwerkkoppelvlak"

# Bepaal die koppelvlak wat na buite kommunikeer (die een wat die stroom
# oor loop) - vnstat volg net koppelvlakke wat eksplisiet bygevoeg is.
# "|| true" want vnstat gee 'n fout as die koppelvlak alreeds geregistreer
# is, wat by 'n herinstallasie heel normaal is.
DEFAULT_IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')

if [ -n "$DEFAULT_IFACE" ]; then
    vnstat --add -i "$DEFAULT_IFACE" >/dev/null 2>&1 || true
fi

progress 100 "Klaar"
