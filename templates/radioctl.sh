#!/bin/bash

set -euo pipefail

BASE_DIR="/opt/radio-orania"
CONFIG_FILE="$BASE_DIR/config/environment.conf"
INSTALLER_DIR="$BASE_DIR/installer"
SOCKET_FILE="$BASE_DIR/liquidsoap/socket"

contains_shell_metachars() {
    case "$1" in
        *[\"\'\`\;\\\$]*) return 0 ;;
    esac
    return 1
}

is_valid_plain_text() {
    [ -n "$1" ] && ! contains_shell_metachars "$1"
}

is_valid_url() {
    [ -n "$1" ] || return 1
    [[ "$1" =~ ^https?:// ]] || return 1
    contains_shell_metachars "$1" && return 1
    case "$1" in
        *[[:space:]]*) return 1 ;;
    esac
    return 0
}

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

    local force="${1:-}"

    local green="" red="" bold="" reset=""
    if [ -t 1 ] || [ "$force" = "--color" ]; then
        green=$'\033[32m'
        red=$'\033[31m'
        bold=$'\033[1m'
        reset=$'\033[0m'
    fi

    echo "${bold}Sender Naam${reset}   : ${STATION_NAME:-onbekend}"
    echo "${bold}Stroom URL${reset}    : ${STREAM_URL:-onbekend}"

    local active_label="onbekend" active_url=""
    if [ -f "$BASE_DIR/liquidsoap/active_source" ]; then
        case "$(cat "$BASE_DIR/liquidsoap/active_source" 2>/dev/null)" in
            primer)    active_label="Hoofstroom";       active_url="${STREAM_URL:-}" ;;
            rugsteun)  active_label="Rugsteun-stroom";  active_url="${BACKUP_STREAM_URL:-}" ;;
            noodmusiek) active_label="Noodmusiek (plaaslik)" ;;
        esac
    fi
    if [ -n "$active_url" ]; then
        echo "${bold}Aktiewe Bron${reset}  : ${active_label} (${active_url})"
    else
        echo "${bold}Aktiewe Bron${reset}  : ${active_label}"
    fi

    local uptime_str=""
    if systemctl is-active --quiet radio-orania.service 2>/dev/null; then
        local started
        started=$(systemctl show radio-orania.service -p ActiveEnterTimestamp --value 2>/dev/null)
        if [ -n "$started" ] && [ "$started" != "n/a" ]; then
            local started_ts now_ts elapsed
            started_ts=$(date -d "$started" +%s 2>/dev/null || echo "")
            if [ -n "$started_ts" ]; then
                now_ts=$(date +%s)
                elapsed=$(( now_ts - started_ts ))
                uptime_str="$(( elapsed / 3600 ))h $(( (elapsed % 3600) / 60 ))m"
            fi
        fi
    fi
    echo "${bold}Aanlyn${reset}        : ${uptime_str:-nie aktief nie}"

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

