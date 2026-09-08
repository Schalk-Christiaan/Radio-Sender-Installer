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
MODE="main"

# Instellings-oortjies. SETTINGS_TAB is die aktiewe oortjie; die
# TAB_COL_START/END-tabelle en TAB_BAR_ROW word elke teken (draw()) vars
# herbereken sodat 'n muisklik se skerm-koördinate na die regte oortjie
# omgeskakel kan word (sien compute_settings_tabbar()/click_settings_tab()).
TAB_NAMES=(RADIO INSTELLINGS INLIGTING GEVAARLIK)
SETTINGS_TAB="RADIO"
SETTINGS_TABBAR_LINE=""
TAB_COL_START=()
TAB_COL_END=()
TAB_BAR_ROW=""

# SGR-muisverslagdoening (klik-om-te-kies op die oortjiebalk). Werk oor SSH/
# 'n normale terminaal-emulator; op die kaal fisiese konsole (tty1, geen
# gpm nie) stuur die terminal eenvoudig nooit hierdie volgordes nie, so 'n
# klik doen daar niks - pyltjies/tik bly die betroubare weg oral.
MOUSE_ON=$'\033[?1000h\033[?1006h'
MOUSE_OFF=$'\033[?1000l\033[?1006l'

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
            printf '%s' "$MOUSE_OFF"
            MODE="main"
            STATUS_MSG=""
            ;;
        *)
            STATUS_MSG="Onbekende opsie: $choice"
            ;;
    esac
}

# Lees een "invoer-eenheid" op die Instellings-skerm. Anders as die
# hoofskerm (wat altyd net een karakter lees) moet Instellings soms 'n
# VOLLE reël lees (opsienommers tot "11"/"12"), maar moet ook pyltjies en
# muiskliek-CSI-volgordes (bv. "\e[<0;12;7M") herken - albei begin met 'n
# los ESC-karakter (0x1b). Ons lees dus eers EEN karakter stil (geen
# terminal-eggo nie): as dit nie ESC is nie, druk ons dit self en lees die
# res van die reël normaalweg (die terminal hanteer eggo/terugspasie
# self); is dit wel ESC, ontleed parse_settings_escape() die res van die
# CSI-volgorde met kort tydgrense (die volgende grepe kom binne millisek-
# ondes as dit werklik 'n pyltjie/muis was - 'n los ESC-druk sal eenvoudig
# uittyd en niks doen nie).
#
# Uitset (globale veranderlikes, nie 'n plaaslike return-waarde nie, want
# bash-funksies kan net een heelgetal-statuskode teruggee):
#   SETTINGS_INPUT_TYPE = "line" | "tab" | "mouse" | "none"
#   SETTINGS_INPUT_LINE = die getikte reël (by "line")
#   SETTINGS_INPUT_DIR  = "prev" | "next" (by "tab")
#   SETTINGS_INPUT_MX/MY = muis-kolom/ry, 1-geïndekseer (by "mouse")
#
# Die FUNKSIE se eie return-status is die van die EERSTE (tydgrens-
# beperkte) lees, sodat die hooflus se bestaande uittyd/EOF-onderskeid
# (sien kommentaar by die hooflus) ongeskonde bly - die kort ekstra lesings
# vir CSI-vervolg-grepe tel nie daarvoor nie.
read_settings_key() {
    SETTINGS_INPUT_TYPE="none"
    SETTINGS_INPUT_LINE=""
    SETTINGS_INPUT_DIR=""
    SETTINGS_INPUT_MX=""
    SETTINGS_INPUT_MY=""

    printf '%sKies: ' "$SHOW_CURSOR"

    local c1 status
    IFS= read -rsN1 -t "$read_timeout" c1
    status=$?

    if [ "$status" -ne 0 ]; then
        printf '%s' "$HIDE_CURSOR"
        return "$status"
    fi

    if [ "$c1" = $'\033' ]; then
        parse_settings_escape
        printf '%s' "$HIDE_CURSOR"
        return 0
    fi

    printf '%s' "$c1"
    local rest=""
    read -r rest
    SETTINGS_INPUT_TYPE="line"
    SETTINGS_INPUT_LINE="${c1}${rest}"
    printf '%s' "$HIDE_CURSOR"
    return 0
}

