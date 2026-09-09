#!/bin/bash

RESET=$'\033[0m'
BOLD=$'\033[1m'
BLINK=$'\033[5m'
GREEN=$'\033[32m'
RED=$'\033[31m'
CYAN=$'\033[36m'
GRAY=$'\033[90m'
ORANGE=$'\033[1;33m'
BLUE=$'\033[1;34m'

# PRIMARY/SECONDARY is die dashboard se twee "aksentkleure" (gebruik vir die
# baniere, aksentbalk en afdelingskoppe) - hulle waarde word deur
# apply_color_scheme() gestel, NIE hier hardgekodeer nie, sodat 'n gebruiker
# dit via die Instellings-kieslys kan verander. Bold geel/blou (i.p.v. 256-
# kleur "regte" oranje) werk betroubaar op sowel SSH-terminale as die kaal
# fisiese Linux-konsole (tty1), wat nie 256 kleure ondersteun nie.
PRIMARY=""
SECONDARY=""
COLOR_SCHEME_FILE="$HOME/.radio-dashboard-colors"

apply_color_scheme() {
    case "$1" in
        sianiel)
            PRIMARY="$CYAN"
            SECONDARY="$CYAN"
            ;;
        groen)
            PRIMARY="$GREEN"
            SECONDARY="$CYAN"
            ;;
        *)
            PRIMARY="$ORANGE"
            SECONDARY="$BLUE"
            ;;
    esac
}

load_color_scheme() {
    local scheme="oranje-blou"
    [ -r "$COLOR_SCHEME_FILE" ] && scheme=$(<"$COLOR_SCHEME_FILE")
    apply_color_scheme "$scheme"
}

load_color_scheme

CURSOR_HOME=$'\033[H'
CLEAR_TO_END=$'\033[0J'
CLEAR_LINE=$'\033[K'
HIDE_CURSOR=$'\033[?25l'
SHOW_CURSOR=$'\033[?25h'

STATUS_MSG=""
PLAYING=false
PLAYER_PID=""

# INSTELLINGS en GEVAARLIK leef nou altyd op die hoofskerm (nie meer 'n
# aparte oortjie-skerm nie) - hierdie twee booleans bepaal net of hulle
# items op die oomblik oop- of toegevou is (sien draw_main_body()).
SHOW_SETTINGS=false
SHOW_DANGER=false

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

STATION_BANNER_KEY=""
STATION_BANNER_TEXT=""

# Stelsel-inligting (bufferstat/datausage/sysstats) kas 5 sekondes lank
# i.p.v. by ELKE draw() herbereken te word - elk van hierdie drie
# "sudo radioctl"-oproepe het sy eie interne timeout (tot 2-3s vir
# socat/vnstat, sien radioctl.sh), en draw() kan tydens Monitor-speel so
# gereeld soos elke sekonde loop. Sonder hierdie kas kan 'n stadige/hangende
# socat of vnstat die hele lewendige skerm (ON AIR, klankvlak-balk) op ELKE
# verversing vertraag, nie net wanneer die syfers werklik ververs word nie.
STELSEL_BODY_CACHE=""
STELSEL_BODY_TS=0
STELSEL_REFRESH_SECS=5