cmd_dash() {
    if [ ! -x /usr/local/bin/radio-dash ]; then
        echo "Beheerpaneel-skerm is nie geïnstalleer nie."
        exit 1
    fi

    exec /usr/local/bin/radio-dash
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

cmd_bufferstat() {
    if ! command -v socat >/dev/null 2>&1; then
        echo "Netwerk-buffer   : onbekend (socat nie geïnstalleer nie)"
        return
    fi

    if [ ! -S "$SOCKET_FILE" ]; then
        echo "Netwerk-buffer   : onbekend (radio loop nie, of nie geaktiveer nie)"
        return
    fi

    local ns=""
    if [ -f "$BASE_DIR/liquidsoap/active_source" ]; then
        case "$(cat "$BASE_DIR/liquidsoap/active_source" 2>/dev/null)" in
            primer)    ns="radio_input" ;;
            rugsteun)  ns="backup_input" ;;
        esac
    fi

    if [ -z "$ns" ]; then
        echo "Netwerk-buffer   : n.v.t. (noodmusiek is op-lug)"
        return
    fi

    # "quit" ná die opdrag laat Liquidsoap self die koppeling toemaak sodra
    # dit geantwoord het; "timeout" is 'n bykomende slot-wagter sodat 'n
    # onverwagte hang nooit die dashboard se herteken-lus kan blokkeer nie.
    local resp
    resp=$(printf '%s\nquit\n' "${ns}.buffer_length" \
        | timeout 2 socat - "UNIX-CONNECT:${SOCKET_FILE}" 2>/dev/null \
        | sed -n '1p') || true

    if [[ "$resp" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        printf 'Netwerk-buffer   : %.1fs\n' "$resp"
    else
        echo "Netwerk-buffer   : onbekend"
    fi
}

cmd_datausage() {
    if ! command -v vnstat >/dev/null 2>&1; then
        echo "Data verbruik    : onbekend (vnstat nie geïnstalleer nie)"
        return
    fi

    local iface line today month
    iface=$(ip route show default 2>/dev/null | awk '{print $5; exit}') || true

    if [ -n "$iface" ]; then
        line=$(timeout 3 vnstat --oneline -i "$iface" 2>/dev/null) || true
    else
        line=$(timeout 3 vnstat --oneline 2>/dev/null) || true
    fi

    if [ -z "$line" ]; then
        echo "Data verbruik    : onbekend"
        return
    fi

    # --oneline se veldvolgorde (vnstat-dokumentasie): 6=totaal vandag,
    # 11=totaal hierdie maand.
    today=$(printf '%s' "$line" | awk -F';' '{print $6}') || true
    month=$(printf '%s' "$line" | awk -F';' '{print $11}') || true

    echo "Data verbruik    : Vandag ${today:-onbekend}   Maand ${month:-onbekend}"
}

cmd_sysstats() {
    local load
    load=$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null) || true
    echo "CPU-las (1/5/15m): ${load:-onbekend}"

    if command -v free >/dev/null 2>&1; then
        free -h | awk '/^Mem:/ {print "Geheue           : " $3 " / " $2 " in gebruik"}'
    else
        echo "Geheue           : onbekend"
    fi

    df -h "$BASE_DIR" 2>/dev/null | awk 'NR==2 {print "Skyfspasie       : " $3 " / " $2 " in gebruik (" $4 " beskikbaar)"}'

    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        local temp_raw temp_c
        temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null) || true
        temp_c=$(awk -v t="${temp_raw:-}" 'BEGIN { if (t != "") printf "%.1f", t / 1000 }') || true
        echo "CPU-temperatuur  : ${temp_c:-onbekend}°C"
    else
        echo "CPU-temperatuur  : onbekend"
    fi
}

# --- BEHEER-oortjie: handmatige bron-wissel -----------------------------
#
# Skryf net 'n woord na radio.liq se source_override-lêer - Liquidsoap
# lees dit self elke 2 sekondes (sien radio.liq), geen socat/socket nodig
# nie. Die wissel is doelbewus TYDELIK: radio.liq stel dit terug na
# "outomaties" by elke diens-begin (sien radio.liq se opmerking daaroor),
# so 'n vergete wissel bly nie oor 'n herbegin/herlaai heen vassit nie.
cmd_wissel() {
    need_root "wissel <1|2|musiek|outomaties>"
    load_config

    local choice="$1" val label

    case "$choice" in
        1)
            val="primer"
            label="Bron 1"
            ;;
        2)
            if [ -z "${BACKUP_STREAM_URL:-}" ]; then
                echo "Geen rugsteun-stroom ingestel nie."
                exit 1
            fi
            val="rugsteun"
            label="Bron 2"
            ;;
        musiek)
            val="noodmusiek"
            label="Musiek"
            ;;
        outomaties|"")
            val=""
            label="Outomaties"
            ;;
        *)
            echo "Gebruik: radioctl wissel <1|2|musiek|outomaties>"
            exit 1
            ;;
    esac

    local override_file="$BASE_DIR/liquidsoap/source_override"
    local tmp
    tmp=$(mktemp)
    printf '%s' "$val" > "$tmp"
    install -m 644 -o radio-orania -g audio "$tmp" "$override_file"
    rm -f "$tmp"

    echo "Bron gewissel na: $label"
}

# --- TOETS-oortjie: foutsimulasie vir die dashboard ---------------------
#
# Elke toets is doelbewus SELFSTANDIG omkeerbaar (of outomaties, of via 'n
# eksplisiete "restore"-opdrag), en raak nooit meer as wat nodig is nie -
# sien docs/adr/0001-dashboard-single-screen-tab-navigation.md vir die
# volledige besluit-geskiedenis hieroor.