parse_settings_escape() {
    local c2
    IFS= read -rsN1 -t 0.05 c2 || return
    [ "$c2" != "[" ] && return

    local c3
    IFS= read -rsN1 -t 0.2 c3 || return

    case "$c3" in
        A|D)
            SETTINGS_INPUT_TYPE="tab"
            SETTINGS_INPUT_DIR="prev"
            ;;
        B|C)
            SETTINGS_INPUT_TYPE="tab"
            SETTINGS_INPUT_DIR="next"
            ;;
        "<")
            # SGR-muisvolgorde: "<Cb;Cx;CyM" (druk) of "...m" (los). Lees
            # greep-vir-greep tot by die M/m-terminator, of tot 'n redelike
            # boonste grens (verhoed 'n oneindige lees as iets vreemds
            # aankom).
            local seq="" ch term=""
            while :; do
                IFS= read -rsN1 -t 0.2 ch || break
                if [ "$ch" = "M" ] || [ "$ch" = "m" ]; then
                    term="$ch"
                    break
                fi
                seq+="$ch"
                [ "${#seq}" -ge 20 ] && break
            done

            if [ "$term" = "M" ]; then
                local btn="" x="" y=""
                IFS=';' read -r btn x y <<< "$seq"
                # Slegs 'n eenvoudige linkerklik: die boonste bisse (32=
                # sleep, 64=rolwiel) moet af wees, en die laer 2 bisse moet
                # 0 wees (knoppie 1/links).
                if [[ "$btn" =~ ^[0-9]+$ ]] \
                    && (( (btn & 96) == 0 )) \
                    && (( (btn & 3) == 0 )); then
                    SETTINGS_INPUT_TYPE="mouse"
                    SETTINGS_INPUT_MX="$x"
                    SETTINGS_INPUT_MY="$y"
                fi
            fi
            ;;
    esac
}

draw_settings_body() {
    echo "${BOLD}Instellings${RESET}"
    echo

    # Op klein/compact skerms (sien $compact in draw()) val ons terug na
    # die ou, sobere plat lys - dieselfde rede as die STATUS/OPDRAGTE-koppe
    # elders: afdelingskoppe kos ekstra reëls wat op 'n klein skerm skaars is.
    if [ "$compact" = true ]; then
        echo "  1) Stroom URL (primêr)"
        echo "  2) Rugsteun-stroom URL"
        echo "  3) Musiek/sweeper-verhouding"
        echo "  4) Stasienaam"
        echo "  5) ALSA-klanktoestel"
        echo "  6) Heartbeat URL"
        echo "  7) ${RED}Wys wagwoorde${RESET}"
        echo "  8) Opdateer sagteware"
        echo "  9) Herkonfigureer (loop opstelling weer)"
        echo "  10) ${RED}Verwyder alles (uninstall)${RESET}"
        echo "  11) Maksimum stroom-buffer"
        echo "  12) Kleurskema"
        echo "  0) Terug na hoofskerm"

        if [ -n "$STATUS_MSG" ]; then
            echo
            echo "  >> $STATUS_MSG"
        fi
        return
    fi

    # SETTINGS_TABBAR_LINE en TAB_COL_START/END word BUITE hierdie subshell
    # deur compute_settings_tabbar() in draw() bereken (sien kommentaar
    # daar) - hier lees ons dit net.
    echo "$SETTINGS_TABBAR_LINE ${GRAY}(◄ ► om te wissel, of klik)${RESET}"
    echo "$sep"
    echo

    case "$SETTINGS_TAB" in
        RADIO)
            # shellcheck disable=SC2034 # gebruik via naamverwysing in print_command_grid
            local radio_items=(
                "1) Stroom URL (primêr)" "2) Rugsteun-stroom URL"
                "4) Stasienaam" "5) ALSA-klanktoestel"
            )
            print_command_grid radio_items radio_items "$sep_width"
            echo
            sudo radioctl bufferstat
            ;;
        INSTELLINGS)
            # shellcheck disable=SC2034 # gebruik via naamverwysing in print_command_grid
            local settings_items=(
                "3) Musiek/sweeper-verhouding" "6) Heartbeat URL"
                "11) Maksimum stroom-buffer" "12) Kleurskema"
                "8) Opdateer sagteware" "9) Herkonfigureer"
            )
            print_command_grid settings_items settings_items "$sep_width"
            ;;
        INLIGTING)
            printf '%s\n' "$status_raw" | grep 'Aanlyn'
            sudo radioctl datausage
            sudo radioctl sysstats
            ;;
        GEVAARLIK)
            echo "  7) ${RED}Wys wagwoorde${RESET}"
            echo "  10) ${RED}Verwyder alles (uninstall)${RESET}"
            ;;
    esac

    echo
    echo "  0) Terug na hoofskerm"

    if [ -n "$STATUS_MSG" ]; then
        echo
        echo "  >> $STATUS_MSG"
    fi
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