# Genereer 'n groot bloklettter-baniere vir die stasienaam via 'toilet'
# (indien geïnstalleer), begrens tot die beskikbare terminaalbreedte, en
# kas dit in 'n GLOBALE veranderlike. Belangrik: hierdie funksie moet as
# 'n GEWONE opdrag aangeroep word (nie via "$(...)" nie) - 'n command
# substitution loop in 'n subshell, en veranderinge daarbinne (soos die
# kas) sou net verlore gaan, presies soos met WAVE_FRAME hierbo. Sodoende
# hoef 'n nuwe proses nie by ELKE skerm-verversing geskep te word nie,
# net wanneer die naam of terminaalbreedte werklik verander.
# Toilet se "-w" begrensing laat elke reël wel binne die versoekte
# breedte pas, maar as die teks nie EENLYNIG pas nie, deel dit dit eerder
# VERTIKAAL op in bykomende, gestapelde blokke (elke reël is smal genoeg,
# maar die geheel word onnodig hoog en lyk stukkend/oorvleuelend - presies
# die "wrap" wat gerapporteer is). 'n Blote reël-breedte-toets sou dit
# mis, want elke gestapelde reël voldoen steeds aan die breedte-perk.
# Vergelyk dus eerder die reël-TELLING teen 'n onbeperkte weergawe: as
# hulle ooreenstem, het toilet dit op sy natuurlike een-blok hoogte kon
# vertoon (geen stapeling nie); as die beperkte weergawe meer reëls het,
# hét dit gestapel, en ons verwerp daardie font vir hierdie breedte.
toilet_fits_on_one_line() {
    local font="$1" name="$2" width="$3"

    local natural_rows constrained_rows
    natural_rows=$(toilet -f "$font" -w 9999 -- "$name" 2>/dev/null | wc -l)
    [ "$natural_rows" -eq 0 ] && return 1

    constrained_rows=$(toilet -f "$font" -w "$width" -- "$name" 2>/dev/null | wc -l)

    [ "$constrained_rows" -eq "$natural_rows" ]
}

