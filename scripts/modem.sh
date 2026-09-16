#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

BASE_DIR="/opt/radio-orania"

progress 10 "Kontroleer modem-failover"

if [ "$INSTALL_MODEM_FAILOVER" != "yes" ]; then

    if [ -f /etc/systemd/system/radio-network-watchdog.service ]; then
        systemctl stop radio-network-watchdog.service 2>/dev/null || true
        systemctl disable radio-network-watchdog.service 2>/dev/null || true
        rm -f /etc/systemd/system/radio-network-watchdog.service
        systemctl daemon-reload
    fi

    progress 100 "Geen modem-failover ingestel"
    exit 0

fi

progress 25 "Installeer NetworkManager en ModemManager"

apt-get install -y -qq \
    network-manager \
    modemmanager \
    mobile-broadband-provider-info

progress 50 "Stel NetworkManager op om die bekabelde koppelvlak te ignoreer"

# Die bekabelde koppelvlak word reeds deur ifupdown
# (/etc/network/interfaces) bestuur en moet nie ook deur NetworkManager
# oorgeneem word nie - dit kon die bestaande, werkende verbinding
# ontwrig. Alles ANDERS (die modem, ongeag watter tipe toestel dit
# blyk te wees - baie LTE-stokkies verskyn eenvoudig as 'n gewone
# USB-Ethernet-toestel, nie as 'n ModemManager "gsm"-tipe nie) bly
# NetworkManager se verantwoordelikheid.
MODEM_ETH_IFACE=$(awk '/^iface/ && $2 != "lo" {print $2; exit}' /etc/network/interfaces 2>/dev/null)

mkdir -p /etc/NetworkManager/conf.d

if [ -n "$MODEM_ETH_IFACE" ]; then
    cat > /etc/NetworkManager/conf.d/10-ignore-wired.conf << EOF
[keyfile]
unmanaged-devices=interface-name:$MODEM_ETH_IFACE
EOF
fi

progress 65 "Begin NetworkManager en ModemManager"

systemctl enable --now NetworkManager >/dev/null 2>&1
systemctl enable --now ModemManager >/dev/null 2>&1

progress 80 "Installeer netwerk-bewaker"

mkdir -p "$BASE_DIR/network"

cp \
    "$SCRIPT_DIR/../templates/network-watchdog.sh" \
    "$BASE_DIR/network/network-watchdog.sh"

chmod +x "$BASE_DIR/network/network-watchdog.sh"

cp \
    "$SCRIPT_DIR/../templates/radio-network-watchdog.service" \
    /etc/systemd/system/radio-network-watchdog.service

systemctl daemon-reload

systemctl enable radio-network-watchdog.service >/dev/null 2>&1
systemctl restart radio-network-watchdog.service >/dev/null 2>&1

progress 100 "Klaar"