TEST_INTERNET_MARKER="$BASE_DIR/liquidsoap/.test_internet_blocked"
TEST_INTERNET_REVERT_SECS=60
TEST_INTERNET_REVERT_UNIT="radio-orania-test-internet-revert"

test_source_id() {
    case "$1" in
        1) echo "radio_input" ;;
        2) echo "backup_input" ;;
        *) return 1 ;;
    esac
}

test_source_marker() {
    echo "$BASE_DIR/liquidsoap/.test_bron${1}_stopped"
}

cmd_test_source_status() {
    local n="$1" marker
    marker=$(test_source_marker "$n") || { echo "onbekend"; exit 1; }

    if [ -f "$marker" ]; then
        echo "gestop"
    else
        echo "loop"
    fi
}

cmd_test_source_stop() {
    need_root "test-source-stop <1|2>"
    load_config

    local n="$1" id marker
    id=$(test_source_id "$n") || { echo "Ongeldige bron: $n"; exit 1; }

    if [ "$n" = "2" ] && [ -z "${BACKUP_STREAM_URL:-}" ]; then
        echo "Geen rugsteun-stroom ingestel nie."
        exit 1
    fi

    if command -v socat >/dev/null 2>&1 && [ -S "$SOCKET_FILE" ]; then
        printf '%s\nquit\n' "${id}.stop" \
            | timeout 2 socat - "UNIX-CONNECT:${SOCKET_FILE}" >/dev/null 2>&1 || true
    fi

    marker=$(test_source_marker "$n")
    touch "$marker"

    echo "Bron $n se wegval gesimuleer."
}

cmd_test_source_start() {
    need_root "test-source-start <1|2>"

    local n="$1" id marker
    id=$(test_source_id "$n") || { echo "Ongeldige bron: $n"; exit 1; }

    if command -v socat >/dev/null 2>&1 && [ -S "$SOCKET_FILE" ]; then
        printf '%s\nquit\n' "${id}.start" \
            | timeout 2 socat - "UNIX-CONNECT:${SOCKET_FILE}" >/dev/null 2>&1 || true
    fi

    marker=$(test_source_marker "$n")
    rm -f "$marker"

    echo "Bron $n herstel."
}

cmd_test_internet_status() {
    if [ -f "$TEST_INTERNET_MARKER" ]; then
        echo "geblokkeer"
    else
        echo "normaal"
    fi
}

cmd_test_internet_block() {
    need_root "test-internet-block"

    if ! command -v iptables >/dev/null 2>&1; then
        echo "iptables nie geïnstalleer nie."
        exit 1
    fi

    if [ -f "$TEST_INTERNET_MARKER" ]; then
        echo "Internet-blokkade is klaar aktief."
        exit 0
    fi

    # Reeds-gevestigde koppelinge (soos 'n bestaande SSH-sessie) bly
    # toegelaat - net NUWE uitgaande koppelinge word geblokkeer. Albei
    # reëls dra 'n unieke comment-etiket sodat restore() net ONS reëls
    # verwyder, nooit enige reeds-bestaande firewall-reël nie.
    iptables -I OUTPUT 1 \
        -m state --state ESTABLISHED,RELATED \
        -m comment --comment radio-orania-test-established \
        -j ACCEPT
    iptables -A OUTPUT \
        -m comment --comment radio-orania-test \
        -j DROP

    touch "$TEST_INTERNET_MARKER"

    if command -v systemd-run >/dev/null 2>&1; then
        systemd-run --unit="$TEST_INTERNET_REVERT_UNIT" \
            --on-active="$TEST_INTERNET_REVERT_SECS" \
            /usr/local/bin/radioctl test-internet-restore >/dev/null 2>&1 || true
    fi

    echo "Internet geblokkeer (herstel outomaties na ${TEST_INTERNET_REVERT_SECS}s, of kies hierdie opsie weer)."
}

