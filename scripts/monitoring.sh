#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

BASE_DIR="/opt/radio-orania"

progress 25 "Kontroleer heartbeat"

if [ -z "$HEARTBEAT_URL" ]; then

```
progress 100 "Geen heartbeat ingestel"

exit 0
```

fi

progress 50 "Installeer heartbeat"

mkdir -p "$BASE_DIR/monitoring"

cp \
    "$SCRIPT_DIR/../templates/heartbeat.sh" \
    "$BASE_DIR/monitoring/heartbeat.sh"

chmod +x \
    "$BASE_DIR/monitoring/heartbeat.sh"

progress 75 "Installeer heartbeat diens"

cp \
"$SCRIPT_DIR/../templates/radio-heartbeat.service" \
/etc/systemd/system/radio-heartbeat.service

systemctl daemon-reload

systemctl enable radio-heartbeat.service >/dev/null 2>&1
systemctl restart radio-heartbeat.service >/dev/null 2>&1

progress 100 "Klaar"
