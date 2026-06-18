#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

progress 25 "Kontroleer heartbeat"

if [ -z "$HEARTBEAT_URL" ]; then

    progress 100 "Geen heartbeat ingestel"

    exit 0

fi

progress 50 "Installeer heartbeat"

cp \
    "$SCRIPT_DIR/../templates/heartbeat.sh" \
    /usr/local/bin/heartbeat.sh

sed -i \
    "s|__HEARTBEAT_URL__|$HEARTBEAT_URL|g" \
    /usr/local/bin/heartbeat.sh

chmod +x /usr/local/bin/heartbeat.sh

progress 75 "Skep cronjob"

cat > /etc/cron.d/radio-orania-heartbeat << EOF
* * * * * root /usr/local/bin/heartbeat.sh
EOF

progress 100 "Klaar"