cmd_test_internet_restore() {
    need_root "test-internet-restore"

    if command -v iptables >/dev/null 2>&1; then
        while iptables -C OUTPUT -m comment --comment radio-orania-test -j DROP 2>/dev/null; do
            iptables -D OUTPUT -m comment --comment radio-orania-test -j DROP
        done
        while iptables -C OUTPUT -m state --state ESTABLISHED,RELATED -m comment --comment radio-orania-test-established -j ACCEPT 2>/dev/null; do
            iptables -D OUTPUT -m state --state ESTABLISHED,RELATED -m comment --comment radio-orania-test-established -j ACCEPT
        done
    fi

    rm -f "$TEST_INTERNET_MARKER"

    systemctl stop "${TEST_INTERNET_REVERT_UNIT}.service" >/dev/null 2>&1 || true

    echo "Internet herstel."
}

cmd_test_service_crash() {
    need_root "test-service-crash"

    systemctl kill --signal=SIGKILL radio-orania.service

    echo "Diens doodgemaak - wag ~5s vir outo-herstel (Restart=always)."
}

cmd_test_heartbeat() {
    load_config

    if [ -z "${HEARTBEAT_URL:-}" ]; then
        echo "Heartbeat-toets: geen HEARTBEAT_URL ingestel nie."
        exit 1
    fi

    if curl -fsS --max-time 10 -o /dev/null "$HEARTBEAT_URL"; then
        echo "Heartbeat-toets: geslaag."
    else
        echo "Heartbeat-toets: misluk."
        exit 1
    fi
}

cmd_test_soundcard() {
    need_root "test-soundcard"
    load_config

    if ! command -v speaker-test >/dev/null 2>&1; then
        echo "Klankkaart-toets: onbekend (speaker-test nie geïnstalleer nie)."
        exit 1
    fi

    if timeout 3 speaker-test -D "${ALSA_DEVICE:-default}" -c 2 -t sine -f 1000 -l 1 >/dev/null 2>&1; then
        echo "Klankkaart-toets: geslaag (${ALSA_DEVICE:-default})."
    else
        echo "Klankkaart-toets: misluk (${ALSA_DEVICE:-default} dalk in gebruik deur die radio-diens, of nie bereikbaar nie)."
        exit 1
    fi
}

SETTABLE_KEYS="STREAM_URL BACKUP_STREAM_URL MUSIC_WEIGHT SWEEPER_WEIGHT ALSA_DEVICE STATION_NAME HEARTBEAT_URL STREAM_BUFFER_MAX PRIMARY_SOURCE"

with_installer_config() {
    # persist_installer.sh verwyder doelbewus die installer se eie
    # config-kopie (om nie geheime te verdubbel nie) - herstel dit net
    # tydelik sodat die installer-skripte die nuwe waardes kan lees.
    mkdir -p "$INSTALLER_DIR/config"
    cp "$CONFIG_FILE" "$INSTALLER_DIR/config/environment.conf"

    set +e
    "$@"
    local status=$?
    set -e

    rm -f "$INSTALLER_DIR/config/environment.conf"
    return "$status"
}

