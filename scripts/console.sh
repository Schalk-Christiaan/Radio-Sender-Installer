#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"
source "$SCRIPT_DIR/../config/environment.conf"

if [ "$INSTALL_DASHBOARD" != "yes" ]; then
    progress 100 "Beheerpaneel-skerm nie aangevra nie"
    exit 0
fi

# Die konsole (tty1, waar die beheerpaneel-skerm fisies verskyn) gebruik
# broneers 'n groot verstek-lettertipe (bv. 8x16), wat op 'n wye skerm net
# 'n klein deel van die skerm se breedte benut - hoe kleiner die
# lettertipe, hoe meer kolomme/reëls pas op dieselfde fisiese skerm, en
# hoe wyer lyk die dashboard. "Terminus 12x6" is die kleinste, digste
# lettertipe wat amptelik saam met Debian se console-setup verpak word.
#
# Let wel: dit verander net die lettertipe. As die konsole self nie op
# die skerm se volle native resolusie loop nie (raar op moderne
# hardeware, maar moontlik), sal selfs 'n klein lettertipe nie veel help
# nie - sien die README vir 'n opsionele GRUB "video="-instelling.

progress 20 "Kontroleer console-setup"

if ! dpkg -s console-setup >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq console-setup
fi

progress 60 "Stel klein lettertipe in (Terminus 12x6)"

CONSOLE_SETUP_FILE=/etc/default/console-setup

if [ -f "$CONSOLE_SETUP_FILE" ]; then
    sed -i 's/^FONTFACE=.*/FONTFACE="Terminus"/' "$CONSOLE_SETUP_FILE"
    sed -i 's/^FONTSIZE=.*/FONTSIZE="12x6"/' "$CONSOLE_SETUP_FILE"
else
    {
        echo 'FONTFACE="Terminus"'
        echo 'FONTSIZE="12x6"'
    } >> "$CONSOLE_SETUP_FILE"
fi

progress 85 "Pas dadelik toe"

# Kan misluk in omgewings sonder 'n regte virtuele konsole (bv. binne 'n
# houer) - nie fataal nie, die instelling geld in elk geval by die
# volgende regte skerm-herbegin.
setupcon --save >/dev/null 2>&1 || true

progress 100 "Klaar"
