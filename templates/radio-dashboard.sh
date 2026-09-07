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

# 'n Ligte, suiwer-bash "golfvorm" wat by elke verversing 'n stap
# aanbeweeg. Dit is opsetlik net dekoratief (nie 'n regte oudio-
# ontleding nie) - 'n vorige weergawe het elke sekonde 'n nuwe ffmpeg-
# proses geskep om die klankvlak te meet, wat broos was (dikwels leeg)
# en die teken-siklus onvoorspelbaar vertraag het. 'n Suiwer
# string-opsoek loop altyd, is oombliklik, en skep nooit 'n subproses nie.
WAVE_PATTERNS=(
    "▁▂▃▅▇▅▃▂▁▂▃▅▇▅▃▂▁▂▃▅▇▅▃▂"
    "▂▃▅▇▅▃▂▁▂▃▅▇▅▃▂▁▂▃▅▇▅▃▂▁"
    "▃▅▇▅▃▂▁▂▃▅▇▅▃▂▁▂▃▅▇▅▃▂▁▂"
    "▅▇▅▃▂▁▂▃▅▇▅▃▂▁▂▃▅▇▅▃▂▁▂▃"
    "▇▅▃▂▁▂▃▅▇▅▃▂▁▂▃▅▇▅▃▂▁▂▃▅"
    "▅▃▂▁▂▃▅▇▅▃▂▁▂▃▅▇▅▃▂▁▂▃▅▇"
)
WAVE_FRAME=0

fake_wave() {
    local idx=$(( WAVE_FRAME % ${#WAVE_PATTERNS[@]} ))
    echo "${WAVE_PATTERNS[$idx]}"
}

toggle_listen() {

    if [ "$PLAYING" = true ]; then

        [ -n "$PLAYER_PID" ] && kill "$PLAYER_PID" 2>/dev/null

        PLAYING=false
        PLAYER_PID=""
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
        echo "  1) Verander stroom URL (primêr)"
        echo "  2) Verander rugsteun-stroom URL"
        echo "  3) Verander musiek/sweeper-verhouding"
        echo "  4) Verander stasienaam"
        echo "  5) Verander ALSA-klanktoestel"
        echo "  6) Verander Heartbeat URL"
        echo "  7) Wys wagwoorde"
        echo "  8) Opdateer sagteware"
        echo "  9) Herkonfigureer (loop opstelling weer)"
        echo "  10) ${RED}Verwyder alles (uninstall)${RESET}"
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
                read -r -p "Rugsteun-stroom URL (leeg om af te skakel): " backup_url
                sudo radioctl set BACKUP_STREAM_URL "$backup_url"
                pause
                ;;
            3)
                read -r -p "Musiek gewig: " mw
                read -r -p "Sweeper gewig: " sw
                sudo radioctl set MUSIC_WEIGHT "$mw"
                sudo radioctl set SWEEPER_WEIGHT "$sw"
                pause
                ;;
            4)
                read -r -p "Nuwe stasienaam: " new_name
                sudo radioctl set STATION_NAME "$new_name"
                pause
                ;;
            5)
                command -v aplay >/dev/null 2>&1 && aplay -l 2>/dev/null
                echo
                read -r -p "ALSA-toestel (bv. default, hw:0,0): " alsa
                sudo radioctl set ALSA_DEVICE "$alsa"
                pause
                ;;
            6)
                read -r -p "Heartbeat URL (leeg om af te skakel): " hb
                sudo radioctl set HEARTBEAT_URL "$hb"
                pause
                ;;
            7)
                clear
                sudo radioctl passwords
                pause
                ;;
            8)
                read -r -p "Opdateer sagteware nou? (Y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    sudo radioctl update
                    pause
                fi
                ;;
            9)
                read -r -p "Herkonfigureer nou? Dit loop die opstelling-vrae weer. (Y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    sudo radioctl reconfigure
                    pause
                fi
                ;;
            10)
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

    # WAVE_FRAME moet BUITE die $(...) subshell hieronder verhoog word -
    # veranderinge binne 'n command substitution se subshell gaan
    # verlore sodra dit klaar is, en die "animasie" sou nooit beweeg nie.
    WAVE_FRAME=$(( WAVE_FRAME + 1 ))

    local frame
    frame=$(
        draw_banner
        sudo radioctl status --color
        echo

        # Hierdie blok bly altyd twee reëls, of ons nou speel of nie, sodat
        # die raam se totale hoogte nooit tussen verversings verander nie.
        if [ "$PLAYING" = true ]; then
            echo "  ${GREEN}▶ Luister nou${RESET}   $(fake_wave)"
        else
            echo
        fi
        echo

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
