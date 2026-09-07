#!/bin/bash

RESET=$'\033[0m'
BOLD=$'\033[1m'
BLINK=$'\033[5m'
GREEN=$'\033[32m'
RED=$'\033[31m'
CYAN=$'\033[36m'

CURSOR_HOME=$'\033[H'
CLEAR_TO_END=$'\033[0J'
HIDE_CURSOR=$'\033[?25l'
SHOW_CURSOR=$'\033[?25h'

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

pause() {
    echo
    read -r -p "Druk Enter om voort te gaan..." _ || true
}

settings_menu() {

    while true; do

        clear
        echo "${BOLD}Instellings${RESET}"
        echo
        echo "  1) Verander stroom URL"
        echo "  2) Verander musiek/sweeper-verhouding"
        echo "  3) Wys wagwoorde"
        echo "  4) Opdateer sagteware"
        echo "  5) Herkonfigureer (loop opstelling weer)"
        echo "  6) ${RED}Verwyder alles (uninstall)${RESET}"
        echo "  0) Terug na hoofskerm"
        echo

        read -r -p "Kies: " choice || return

        case "$choice" in
            1)
                read -r -p "Nuwe stroom URL: " new_url
                sudo radioctl set STREAM_URL "$new_url"
                pause
                ;;
            2)
                read -r -p "Musiek gewig: " mw
                read -r -p "Sweeper gewig: " sw
                sudo radioctl set MUSIC_WEIGHT "$mw"
                sudo radioctl set SWEEPER_WEIGHT "$sw"
                pause
                ;;
            3)
                clear
                sudo radioctl passwords
                pause
                ;;
            4)
                read -r -p "Opdateer sagteware nou? (Y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    sudo radioctl update
                    pause
                fi
                ;;
            5)
                read -r -p "Herkonfigureer nou? Dit loop die opstelling-vrae weer. (Y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    sudo radioctl reconfigure
                    pause
                fi
                ;;
            6)
                read -r -p "WAARSKUWING: dit verwyder ALLES permanent. Is jy seker? (Y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    sudo radioctl uninstall
                    echo
                    echo "Verwydering voltooi."
                    pause
                    exit 0
                fi
                ;;
            0|"")
                return
                ;;
            *)
                ;;
        esac

    done
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

# Bou die hele raam as EEN string en skryf dit in EEN stap, met die cursor
# na die boonste-linker-hoek geskuif (nie 'n volle "clear" nie). Dit
# oorskryf die vorige raam in plek en vee net die oorblyfsel daarna uit
# (\033[0J) - dus geen sigbare flikkering soos 'n herhaalde clear+herteken
# sou veroorsaak nie.
draw() {

    local frame
    frame=$(
        draw_banner
        sudo radioctl status --color
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

        echo "  [C] Instellings         [Q] Verlaat na shell"
        echo "----------------------------------------------------"

        if [ -n "$STATUS_MSG" ]; then
            echo
            echo "  >> $STATUS_MSG"
        fi
    )

    printf '%s%s\n%s' "$CURSOR_HOME" "$frame" "$CLEAR_TO_END"
}

cleanup() {
    [ -n "$PLAYER_PID" ] && kill "$PLAYER_PID" 2>/dev/null
    printf '%s' "$SHOW_CURSOR"
}

trap cleanup EXIT

clear
printf '%s' "$HIDE_CURSOR"

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
                printf '%s' "$SHOW_CURSOR"
                clear
                sudo radioctl logs | less
                clear
                printf '%s' "$HIDE_CURSOR"
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
            [Cc])
                printf '%s' "$SHOW_CURSOR"
                settings_menu
                clear
                printf '%s' "$HIDE_CURSOR"
                STATUS_MSG=""
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
