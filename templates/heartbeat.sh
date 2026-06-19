#!/bin/bash

source /opt/radio-orania/config/environment.conf

while true; do

    systemctl is-active --quiet radio-orania.service || exit 1

    curl \
        -fsS \
        -o /dev/null \
        "${HEARTBEAT_URL}1"

    sleep 5

done