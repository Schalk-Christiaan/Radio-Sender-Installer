source config/environment.conf

cp templates/heartbeat.sh \
   /usr/local/bin/heartbeat.sh

sed -i "s|__UPTIME_URL__|$UPTIME_URL|g" \
   /usr/local/bin/heartbeat.sh

chmod +x /usr/local/bin/heartbeat.sh