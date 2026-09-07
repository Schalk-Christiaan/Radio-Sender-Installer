#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

if [ "$INSTALL_DASHBOARD" != "yes" ]; then
    progress 100 "Monitor-aftakking nie aangevra nie"
    exit 0
fi

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

progress 20 "Skryf Icecast konfigurasie"

cp \
    "$SCRIPT_DIR/../templates/icecast.xml" \
    /etc/icecast2/icecast.xml

sed -i "s|__ICECAST_PORT__|$ICECAST_PORT|g" /etc/icecast2/icecast.xml
sed -i "s|__ICECAST_SOURCE_PASSWORD__|$(escape_sed_replacement "$ICECAST_SOURCE_PASSWORD")|g" /etc/icecast2/icecast.xml

chmod 640 /etc/icecast2/icecast.xml
chown root:icecast /etc/icecast2/icecast.xml 2>/dev/null || true

progress 60 "Aktiveer Icecast diens"

if [ -f /etc/default/icecast2 ]; then
    sed -i 's/^ENABLE=.*/ENABLE=true/' /etc/default/icecast2
else
    echo "ENABLE=true" > /etc/default/icecast2
fi

systemctl daemon-reload
systemctl enable icecast2 >/dev/null 2>&1
systemctl restart icecast2

progress 100 "Klaar"
