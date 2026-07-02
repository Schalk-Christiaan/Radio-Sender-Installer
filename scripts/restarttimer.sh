#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

HELPER_FILE="/usr/local/bin/restart-radio.sh"
SERVICE_FILE="/etc/systemd/system/radio-orania-restart.service"
TIMER_FILE="/etc/systemd/system/radio-orania-restart.timer"

progress 15 "Skep restart helper"

cat > "$HELPER_FILE" << EOF
#!/bin/bash
set -e

PUSH_URL="$RESTART_PUSH_URL"
BASE_PUSH_URL="\${PUSH_URL%%\?*}"
SERVICE_NAME="radio-orania.service"
MAX_WAIT=60

curl_push() {
    local status="\$1"
    local message="\$2"

    if [ -n "\$BASE_PUSH_URL" ]; then
        curl -fsS "\${BASE_PUSH_URL}?status=\${status}&msg=\${message}&ping=" >/dev/null 2>&1 || true
    fi
}

if ! systemctl restart "\$SERVICE_NAME"; then
    curl_push "down" "Radio%20restart%20failed"
    exit 1
fi

elapsed=0
while [ "\$elapsed" -lt "\$MAX_WAIT" ]; do
    if systemctl is-active --quiet "\$SERVICE_NAME"; then
        curl_push "up" "Radio%20restarted"
        exit 0
    fi
    sleep 2
    elapsed=\$((elapsed + 2))
done

curl_push "down" "Radio%20did%20not%20become%20active"
exit 1
EOF

chmod +x "$HELPER_FILE"

progress 40 "Skep restart diens"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Restart Radio Orania service

[Service]
Type=oneshot
ExecStart=$HELPER_FILE
EOF

progress 65 "Skep restart timer"

{
    echo "[Unit]"
    echo "Description=Restart Radio Orania op geskeduleerde tye"
    echo
    echo "[Timer]"
    for slot in $RESTART_SCHEDULE; do
        echo "OnCalendar=*-*-* $slot:00"
    done
    echo "Persistent=true"
    echo
    echo "[Install]"
    echo "WantedBy=timers.target"
} > "$TIMER_FILE"

progress 85 "Aktiveer restart timer"

systemctl daemon-reload
systemctl enable --now radio-orania-restart.timer >/dev/null 2>&1

progress 100 "Klaar"