# Komposeer 'n groot bloklettter-baniere MET 'n 3D-skaduwee: die gekose
# blokfont word twee keer geplaas op 'n karakter-rooster - eers 'n
# verskuifde grys kopie (die skaduwee), dan die helder aksentkleur-
# oorspronklike (PRIMARY) bo-oor. Waar die twee oorvleuel wen die hoof-teks
# altyd, presies soos 'n regte lig-en-skaduwee-effek sou werk.
compose_shadowed_banner() {
    local name="$1"
    local width="$2"
    local font="$3"
    local dy=1 dx=1

    local raw
    raw=$(toilet -f "$font" -w "$width" -- "$name" 2>/dev/null)
    [ -z "$raw" ] && return 1

    local -a lines
    mapfile -t lines <<< "$raw"

    local n=${#lines[@]}
    local w=0 i len
    for i in "${!lines[@]}"; do
        len=${#lines[$i]}
        (( len > w )) && w=$len
    done
    [ "$w" -eq 0 ] && return 1

    for i in "${!lines[@]}"; do
        printf -v 'lines[i]' '%-*s' "$w" "${lines[$i]}"
    done

    local out_rows=$(( n + dy ))
    local out_cols=$(( w + dx ))

    local -a main_grid shadow_grid
    local blank
    blank=$(printf '%*s' "$out_cols" '')
    for ((r = 0; r < out_rows; r++)); do
        main_grid[r]="$blank"
        shadow_grid[r]="$blank"
    done

    local r c row ch pos
    for ((r = 0; r < n; r++)); do
        row="${lines[$r]}"
        for ((c = 0; c < w; c++)); do
            ch="${row:c:1}"
            [ "$ch" = " " ] && continue
            pos=$(( r + dy ))
            shadow_grid[pos]="${shadow_grid[pos]:0:c+dx}${ch}${shadow_grid[pos]:c+dx+1}"
        done
    done

    for ((r = 0; r < n; r++)); do
        row="${lines[$r]}"
        for ((c = 0; c < w; c++)); do
            ch="${row:c:1}"
            [ "$ch" = " " ] && continue
            main_grid[r]="${main_grid[r]:0:c}${ch}${main_grid[r]:c+1}"
        done
    done

    local state mch sch out result
    result=""
    for ((r = 0; r < out_rows; r++)); do
        out=""
        state="none"
        for ((c = 0; c < out_cols; c++)); do
            mch="${main_grid[$r]:c:1}"
            sch="${shadow_grid[$r]:c:1}"
            if [ -n "$mch" ] && [ "$mch" != " " ]; then
                if [ "$state" != "main" ]; then
                    out+="${RESET}${PRIMARY}${BOLD}"
                    state="main"
                fi
                out+="$mch"
            elif [ -n "$sch" ] && [ "$sch" != " " ]; then
                if [ "$state" != "shadow" ]; then
                    out+="${RESET}${GRAY}"
                    state="shadow"
                fi
                out+="$sch"
            else
                if [ "$state" != "none" ]; then
                    out+="${RESET}"
                    state="none"
                fi
                out+=" "
            fi
        done
        out+="${RESET}"
        result+="${out}"$'\n'
    done

    printf '%s' "$result"
}

update_station_banner() {
    local name="$1"
    local width="$2"
    local key="${name}|${width}"

    [ "$key" = "$STATION_BANNER_KEY" ] && return

    local dx=1
    local big="" font

    if command -v toilet >/dev/null 2>&1; then
        # Die skaduwee skuif die finale baniere dx kolomme wyer as wat
        # toilet self weet van - versoek dus 'n breedte wat REEDS die
        # skaduwee se ruimte in ag neem ($width - dx), sodat die
        # saamgestelde resultaat (w + dx) nooit die werklike terminaal-
        # breedte kan oorskry nie. Probeer eers die groot font; val terug
        # na 'n kleiner een as dit sou moes stapel/wrap.
        local content_width=$(( width - dx ))
        if [ "$content_width" -gt 0 ]; then
            for font in mono12 mono9; do
                if toilet_fits_on_one_line "$font" "$name" "$content_width"; then
                    big=$(compose_shadowed_banner "$name" "$content_width" "$font")
                    [ -n "$big" ] && break
                fi
            done
        fi
    fi

    if [ -n "$big" ]; then
        STATION_BANNER_TEXT="$big"
    else
        local plain="$name"
        if [ "${#plain}" -gt "$width" ] && [ "$width" -gt 1 ]; then
            plain="${plain:0:$((width - 1))}…"
        fi
        STATION_BANNER_TEXT="${PRIMARY}${BOLD}${plain}${RESET}"
    fi

    STATION_BANNER_KEY="$key"
}

# Moet, soos update_station_banner(), as 'n GEWONE opdrag aangeroep word
# (nie via "$(...)" nie) - anders gaan STELSEL_BODY_CACHE/_TS se
# toekennings verlore sodra die subshell klaar is, en die kas sou nooit
# werk nie.
update_stelsel_body() {
    local now
    now=$(date +%s)

    if [ -n "$STELSEL_BODY_CACHE" ] && [ $(( now - STELSEL_BODY_TS )) -lt "$STELSEL_REFRESH_SECS" ]; then
        return
    fi

    # "Skyfspasie" word uit sysstats se uitset gefiltreer, want status_body
    # (elders in draw()) wys dit klaar (sien cmd_status/cmd_sysstats in
    # radioctl.sh).
    STELSEL_BODY_CACHE=$(
        sudo radioctl bufferstat
        sudo radioctl datausage
        sudo radioctl sysstats | grep -v '^Skyfspasie'
    )
    STELSEL_BODY_TS="$now"
}

fake_wave() {
    local idx=$(( WAVE_FRAME % ${#WAVE_PATTERNS[@]} ))
    echo "${WAVE_PATTERNS[$idx]}"
}

toggle_listen() {

    if [ "$PLAYING" = true ]; then

        [ -n "$PLAYER_PID" ] && kill "$PLAYER_PID" 2>/dev/null

        PLAYING=false
        PLAYER_PID=""
        STATUS_MSG="Monitor gestop."

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
        STATUS_MSG="Monitor speel..."

    fi
}

# Vra vir 'n reël teks TERWYL die dashboard-raam op die skerm bly staan -
# die versoek word net onder die bestaande raam gewys (nie 'n aparte
# clear-skerm nie); die volgende teken-siklus vee dit outomaties weer
# weg via CLEAR_TO_END, sodat alles as EEN eenvormige skerm oorkom.
inline_prompt() {
    local prompt="$1"
    local __resultvar="$2"
    local reply

    printf '%s%s' "$SHOW_CURSOR" "$prompt"
    read -r reply
    printf '%s' "$HIDE_CURSOR"

    printf -v "$__resultvar" '%s' "$reply"
}

inline_pause() {
    printf '%sDruk Enter om voort te gaan...' "$SHOW_CURSOR"
    read -r _ || true
    printf '%s' "$HIDE_CURSOR"
}

handle_settings_key() {

    local choice="$1"
    local val

    case "$choice" in
        1)
            inline_prompt "Nuwe stroom URL: " val
            STATUS_MSG=$(sudo radioctl set STREAM_URL "$val" 2>&1)
            ;;
        2)
            inline_prompt "Rugsteun-stroom URL (leeg om af te skakel): " val
            STATUS_MSG=$(sudo radioctl set BACKUP_STREAM_URL "$val" 2>&1)
            ;;
        3)
            local mw sw r1 r2
            inline_prompt "Musiek gewig: " mw
            inline_prompt "Sweeper gewig: " sw
            r1=$(sudo radioctl set MUSIC_WEIGHT "$mw" 2>&1)
            r2=$(sudo radioctl set SWEEPER_WEIGHT "$sw" 2>&1)
            STATUS_MSG="$r1 / $r2"
            ;;
        4)
            inline_prompt "Nuwe stasienaam: " val
            STATUS_MSG=$(sudo radioctl set STATION_NAME "$val" 2>&1)
            ;;
        5)
            printf '%s' "$SHOW_CURSOR"
            echo
            command -v aplay >/dev/null 2>&1 && aplay -l 2>/dev/null
            echo
            printf 'ALSA-toestel (bv. default, hw:0,0): '
            read -r val
            printf '%s' "$HIDE_CURSOR"
            STATUS_MSG=$(sudo radioctl set ALSA_DEVICE "$val" 2>&1)
            ;;
        6)
            inline_prompt "Heartbeat URL (leeg om af te skakel): " val
            STATUS_MSG=$(sudo radioctl set HEARTBEAT_URL "$val" 2>&1)
            ;;
        7)
            printf '%s' "$SHOW_CURSOR"
            echo
            sudo radioctl passwords
            inline_pause
            STATUS_MSG=""
            ;;
        8)
            inline_prompt "Opdateer sagteware nou? (Y/N): " val
            if [[ "$val" =~ ^[Yy]$ ]]; then
                printf '%s' "$SHOW_CURSOR"
                sudo radioctl update
                inline_pause
            fi
            STATUS_MSG=""
            ;;
        9)
            inline_prompt "Herkonfigureer nou? Dit loop die opstelling-vrae weer. (Y/N): " val
            if [[ "$val" =~ ^[Yy]$ ]]; then
                printf '%s' "$SHOW_CURSOR"
                sudo radioctl reconfigure
                inline_pause
            fi
            STATUS_MSG=""
            ;;
        10)
            inline_prompt "WAARSKUWING: dit verwyder ALLES permanent. Is jy seker? (Y/N): " val
            if [[ "$val" =~ ^[Yy]$ ]]; then
                printf '%s' "$SHOW_CURSOR"
                sudo radioctl uninstall
                echo
                echo "Verwydering voltooi."
                inline_pause
                exit 0
            fi
            STATUS_MSG=""
            ;;
        11)
            inline_prompt "Maksimum stroom-buffer in sekondes: " val
            STATUS_MSG=$(sudo radioctl set STREAM_BUFFER_MAX "$val" 2>&1)
            ;;
        12)
            printf '%s' "$SHOW_CURSOR"
            echo
            echo "Beskikbare kleurskemas:"
            echo "  1) Oranje/Blou (verstek)"
            echo "  2) Sianiel (klassiek)"
            echo "  3) Groen"
            printf 'Kies: '
            read -r val
            printf '%s' "$HIDE_CURSOR"

            local scheme=""
            case "$val" in
                1) scheme="oranje-blou" ;;
                2) scheme="sianiel" ;;
                3) scheme="groen" ;;
            esac

            if [ -n "$scheme" ]; then
                echo "$scheme" > "$COLOR_SCHEME_FILE"
                apply_color_scheme "$scheme"
                # Die baniere is gekas op naam+breedte (sien update_station_banner)
                # en sou dus nie outomaties die nuwe kleur oorneem nie - forseer
                # 'n herskepping deur die kas-sleutel te herstel.
                STATION_BANNER_KEY=""
                STATUS_MSG="Kleurskema verander."
            else
                STATUS_MSG="Ongeldige keuse."
            fi
            ;;
        0|"")
            STATUS_MSG=""
            ;;
        *)
            STATUS_MSG="Onbekende opsie: $choice"
            ;;
    esac
}

