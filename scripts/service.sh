cp templates/radio-orania.service \
   /etc/systemd/system/

systemctl daemon-reload
systemctl enable radio-orania.service