cmd_set() {
    need_root "set <SLEUTEL> <WAARDE>"
    load_config

    if [ "$#" -lt 2 ]; then
        echo "Gebruik: radioctl set <SLEUTEL> <WAARDE>"
        echo "Sleutels: $SETTABLE_KEYS"
        exit 1
    fi

    local key="$1"
    local value="$2"

    case "$key" in
        STREAM_URL)
            is_valid_url "$value" || {
                echo "Ongeldige URL. Moet met http:// of https:// begin, geen aanhalingstekens/spasies nie."
                exit 1
            }
            ;;
        BACKUP_STREAM_URL|HEARTBEAT_URL)
            if [ -n "$value" ] && ! is_valid_url "$value"; then
                echo "Ongeldige URL. Moet met http:// of https:// begin, geen aanhalingstekens/spasies nie."
                echo "(Laat leeg - 'radioctl set $key \"\"' - om dit af te skakel.)"
                exit 1
            fi
            ;;
        MUSIC_WEIGHT|SWEEPER_WEIGHT|STREAM_BUFFER_MAX)
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ]; then
                echo "Moet 'n positiewe heelgetal wees."
                exit 1
            fi
            ;;
        ALSA_DEVICE)
            is_valid_plain_text "$value" || {
                echo "Ongeldige ALSA-toestel."
                exit 1
            }
            ;;
        STATION_NAME)
            is_valid_plain_text "$value" || {
                echo "Sender naam mag nie aanhalingstekens, backticks, \$ of ; bevat nie."
                exit 1
            }
            ;;
        PRIMARY_SOURCE)
            case "$value" in
                1|2) ;;
                *)
                    echo "Moet 1 of 2 wees."
                    exit 1
                    ;;
            esac
            if [ "$value" = "2" ] && [ -z "${BACKUP_STREAM_URL:-}" ]; then
                echo "Kan nie Bron 2 as primêr stel nie - geen rugsteun-stroom is ingestel nie."
                exit 1
            fi
            ;;
        *)
            echo "Onbekende of nie-verstelbare instelling: $key"
            echo "Beskikbaar: $SETTABLE_KEYS"
            exit 1
            ;;
    esac

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Konfigurasie ontbreek: $CONFIG_FILE"
        exit 1
    fi

    local tmp
    tmp=$(mktemp)

    grep -v "^${key}=" "$CONFIG_FILE" > "$tmp"
    printf '%s=%q\n' "$key" "$value" >> "$tmp"

    # 'n Primêre bron wat op Bron 2 staan, is betekenisloos sonder 'n
    # rugsteun-stroom (en verwys na 'n backup_radio wat dan glad nie
    # meer in radio.liq bestaan nie) - stel dit stil terug na 1 saam
    # met hierdie wysiging, i.p.v. 'n dooie verwysing agter te laat.
    local primary_reset_note=""
    if [ "$key" = "BACKUP_STREAM_URL" ] && [ -z "$value" ] && [ "${PRIMARY_SOURCE:-1}" = "2" ]; then
        grep -v '^PRIMARY_SOURCE=' "$tmp" > "${tmp}.2"
        mv "${tmp}.2" "$tmp"
        printf '%s=%q\n' "PRIMARY_SOURCE" "1" >> "$tmp"
        primary_reset_note=" Primêre bron is ook teruggestel na 1."
    fi

    install -m 600 -o radio-orania -g audio "$tmp" "$CONFIG_FILE"
    rm -f "$tmp"

    case "$key" in
        STREAM_URL|BACKUP_STREAM_URL|MUSIC_WEIGHT|SWEEPER_WEIGHT|ALSA_DEVICE|STREAM_BUFFER_MAX|PRIMARY_SOURCE)
            if [ ! -x "$INSTALLER_DIR/scripts/liquidsoap.sh" ]; then
                echo "$key gestoor, maar kon nie outomaties toegepas word nie (installer ontbreek)."
            elif with_installer_config bash "$INSTALLER_DIR/scripts/liquidsoap.sh" >/dev/null; then
                systemctl restart radio-orania.service
                echo "$key opgedateer na '$value' en toegepas.$primary_reset_note"
            else
                echo "$key gestoor, maar kon nie toegepas word nie - die nuwe waarde het Liquidsoap se kontrole gedruip."
                exit 1
            fi
            ;;
        STATION_NAME)
            if [ ! -x "$INSTALLER_DIR/scripts/service.sh" ]; then
                echo "$key gestoor, maar kon nie outomaties toegepas word nie (installer ontbreek)."
            elif with_installer_config bash "$INSTALLER_DIR/scripts/service.sh" >/dev/null; then
                echo "$key opgedateer na '$value' en toegepas."
            else
                echo "$key gestoor, maar kon nie toegepas word nie."
                exit 1
            fi
            ;;
        HEARTBEAT_URL)
            if [ ! -x "$INSTALLER_DIR/scripts/monitoring.sh" ]; then
                echo "$key gestoor, maar kon nie outomaties toegepas word nie (installer ontbreek)."
            elif with_installer_config bash "$INSTALLER_DIR/scripts/monitoring.sh" >/dev/null; then
                echo "$key opgedateer na '$value' en toegepas."
            else
                echo "$key gestoor, maar kon nie toegepas word nie."
                exit 1
            fi
            ;;
    esac
}

cmd_passwords() {
    need_root "passwords"

    load_config

    echo "=== Wagwoorde ==="
    echo

    if [ -f "$BASE_DIR/filebrowser/credentials.txt" ]; then
        echo "-- File Browser --"
        cat "$BASE_DIR/filebrowser/credentials.txt"
        echo
    fi

    if [ -f "$BASE_DIR/config/radio-admin-credentials.txt" ]; then
        echo "-- Beheerpaneel (radio-admin) --"
        cat "$BASE_DIR/config/radio-admin-credentials.txt"
        echo
    fi

    if [ -n "${ICECAST_SOURCE_PASSWORD:-}" ]; then
        echo "-- Monitor-aftakking (Icecast bron-wagwoord) --"
        echo "$ICECAST_SOURCE_PASSWORD"
    fi
}