# Lees een "invoer-eenheid" op die hoofskerm. Enkelletter-opdragte (S/T/R/
# ens.) werk oombliklik, geen Enter nodig nie; 'n syfer begin egter 'n
# Instellings/Gevaarlik-opsienommer (tot "12"), wat 'n VOLLE reël moet lees
# tot Enter. Ons lees dus eers EEN karakter stil: as dit 'n syfer is, druk
# ons dit self en lees die res van die reël normaalweg (die terminal
# hanteer eggo/terugspasie self); andersins is dit 'n oombliklike
# enkelletter-opdrag. 'n Los ESC (bv. per ongeluk 'n pyltjie gedruk) word
# stil weggegooi sodat dit nie per abuis as 'n opdrag ontleed word nie.
#
# Uitset (globale veranderlikes, nie 'n plaaslike return-waarde nie, want
# bash-funksies kan net een heelgetal-statuskode teruggee):
#   MAIN_INPUT_TYPE = "line" | "char" | "none"
#   MAIN_INPUT_LINE = die getikte reël (by "line")
#   MAIN_INPUT_CHAR = die enkele karakter (by "char")
#
# Die FUNKSIE se eie return-status is die van die EERSTE (tydgrens-
# beperkte) lees, sodat die hooflus se bestaande uittyd/EOF-onderskeid
# (sien kommentaar by die hooflus) ongeskonde bly.
read_main_key() {
    MAIN_INPUT_TYPE="none"
    MAIN_INPUT_LINE=""
    MAIN_INPUT_CHAR=""

    local c1 status
    IFS= read -rsN1 -t "$read_timeout" c1
    status=$?

    if [ "$status" -ne 0 ]; then
        return "$status"
    fi

    if [[ "$c1" =~ ^[0-9]$ ]]; then
        printf '%sKies: %s' "$SHOW_CURSOR" "$c1"
        local rest="" rest_status
        read -r -t 15 rest
        rest_status=$?
        printf '%s' "$HIDE_CURSOR"
        # 'n Tydgrens hier verhoed dat 'n vergete/toevallige syfer die
        # skerm vir ewig laat hang wag vir Enter - as dit uittyd, gooi ons
        # die halwe invoer eenvoudig weg (MAIN_INPUT_TYPE bly "none") i.p.v.
        # dit as 'n opsienommer te ontleed.
        [ "$rest_status" -ne 0 ] && return 0
        MAIN_INPUT_TYPE="line"
        MAIN_INPUT_LINE="${c1}${rest}"
        return 0
    fi

    if [ "$c1" = $'\033' ]; then
        # Lees greep-vir-greep, presies soos die vorige oortjie-weergawe se
        # parse_settings_escape() gedoen het: as die volgende greep nie '['
        # is nie (of niks kom betyds nie), gooi ons NIKS bykomend weg nie -
        # 'n vinnige regte toetsdruk direk ná 'n los ESC bly dus intak. Kom
        # daar wel '[' (die tipiese pyltjie-voorvoegsel), verbruik net EEN
        # verdere greep (die pyltjie se laaste letter) en gooi dit weg.
        local c2
        IFS= read -rsN1 -t 0.05 c2 || return 0
        if [ "$c2" = "[" ]; then
            IFS= read -rsN1 -t 0.2 || true
        fi
        return 0
    fi

    MAIN_INPUT_TYPE="char"
    MAIN_INPUT_CHAR="$c1"
    return 0
}