# Bou die Instellings-oortjiebalk se teks EN onthou elke oortjie se
# begin/eind-kolom (plat, sonder ANSI-kodes) in TAB_COL_START/END. Moet
# BUITE die $(...) subshell in draw() aangeroep word (soos
# update_station_banner) - anders gaan hierdie globale toekennings by die
# subshell se einde verlore, en sou 'n muisklik nooit korrek kon omgeskakel
# word na 'n oortjie nie.
compute_settings_tabbar() {
    TAB_COL_START=()
    TAB_COL_END=()
    SETTINGS_TABBAR_LINE=""

    local col=1 i name disp colored
    for i in "${!TAB_NAMES[@]}"; do
        name="${TAB_NAMES[$i]}"
        if [ "$name" = "$SETTINGS_TAB" ]; then
            disp="[${name}]"
            colored="${BOLD}${PRIMARY}${disp}${RESET}"
        else
            disp="$name"
            colored="$disp"
        fi

        TAB_COL_START[i]=$col
        TAB_COL_END[i]=$(( col + ${#disp} - 1 ))

        SETTINGS_TABBAR_LINE+="${colored} "
        col=$(( col + ${#disp} + 1 ))
    done
}

cycle_settings_tab() {
    local dir="$1" i cur_idx=0
    for i in "${!TAB_NAMES[@]}"; do
        [ "${TAB_NAMES[$i]}" = "$SETTINGS_TAB" ] && cur_idx=$i
    done

    local n=${#TAB_NAMES[@]}
    if [ "$dir" = "next" ]; then
        cur_idx=$(( (cur_idx + 1) % n ))
    else
        cur_idx=$(( (cur_idx - 1 + n) % n ))
    fi

    SETTINGS_TAB="${TAB_NAMES[$cur_idx]}"
}

click_settings_tab() {
    local mx="$1" my="$2" i

    [[ "$mx" =~ ^[0-9]+$ ]] || return
    [ -n "$TAB_BAR_ROW" ] && [ "$my" = "$TAB_BAR_ROW" ] || return

    for i in "${!TAB_NAMES[@]}"; do
        if [ "$mx" -ge "${TAB_COL_START[$i]}" ] && [ "$mx" -le "${TAB_COL_END[$i]}" ]; then
            SETTINGS_TAB="${TAB_NAMES[$i]}"
            return
        fi
    done
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
        "[B] Rugsteun" "[C] Instellings" "[Q] Verlaat na shell"
    )
    # shellcheck disable=SC2034 # gebruik via naamverwysing (nameref) in print_command_grid
    local cmd_colored=(
        "[S] Begin" "[T] Stop" "[R] Herbegin"
        "[L] Logs" "$listen_colored" "[M] Media"
        "[B] Rugsteun" "[C] Instellings" "[Q] Verlaat na shell"
    )

    print_command_grid cmd_plain cmd_colored "$sep_width"

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

    # compute_settings_tabbar() moet ook HIER (buite die subshell) loop,
    # om dieselfde rede - anders sou TAB_COL_START/END (nodig om 'n
    # muisklik se kolom na 'n oortjie om te skakel) nooit buite die subshell
    # bewaar bly nie.
    if [ "$MODE" = "settings" ] && [ "$compact" = false ]; then
        compute_settings_tabbar
    else
        TAB_BAR_ROW=""
    fi

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

        if [ "$MODE" = "settings" ]; then
            draw_settings_body
        else
            draw_main_body
        fi

        echo "$sep"
    )

    # Bepaal watter terminaal-RY die oortjiebalk werklik beland het op
    # (wissel na gelang van hoeveel STATUS-reëls hierdie keer gedruk is),
    # sodat 'n muisklik se Y-koördinaat korrek vergelyk kan word. "GEVAARLIK"
    # kom nêrens anders in die skerm voor nie, so dis 'n veilige merker.
    if [ "$MODE" = "settings" ] && [ "$compact" = false ]; then
        TAB_BAR_ROW=$(printf '%s\n' "$frame" | grep -n "GEVAARLIK" | head -1 | cut -d: -f1)
    fi

    frame="${frame//$'\n'/$CLEAR_LINE$'\n'}${CLEAR_LINE}"

    printf '%s%s\n%s' "$CURSOR_HOME" "$frame" "$CLEAR_TO_END"
}

cleanup() {
    [ -n "$PLAYER_PID" ] && kill "$PLAYER_PID" 2>/dev/null
    printf '%s%s' "$MOUSE_OFF" "$SHOW_CURSOR"
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

    # Instellings-opsies loop tot 11/12, so 'n enkel-karakter-lees (soos
    # die hoofskerm gebruik) kan "10"/"11"/"12" nooit ontvang nie - daar
    # gebruik ons eerder read_settings_key(), wat SELF onderskei tussen 'n
    # volle reël, 'n pyltjie, of 'n muisklik (sien kommentaar by die
    # funksie).
    if [ "$MODE" = "settings" ]; then
        read_settings_key
        read_status=$?
    else
        read -r -t "$read_timeout" -n 1 key
        read_status=$?
    fi

    # Statuskode > 128 beteken die tydgrens het net verstryk (normaal,
    # verfris net weer). Enigiets anders wat nie 0 is nie (bv. 1) beteken
    # stdin is heeltemal toe (EOF) - sonder hierdie tak sou die lus
    # oneindig vinnig bly herhaal ipv om uit te gaan.
    if [ "$read_status" -eq 0 ]; then

        if [ "$MODE" = "settings" ]; then

            case "$SETTINGS_INPUT_TYPE" in
                line)
                    handle_settings_key "$SETTINGS_INPUT_LINE"
                    ;;
                tab)
                    cycle_settings_tab "$SETTINGS_INPUT_DIR"
                    ;;
                mouse)
                    click_settings_tab "$SETTINGS_INPUT_MX" "$SETTINGS_INPUT_MY"
                    ;;
                *)
                    :
                    ;;
            esac

        else

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
                [Cc])
                    MODE="settings"
                    SETTINGS_TAB="RADIO"
                    STATUS_MSG=""
                    printf '%s' "$MOUSE_ON"
                    ;;
                [Qq])
                    clear
                    break
                    ;;
                *)
                    STATUS_MSG="Onbekende opsie: $key"
                    ;;
            esac

        fi

    elif [ "$read_status" -lt 128 ]; then
        # stdin is toe (nie 'n interaktiewe terminaal meer nie) - gaan uit.
        break
    fi

done
