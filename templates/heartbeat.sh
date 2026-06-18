#!/bin/bash

curl \
  --connect-timeout 10 \
  --max-time 20 \
  -fsS \
  "__UPTIME_URL__" \
  >/dev/null 2>&1