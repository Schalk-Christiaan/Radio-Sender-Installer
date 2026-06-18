#!/bin/bash

systemctl is-active --quiet radio-orania.service || exit 1

curl -fsS -o /dev/null "__HEARTBEAT_URL__"