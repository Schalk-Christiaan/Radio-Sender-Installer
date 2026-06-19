#!/bin/bash

source /opt/radio-orania/config/environment.conf

systemctl is-active --quiet radio-orania.service || exit 1

PING=$(curl \
    -o /dev/null \
    -s \
    -w "%{time_total}" \
    "$STREAM_URL")

curl \
    -fsS \
    -o /dev/null \
    "${HEARTBEAT_URL}${PING}"