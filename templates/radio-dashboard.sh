#!/bin/bash

RESET=$'\033[0m'
BOLD=$'\033[1m'
BLINK=$'\033[5m'
GREEN=$'\033[32m'
RED=$'\033[31m'
CYAN=$'\033[36m'

STATUS_MSG=""
PLAYING=false
PLAYER_PID=""
MONITOR_URL=""

spinner_run() {

    local msg="$1"
    shift

    local out
    out=$(mktemp)

    "$@" >"$out" 2>&1 &
    local pid=$!

    local frames='|/-\'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % 4 ))
        printf "\r  %s %s   " "${frames:$i:1}" "$msg"
        sleep 0.15
    done

    wait "$pid"
    local status=$?

    printf "\r"

    STATUS_MSG="$(cat "$out")"
    rm -f "$out"

    return "$status"
}

# Neem 'n vinnige (0.5s) klankmonster van die stroom en gee 'n eenvoudige
# balk terug wat die volume van daardie oomblik wys - 'n ligte, regte
# vlak-aanduiding sonder om die skerm oor te neem soos 'n volle
# spektrum-ontleder sou doen.
level_bar() {

    local url="$1"
    local width=24

    local vol
    vol=$(timeout 2 ffmpeg -nostdin -i "$url" -t 0.5 -af volumedetect -f null - 2>&1 |
        grep -oE 'mean_volume: [-0-9.]+' | grep -oE '[-0-9.]+')
    vol=${vol:--45}

    local filled
    filled=$(awk -v v="$vol" -v w="$width" 'BEGIN {
        b = (v + 45) / 45 * w
        if (b < 0) b = 0
        if (b > w) b = w
        printf "%d", b
    }')

    local bar=""
    local i

    for ((i = 0; i < width; i++)); do
        if [ "$i" -lt "$filled" ]; then
            bar="${bar}█"
        else
            bar="${bar}░"
        fi
    done

    echo "$bar"
}

toggle_listen() {

    if [ "$PLAYING" = true ]; then

        [ -n "$PLAYER_PID" ] && kill "$PLAYER_PID" 2>/dev/null

        PLAYING=false
        PLAYER_PID=""
        MONITOR_URL=""
        STATUS_MSG="Musiek gestop."

    else

        local url
        url=$(sudo radioctl monitor-url 2>&1)

        if [[ "$url" != http* ]]; then
            STATUS_MSG="$url"
            return
        fi

        if ! command -v mpv >/dev/null 2>&1; then
            STATUS_MSG="mpv is nie geïnstalleer nie."
            return
        fi

        mpv --no-video --really-quiet "$url" >/dev/null 2>&1 &
        PLAYER_PID=$!
        MONITOR_URL="$url"
        PLAYING=true
        STATUS_MSG="Speel nou..."

    fi
}

draw_banner() {

    local on_air=false
    systemctl is-active --quiet radio-orania.service 2>/dev/null && on_air=true

    echo "${CYAN}${BOLD}"
    cat << 'BANNER'
██████╗  █████╗ ██████╗ ██╗ ██████╗
██╔══██╗██╔══██╗██╔══██╗██║██╔═══██╗
██████╔╝███████║██║  ██║██║██║   ██║
██╔══██╗██╔══██║██║  ██║██║██║   ██║
██║  ██║██║  ██║██████╔╝██║╚██████╔╝
╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝ ╚═════╝
        O R A N I A
BANNER
    echo "${RESET}"

    if [ "$on_air" = true ]; then
        echo "            ${BLINK}${GREEN}${BOLD}● ON AIR${RESET}"
    else
        echo "            ${RED}${BOLD}○ OFF AIR${RESET}"
    fi

    echo
}

draw() {

    clear
    draw_banner
    sudo radioctl status
    echo

    if [ "$PLAYING" = true ]; then
        echo "  ${GREEN}▶ Luister nou${RESET}"
        echo "  $(level_bar "$MONITOR_URL")"
        echo
    fi

    echo "----------------------------------------------------"
    echo "  [S] Begin   [T] Stop   [R] Herbegin   [L] Logs"

    if [ "$PLAYING" = true ]; then
        echo "  [P] Stop Luister        [M] Media   [B] Rugsteun"
    else
        echo "  [P] Luister             [M] Media   [B] Rugsteun"
    fi

    echo "  [Q] Verlaat na shell"
    echo "----------------------------------------------------"

    if [ -n "$STATUS_MSG" ]; then
        echo
        echo "  >> $STATUS_MSG"
    fi
}

cleanup() {
    [ -n "$PLAYER_PID" ] && kill "$PLAYER_PID" 2>/dev/null
}

trap cleanup EXIT

while true; do

    draw

    read_timeout=5
    [ "$PLAYING" = true ] && read_timeout=1

    read -r -t "$read_timeout" -n 1 key
    read_status=$?

    # Statuskode > 128 beteken die tydgrens het net verstryk (normaal,
    # verfris net weer). Enigiets anders wat nie 0 is nie (bv. 1) beteken
    # stdin is heeltemal toe (EOF) - sonder hierdie tak sou die lus
    # oneindig vinnig bly herhaal ipv om uit te gaan.
    if [ "$read_status" -eq 0 ]; then

        echo

        case "$key" in
            [Ss])
                spinner_run "Begin radio..." sudo radioctl start
                [ -z "$STATUS_MSG" ] && STATUS_MSG="Radio begin."
                ;;
            [Tt])
                spinner_run "Stop radio..." sudo radioctl stop
                [ -z "$STATUS_MSG" ] && STATUS_MSG="Radio gestop."
                ;;
            [Rr])
                spinner_run "Herbegin radio..." sudo radioctl restart
                [ -z "$STATUS_MSG" ] && STATUS_MSG="Radio herbegin."
                ;;
            [Ll])
                clear
                sudo radioctl logs | less
                STATUS_MSG=""
                ;;
            [Pp])
                toggle_listen
                ;;
            [Mm])
                STATUS_MSG=$(sudo radioctl media 2>&1)
                ;;
            [Bb])
                spinner_run "Skep rugsteun..." sudo radioctl backup
                ;;
            [Qq])
                clear
                break
                ;;
            *)
                STATUS_MSG="Onbekende opsie: $key"
                ;;
        esac

    elif [ "$read_status" -lt 128 ]; then
        # stdin is toe (nie 'n interaktiewe terminaal meer nie) - gaan uit.
        break
    fi

done
