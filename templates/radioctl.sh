#!/bin/bash

set -euo pipefail

BASE_DIR="/opt/radio-orania"
CONFIG_FILE="$BASE_DIR/config/environment.conf"
INSTALLER_DIR="$BASE_DIR/installer"

need_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Hierdie opdrag moet as root loop. Gebruik: sudo radioctl $1"
        exit 1
    fi
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi
}

cmd_status() {
    load_config

    local green="" red="" bold="" reset=""
    if [ -t 1 ]; then
        green=$'\033[32m'
        red=$'\033[31m'
        bold=$'\033[1m'
        reset=$'\033[0m'
    fi

    echo "${bold}Sender Naam${reset}   : ${STATION_NAME:-onbekend}"
    echo "${bold}Stroom URL${reset}    : ${STREAM_URL:-onbekend}"
    echo

    for svc in radio-orania.service filebrowser.service radio-heartbeat.service radio-orania-restart.timer; do
        if [ -f "/etc/systemd/system/$svc" ]; then
            if systemctl is-active --quiet "$svc" 2>/dev/null; then
                printf "%-28s %s\n" "$svc" "${green}loop${reset}"
            else
                printf "%-28s %s\n" "$svc" "${red}loop nie${reset}"
            fi
        fi
    done

    echo
    df -h "$BASE_DIR" 2>/dev/null | awk 'NR==2 {print "Beskikbare skyfspasie: " $4}'
}

cmd_monitor_url() {
    load_config

    if [ "${INSTALL_DASHBOARD:-no}" != "yes" ]; then
        echo "Monitor-aftakking is nie geaktiveer nie."
        exit 1
    fi

    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    ip=${ip:-localhost}

    echo "http://${ip}:${ICECAST_PORT}/monitor"
}

cmd_start()   { need_root "start";   systemctl start radio-orania.service; }
cmd_stop()    { need_root "stop";    systemctl stop radio-orania.service; }
cmd_restart() { need_root "restart"; systemctl restart radio-orania.service; }

cmd_logs() {
    if [ "${1:-}" = "-f" ]; then
        journalctl -u radio-orania -f
    else
        journalctl -u radio-orania -n 100 --no-pager
    fi
}

cmd_test_stream() {
    load_config

    if [ -z "${STREAM_URL:-}" ]; then
        echo "Geen stroom URL in konfigurasie gevind nie."
        exit 1
    fi

    echo "Toets: $STREAM_URL"

    if curl -Is --max-time 10 "$STREAM_URL" >/dev/null 2>&1; then
        echo "Stroom is bereikbaar."
    else
        echo "Stroom antwoord nie."
        exit 1
    fi
}

cmd_media() {
    if [ -f "$BASE_DIR/filebrowser/credentials.txt" ]; then
        cat "$BASE_DIR/filebrowser/credentials.txt"
    else
        echo "File Browser is nie geïnstalleer nie, of credentials.txt ontbreek."
    fi
}

cmd_backup() {
    need_root "backup"

    mkdir -p "$BASE_DIR/backups"

    local dest
    dest="$BASE_DIR/backups/media-$(date +%Y%m%d-%H%M%S).tar.gz"

    tar -czf "$dest" -C "$BASE_DIR" media

    echo "Rugsteun gestoor: $dest"
}

cmd_reconfigure() {
    need_root "reconfigure"

    if [ ! -x "$INSTALLER_DIR/install.sh" ]; then
        echo "Installer nie gevind by $INSTALLER_DIR nie."
        echo "Klone die repo weer en loop: sudo bash install.sh"
        exit 1
    fi

    bash "$INSTALLER_DIR/install.sh"
}

cmd_update() {
    need_root "update"

    if [ ! -d "$INSTALLER_DIR/.git" ]; then
        echo "Geen git-geskiedenis by $INSTALLER_DIR nie; kan nie outomaties opdateer nie."
        echo "Klone die repo handmatig weer om op te dateer."
        exit 1
    fi

    git -C "$INSTALLER_DIR" pull --ff-only
    bash "$INSTALLER_DIR/install.sh"
}

usage() {
    cat << EOF
Radio Orania Beheerpaneel

Gebruik: radioctl <opdrag>

  status         Wys huidige status van alle dienste
  start          Begin die radio-diens
  stop           Stop die radio-diens
  restart        Herbegin die radio-diens
  logs [-f]      Wys onlangse logs (-f om te volg)
  test-stream    Toets of die stroom URL bereikbaar is
  media          Wys File Browser toegangsbesonderhede
  monitor-url    Wys die netwerk-URL om die op-lug mengsel te monitor
  backup         Skep 'n rugsteun van die mediavouer
  reconfigure    Loop die opstelling-assistent weer
  update         Trek die jongste weergawe en herinstalleer
EOF
}

case "${1:-}" in
    status)       cmd_status ;;
    start)        cmd_start ;;
    stop)         cmd_stop ;;
    restart)      cmd_restart ;;
    logs)         shift; cmd_logs "${1:-}" ;;
    test-stream)  cmd_test_stream ;;
    media)        cmd_media ;;
    monitor-url)  cmd_monitor_url ;;
    backup)       cmd_backup ;;
    reconfigure)  cmd_reconfigure ;;
    update)       cmd_update ;;
    ""|-h|--help|help) usage ;;
    *)
        echo "Onbekende opdrag: ${1:-}"
        echo
        usage
        exit 1
        ;;
esac