cmd_uninstall() {
    need_root "uninstall"

    if [ ! -x "$INSTALLER_DIR/uninstall.sh" ]; then
        echo "Uninstaller nie gevind by $INSTALLER_DIR nie."
        exit 1
    fi

    bash "$INSTALLER_DIR/uninstall.sh"
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

  dash           Bring die beheerpaneel-skerm terug
  status         Wys huidige status van alle dienste
  start          Begin die radio-diens
  stop           Stop die radio-diens
  restart        Herbegin die radio-diens
  logs [-f]      Wys onlangse logs (-f om te volg)
  test-stream    Toets of die stroom URL bereikbaar is
  media          Wys File Browser toegangsbesonderhede
  monitor-url    Wys die netwerk-URL om die op-lug mengsel te monitor
  backup         Skep 'n rugsteun van die mediavouer
  bufferstat     Wys die regstreekse netwerk-buffer van die aktiewe bron
  datausage      Wys data-verbruik vandag/hierdie maand (vnstat)
  sysstats       Wys CPU-las, geheue, skyfspasie en CPU-temperatuur
  set <S> <W>    Verander 'n instelling ($SETTABLE_KEYS)
  wissel <T>     Wissel bron: 1, 2, musiek, of outomaties (tydelik)
  passwords      Wys al die gestoorde wagwoorde
  reconfigure    Loop die opstelling-assistent weer
  update         Trek die jongste weergawe en herinstalleer
  uninstall      Verwyder die hele installasie

  Foutsimulasie (TOETS-oortjie op die beheerpaneel-skerm):
  test-source-status <1|2>   Wys of bron 1/2 tans gestop (gesimuleer) is
  test-source-stop <1|2>     Simuleer bron 1/2 se wegval
  test-source-start <1|2>    Herstel bron 1/2
  test-internet-status       Wys of die toets-internetblokkade tans aktief is
  test-internet-block        Blokkeer alle nuwe uitgaande verkeer (60s outo-herstel)
  test-internet-restore      Herstel internet dadelik
  test-service-crash         Maak radio-orania.service dood (toets outo-herstel)
  test-heartbeat             Stuur een heartbeat-oproep en wys slaag/faal
  test-soundcard             Speel 'n toets-toon na die ALSA-toestel
EOF
}

case "${1:-}" in
    dash)         cmd_dash ;;
    status)       shift; cmd_status "${1:-}" ;;
    start)        cmd_start ;;
    stop)         cmd_stop ;;
    restart)      cmd_restart ;;
    logs)         shift; cmd_logs "${1:-}" ;;
    test-stream)  cmd_test_stream ;;
    media)        cmd_media ;;
    monitor-url)  cmd_monitor_url ;;
    backup)       cmd_backup ;;
    bufferstat)   cmd_bufferstat ;;
    datausage)    cmd_datausage ;;
    sysstats)     cmd_sysstats ;;
    set)          shift; cmd_set "$@" ;;
    wissel)       shift; cmd_wissel "${1:-}" ;;
    passwords)    cmd_passwords ;;
    reconfigure)  cmd_reconfigure ;;
    update)       cmd_update ;;
    uninstall)    cmd_uninstall ;;
    test-source-status)   shift; cmd_test_source_status "${1:-}" ;;
    test-source-stop)     shift; cmd_test_source_stop "${1:-}" ;;
    test-source-start)    shift; cmd_test_source_start "${1:-}" ;;
    test-internet-status)  cmd_test_internet_status ;;
    test-internet-block)   cmd_test_internet_block ;;
    test-internet-restore) cmd_test_internet_restore ;;
    test-service-crash)    cmd_test_service_crash ;;
    test-heartbeat)        cmd_test_heartbeat ;;
    test-soundcard)        cmd_test_soundcard ;;
    ""|-h|--help|help) usage ;;
    *)
        echo "Onbekende opdrag: ${1:-}"
        echo
        usage
        exit 1
        ;;
esac
