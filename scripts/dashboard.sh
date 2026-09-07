#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"

ADMIN_USER="radio-admin"
CRED_FILE="/opt/radio-orania/config/radio-admin-credentials.txt"

progress 15 "Skep admin-gebruiker"

NEW_ADMIN=false

if ! id "$ADMIN_USER" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "$ADMIN_USER"
    NEW_ADMIN=true
fi

if [ "$NEW_ADMIN" = true ]; then

    progress 30 "Genereer wagwoord"

    ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    echo "${ADMIN_USER}:${ADMIN_PASSWORD}" | chpasswd

    cat > "$CRED_FILE" << EOF
Radio Beheerpaneel Aanmelding

Gebruiker:
$ADMIN_USER

Wagwoord:
$ADMIN_PASSWORD

Meld hiermee via SSH aan, of by die fisiese skerm, om die beheerpaneel te sien.
EOF

    chmod 600 "$CRED_FILE"

fi

progress 45 "Stel beperkte toegang tot radioctl in"

cat > /etc/sudoers.d/radio-admin << 'EOF'
radio-admin ALL=(root) NOPASSWD: /usr/local/bin/radioctl
EOF

chmod 440 /etc/sudoers.d/radio-admin

progress 60 "Installeer beheerpaneel-skerm"

install -m 755 \
    "$SCRIPT_DIR/../templates/radio-dashboard.sh" \
    /usr/local/bin/radio-dashboard

progress 75 "Koppel aan aanmelding"

BASH_PROFILE="/home/$ADMIN_USER/.bash_profile"

cat > "$BASH_PROFILE" << 'EOF'
if [ -t 0 ] && [ -z "$RADIO_DASHBOARD_ACTIVE" ]; then
    export RADIO_DASHBOARD_ACTIVE=1
    /usr/local/bin/radio-dashboard
fi
EOF

chown "$ADMIN_USER:$ADMIN_USER" "$BASH_PROFILE"

progress 90 "Aktiveer outoaanmelding op fisiese skerm (tty1)"

mkdir -p /etc/systemd/system/getty@tty1.service.d

cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $ADMIN_USER --noclear %I \$TERM
EOF

systemctl daemon-reload

progress 100 "Klaar"

if [ "$NEW_ADMIN" = true ]; then
    echo
    echo "===================================="
    echo " Beheerpaneel Gebruiker"
    echo "===================================="
    echo
    echo "Gebruiker: $ADMIN_USER"
    echo "Wagwoord : $ADMIN_PASSWORD"
    echo
    echo "Bewaar:"
    echo "$CRED_FILE"
    echo
fi
