#!/bin/bash

set -e

systemctl disable --now radio-orania-restart.timer 2>/dev/null || true
systemctl stop radio-orania-restart.service 2>/dev/null || true

rm -f /etc/systemd/system/radio-orania-restart.timer
rm -f /etc/systemd/system/radio-orania-restart.service
rm -f /usr/local/bin/restart-radio.sh

systemctl daemon-reload
systemctl reset-failed

echo "Radio restart timer verwyder."