# Bou 'n geëtiketteerde afdelingskop soos "── STATUS ──────" wat presies
# tot die opgegewe breedte strek - gebruik om die skerm in duidelike
# afdelings te verdeel (STATUS, OPDRAGTE) i.p.v. een groot blok teks. Die
# kleur word deurgegee (nie hardgekodeer nie) sodat STATUS en OPDRAGTE elk
# in 'n ander aksentkleur van die aktiewe kleurskema kan wys.
section_header() {
    local label="$1" width="$2" color="$3"
    local left="── ${label} "
    local left_len=${#left}
    local fill=$(( width - left_len ))
    [ "$fill" -lt 0 ] && fill=0
    local dashes
    dashes=$(printf '%*s' "$fill" '')
    dashes=${dashes// /─}
    printf '%s%s%s%s' "$color" "$left" "$dashes" "$RESET"
}

# Druk 'n stel opdrag-opsies as 'n eweredig-belynde rooster: elke sel se
# breedte word bereken vanaf die LANGSTE opsie se SIGBARE lengte (sonder
# ANSI-kleurkodes), en die aantal kolomme pas by die terminaal se
# beskikbare breedte aan - so bly die opsies altyd in reguit, netjiese
# lyne, ongeag skermgrootte of watter opsie se teks toevallig kleur het.
print_command_grid() {
    local -n _plain="$1"
    local -n _colored="$2"
    local avail_cols="$3"

    local max_len=0 i
    for i in "${!_plain[@]}"; do
        (( ${#_plain[$i]} > max_len )) && max_len=${#_plain[$i]}
    done

    local cell_width=$(( max_len + 3 ))
    local ncols=$(( avail_cols / cell_width ))
    [ "$ncols" -lt 1 ] && ncols=1
    [ "$ncols" -gt 3 ] && ncols=3

    local line="" pad count=0
    for i in "${!_plain[@]}"; do
        pad=$(( cell_width - ${#_plain[$i]} ))
        line+="${_colored[$i]}$(printf '%*s' "$pad" '')"
        count=$((count + 1))
        if (( count % ncols == 0 )); then
            echo "  $line"
            line=""
        fi
    done

    [ -n "$line" ] && echo "  $line"
}

draw_main_body() {

    local listen_plain listen_colored
    if [ "$PLAYING" = true ]; then
        listen_plain="[P] Monitor Af"
        listen_colored="[P] ${PRIMARY}Monitor Af${RESET}"
    else
        listen_plain="[P] Monitor Aan"
        listen_colored="[P] ${PRIMARY}Monitor Aan${RESET}"
    fi

    # shellcheck disable=SC2034 # gebruik via naamverwysing (nameref) in print_command_grid
    local cmd_plain=(
        "[S] Begin" "[T] Stop" "[R] Herbegin"
        "[L] Logs" "$listen_plain" "[M] Media"
        "[B] Rugsteun" "[Q] Verlaat na shell"
    )
    # shellcheck disable=SC2034 # gebruik via naamverwysing (nameref) in print_command_grid
    local cmd_colored=(
        "[S] Begin" "[T] Stop" "[R] Herbegin"
        "[L] Logs" "$listen_colored" "[M] Media"
        "[B] Rugsteun" "[Q] Verlaat na shell"
    )

    print_command_grid cmd_plain cmd_colored "$sep_width"

    echo

    local settings_arrow="▸" danger_arrow="▸"
    [ "$SHOW_SETTINGS" = true ] && settings_arrow="▾"
    [ "$SHOW_DANGER" = true ] && danger_arrow="▾"

    echo "  [I] Instellings ${settings_arrow}"

    if [ "$SHOW_SETTINGS" = true ]; then
        # shellcheck disable=SC2034 # gebruik via naamverwysing in print_command_grid
        local settings_items=(
            "1) Stroom URL (primêr)" "2) Rugsteun-stroom URL"
            "3) Musiek/sweeper-verhouding" "4) Stasienaam"
            "5) ALSA-klanktoestel" "6) Heartbeat URL"
            "11) Maksimum stroom-buffer" "12) Kleurskema"
            "8) Opdateer sagteware" "9) Herkonfigureer"
        )
        print_command_grid settings_items settings_items "$sep_width"
    fi

    echo "  [G] Gevaarlike opsies ${danger_arrow}"

    if [ "$SHOW_DANGER" = true ]; then
        echo "    7) ${RED}Wys wagwoorde${RESET}"
        echo "    10) ${RED}Verwyder alles (uninstall)${RESET}"
    fi

    if [ -n "$STATUS_MSG" ]; then
        echo
        echo "  >> $STATUS_MSG"
    fi
}

# Bou die hele raam as EEN string en skryf dit in EEN stap, met die cursor
# na die boonste-linker-hoek geskuif (nie 'n volle "clear" nie). Elke
# individuele reël kry ook sy eie "vee-tot-einde-van-reël" ANSI-kode
# (CLEAR_LINE) sodat 'n korter nuwe reël (bv. "loop" i.p.v. "loop nie",
# of "○ OFF AIR" i.p.v. "● ON AIR") nooit stert-karakters van 'n vorige,
# langer reël agterlaat nie - sonder hierdie oorskryf 'n terminal net
# karakters, dit vee nooit outomaties agter 'n korter reël uit nie.
draw() {

    # WAVE_FRAME moet BUITE die $(...) subshell hieronder verhoog word -
    # veranderinge binne 'n command substitution se subshell gaan
    # verlore sodra dit klaar is, en die "animasie" sou nooit beweeg nie.
    WAVE_FRAME=$(( WAVE_FRAME + 1 ))

    local cols lines
    cols=$(tput cols 2>/dev/null || echo 80)
    lines=$(tput lines 2>/dev/null || echo 24)

    # Geen boonste plafon nie - die kassie moet altyd die volle
    # terminaalbreedte gebruik ("volskerm"), ongeag hoe wyd dit is.
    local sep_width=$(( cols - 2 ))
    [ "$sep_width" -lt 10 ] && sep_width=10
    local sep
    sep=$(printf '%*s' "$sep_width" '')
    sep=${sep// /-}

    local accent_bar
    accent_bar=$(printf '%*s' "$sep_width" '')
    accent_bar=${accent_bar// /━}

    local compact=false
    [ "$lines" -lt 20 ] && compact=true

    local status_raw
    status_raw=$(sudo radioctl status --color)

    local station_name
    station_name=$(printf '%s\n' "$status_raw" | sed -n 's/^.*Sender Naam.*: //p' | head -1)
    [ -z "$station_name" ] && station_name="Radio Orania"

    local status_body
    status_body=$(printf '%s\n' "$status_raw" | grep -v 'Sender Naam')

    local on_air=false
    systemctl is-active --quiet radio-orania.service 2>/dev/null && on_air=true

    # update_station_banner moet HIER (buite die $(...) subshell hieronder)
    # aangeroep word - sien die kommentaar by die funksie self.
    if [ "$compact" = false ]; then
        update_station_banner "$station_name" "$sep_width"
    else
        STATION_BANNER_TEXT="${PRIMARY}${BOLD}${station_name}${RESET}"
    fi

    # update_stelsel_body moet ook HIER (buite die subshell) loop, om
    # dieselfde rede as update_station_banner - sien die kommentaar by die
    # funksie self.
    update_stelsel_body

    local frame
    frame=$(
        echo "$STATION_BANNER_TEXT"

        # Die aksentbalk en afdelingskoppe ("── STATUS ──" ens.) is suiwer
        # dekoratief - hulle kos ekstra reëls, so op klein/compact skerms
        # (waar elke reël skaars is) val ons terug na die ou, sobere uitleg
        # (net die skeidingslyn "$sep") i.p.v. hulle af te druk.
        [ "$compact" = false ] && echo "${PRIMARY}${accent_bar}${RESET}"

        if [ "$on_air" = true ]; then
            echo "${BLINK}${GREEN}${BOLD}● ON AIR${RESET}"
        else
            echo "${RED}${BOLD}○ OFF AIR${RESET}"
        fi

        [ "$compact" = false ] && echo

        [ "$compact" = false ] && echo "$(section_header "STATUS" "$sep_width" "$SECONDARY")"
        echo "$status_body"
        echo "$STELSEL_BODY_CACHE"

        if [ "$PLAYING" = true ]; then
            echo "  ${GREEN}▶ Monitor speel${RESET}   $(fake_wave)"
        else
            echo
        fi

        [ "$compact" = false ] && echo

        if [ "$compact" = false ]; then
            echo "$(section_header "OPDRAGTE" "$sep_width" "$PRIMARY")"
        else
            echo "$sep"
        fi

        draw_main_body

        echo "$sep"
    )

    frame="${frame//$'\n'/$CLEAR_LINE$'\n'}${CLEAR_LINE}"

    printf '%s%s\n%s' "$CURSOR_HOME" "$frame" "$CLEAR_TO_END"
}

cleanup() {
    [ -n "$PLAYER_PID" ] && kill "$PLAYER_PID" 2>/dev/null
    printf '%s' "$SHOW_CURSOR"
}

trap cleanup EXIT

# Die kernel stuur WINCH vir die voorgrond-proses sodra die terminaal se
# venstergrootte verander. Sonder hierdie "trap" sou die lopende "read -t"
# hieronder eenvoudig bly wag tot sy volle tydgrens (tot 5s) - solank as
# wat dit vat, wys die terminal SELF nog die ou, nou-te-lang reëls (op sy
# eie manier gewrap), wat soos 'n gebreekte opskrif kan lyk. Deur 'n trap
# te registreer (al doen die handler self niks) word die "read" dadelik
# onderbreek, wat 'n oombliklike herteken met die nuwe grootte afdwing.
handle_resize() { :; }
trap handle_resize WINCH

clear
printf '%s' "$HIDE_CURSOR"

while true; do

    draw

    read_timeout=5
    [ "$PLAYING" = true ] && read_timeout=1

    read_main_key
    read_status=$?

    # Statuskode > 128 beteken die tydgrens het net verstryk (normaal,
    # verfris net weer). Enigiets anders wat nie 0 is nie (bv. 1) beteken
    # stdin is heeltemal toe (EOF) - sonder hierdie tak sou die lus
    # oneindig vinnig bly herhaal ipv om uit te gaan.
    if [ "$read_status" -eq 0 ]; then

        case "$MAIN_INPUT_TYPE" in
            line)
                handle_settings_key "$MAIN_INPUT_LINE"
                ;;
            char)
                case "$MAIN_INPUT_CHAR" in
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
                        sudo radioctl logs | less
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
                    [Ii])
                        [ "$SHOW_SETTINGS" = true ] && SHOW_SETTINGS=false || SHOW_SETTINGS=true
                        STATUS_MSG=""
                        ;;
                    [Gg])
                        [ "$SHOW_DANGER" = true ] && SHOW_DANGER=false || SHOW_DANGER=true
                        STATUS_MSG=""
                        ;;
                    [Qq])
                        clear
                        break
                        ;;
                    *)
                        STATUS_MSG="Onbekende opsie: $MAIN_INPUT_CHAR"
                        ;;
                esac
                ;;
            *)
                :
                ;;
        esac

    elif [ "$read_status" -lt 128 ]; then
        # stdin is toe (nie 'n interaktiewe terminaal meer nie) - gaan uit.
        break
    fi

done
