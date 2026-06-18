#!/bin/bash

source /opt/radio-orania/config/environment.conf

systemctl is-active --quiet radio-orania.service || exit 1

curl -fsS -o /dev/null "$HEARTBEAT_URL"