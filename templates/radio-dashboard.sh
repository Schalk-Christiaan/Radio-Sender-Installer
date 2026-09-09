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

# Oortjies. Almal leef op DIESELFDE deurlopende skerm (STATUS bly altyd
# sigbaar bo-aan) - geen aparte modus/skerm-wissel nie. Net een oortjie
# se opsies wys op enige oomblik; ◄/► wissel tussen hulle (sien
# cycle_tab()/read_main_key()). BEHEER is die verstek-oortjie omdat dit
# die mees-gebruikte aksies bevat. Elke oortjie se opsies begin by 1 (sien
# docs/adr/0001-dashboard-single-screen-tab-navigation.md vir waarom).
TAB_NAMES=(BEHEER INLIGTING INSTELLINGS ONDERHOUD GEVAARLIK TOETS)
ACTIVE_TAB="BEHEER"

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
# werk nie. Die kaller (draw()) roep dit net wanneer die INLIGTING-oortjie
# aktief is - die 5s-kas verhoed steeds herhaalde stadige oproepe solank
# 'n mens daar bly sit, maar ander oortjies betaal nooit meer hierdie
# koste nie.
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

# --- BEHEER-oortjie: 1) Begin 2) Stop 3) Herbegin 4) Monitor -----------
# Suiwer lewendige-uitsending-beheer - alles wat net INLIGTING wys (Media)
# of die stelsel/paneel onderhou (Rugsteun, Kleurskema, ens.) leef elders.
handle_beheer_item() {
    local choice="$1"

    case "$choice" in
        1)
            spinner_run "Begin radio..." sudo radioctl start
            [ -z "$STATUS_MSG" ] && STATUS_MSG="Radio begin."
            ;;
        2)
            spinner_run "Stop radio..." sudo radioctl stop
            [ -z "$STATUS_MSG" ] && STATUS_MSG="Radio gestop."
            ;;
        3)
            spinner_run "Herbegin radio..." sudo radioctl restart
            [ -z "$STATUS_MSG" ] && STATUS_MSG="Radio herbegin."
            ;;
        4)
            toggle_listen
            ;;
        "")
            STATUS_MSG=""
            ;;
        *)
            STATUS_MSG="Onbekende opsie: $choice"
            ;;
    esac
}

# --- INLIGTING-oortjie: stelsel-syfers (buffer/data/CPU) + 1) Logs
#     2) Media --------------------------------------------------------
handle_inligting_item() {
    local choice="$1"

    case "$choice" in
        1)
            printf '%s' "$SHOW_CURSOR"
            sudo radioctl logs | less
            printf '%s' "$HIDE_CURSOR"
            STATUS_MSG=""
            ;;
        2)
            STATUS_MSG=$(sudo radioctl media 2>&1)
            ;;
        "")
            STATUS_MSG=""
            ;;
        *)
            STATUS_MSG="Onbekende opsie: $choice"
            ;;
    esac
}

# --- INSTELLINGS-oortjie: 1-7 (uitsluitlik "radioctl set"-sleutels) -----
handle_instellings_item() {
    local choice="$1" val

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
            inline_prompt "Maksimum stroom-buffer in sekondes: " val
            STATUS_MSG=$(sudo radioctl set STREAM_BUFFER_MAX "$val" 2>&1)
            ;;
        "")
            STATUS_MSG=""
            ;;
        *)
            STATUS_MSG="Onbekende opsie: $choice"
            ;;
    esac
}

# --- ONDERHOUD-oortjie: 1) Rugsteun 2) Opdateer sagteware
#     3) Herkonfigureer 4) Kleurskema -------------------------------------
# Stelsel/paneel-onderhoud - nie 'n lewendige-uitsending-aksie (BEHEER) of
# 'n enkele "radioctl set"-sleutel (INSTELLINGS) nie.
handle_onderhoud_item() {
    local choice="$1" val

    case "$choice" in
        1)
            spinner_run "Skep rugsteun..." sudo radioctl backup
            ;;
        2)
            inline_prompt "Opdateer sagteware nou? (Y/N): " val
            if [[ "$val" =~ ^[Yy]$ ]]; then
                printf '%s' "$SHOW_CURSOR"
                sudo radioctl update
                inline_pause
            fi
            STATUS_MSG=""
            ;;
        3)
            inline_prompt "Herkonfigureer nou? Dit loop die opstelling-vrae weer. (Y/N): " val
            if [[ "$val" =~ ^[Yy]$ ]]; then
                printf '%s' "$SHOW_CURSOR"
                sudo radioctl reconfigure
                inline_pause
            fi
            STATUS_MSG=""
            ;;
        4)
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
        "")
            STATUS_MSG=""
            ;;
        *)
            STATUS_MSG="Onbekende opsie: $choice"
            ;;
    esac
}

# --- GEVAARLIK-oortjie: 1) Wagwoorde 2) Verwyder alles ------------------
handle_gevaarlik_item() {
    local choice="$1" val

    case "$choice" in
        1)
            printf '%s' "$SHOW_CURSOR"
            echo
            sudo radioctl passwords
            inline_pause
            STATUS_MSG=""
            ;;
        2)
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
        "")
            STATUS_MSG=""
            ;;
        *)
            STATUS_MSG="Onbekende opsie: $choice"
            ;;
    esac
}

# --- TOETS-oortjie: 1) Bron 1 2) Bron 2 3) Internet 4) Diens-crash
#     5) Heartbeat 6) Klankkaart -----------------------------------------
#
# 1-3 is wissel-opsies (loop/gestop, of normaal/geblokkeer) - die huidige
# toestand word ELKE keer eers by radioctl bevraagteken (nie plaaslik
# onthou nie), sodat 'n outomatiese herstel (bv. die internet-blokkade se
# 60s-tydgrens) korrek op die skerm weerspieël word.
handle_toets_item() {
    local choice="$1" val resp

    case "$choice" in
        1)
            resp=$(sudo radioctl test-source-status 1 2>&1)
            if [ "$resp" = "gestop" ]; then
                STATUS_MSG=$(sudo radioctl test-source-start 1 2>&1)
            else
                STATUS_MSG=$(sudo radioctl test-source-stop 1 2>&1)
            fi
            ;;
        2)
            resp=$(sudo radioctl test-source-status 2 2>&1)
            if [ "$resp" = "gestop" ]; then
                STATUS_MSG=$(sudo radioctl test-source-start 2 2>&1)
            else
                STATUS_MSG=$(sudo radioctl test-source-stop 2 2>&1)
            fi
            ;;
        3)
            resp=$(sudo radioctl test-internet-status 2>&1)
            if [ "$resp" = "geblokkeer" ]; then
                STATUS_MSG=$(sudo radioctl test-internet-restore 2>&1)
            else
                STATUS_MSG=$(sudo radioctl test-internet-block 2>&1)
            fi
            ;;
        4)
            inline_prompt "Maak die radio-diens dood om outo-herstel te toets? (Y/N): " val
            if [[ "$val" =~ ^[Yy]$ ]]; then
                STATUS_MSG=$(sudo radioctl test-service-crash 2>&1)
            else
                STATUS_MSG=""
            fi
            ;;
        5)
            STATUS_MSG=$(sudo radioctl test-heartbeat 2>&1)
            ;;
        6)
            STATUS_MSG=$(sudo radioctl test-soundcard 2>&1)
            ;;
        "")
            STATUS_MSG=""
            ;;
        *)
            STATUS_MSG="Onbekende opsie: $choice"
            ;;
    esac
}

# Stuur 'n getikte opsienommer na die regte oortjie se hanteerder - watter
# nommer wat beteken, hang af van watter oortjie op die oomblik aktief is
# (elke oortjie se nommers begin by 1, sien TAB_NAMES hierbo).
handle_tab_item() {
    local choice="$1"

    case "$ACTIVE_TAB" in
        BEHEER)      handle_beheer_item "$choice" ;;
        INLIGTING)   handle_inligting_item "$choice" ;;
        INSTELLINGS) handle_instellings_item "$choice" ;;
        ONDERHOUD)   handle_onderhoud_item "$choice" ;;
        GEVAARLIK)   handle_gevaarlik_item "$choice" ;;
        TOETS)       handle_toets_item "$choice" ;;
    esac
}

cycle_tab() {
    local dir="$1" i cur=0

    for i in "${!TAB_NAMES[@]}"; do
        [ "${TAB_NAMES[$i]}" = "$ACTIVE_TAB" ] && cur=$i
    done

    local n=${#TAB_NAMES[@]}
    if [ "$dir" = "next" ]; then
        cur=$(( (cur + 1) % n ))
    else
        cur=$(( (cur - 1 + n) % n ))
    fi

    ACTIVE_TAB="${TAB_NAMES[$cur]}"
    STATUS_MSG=""
}

# Lees een "invoer-eenheid" op die hoofskerm. Enkelletter-opdragte ('n
# oortjie se opsies word getik as syfers, sien onder) werk oombliklik,
# geen Enter nodig nie - op die oomblik is net [Q] so 'n opdrag. 'n Syfer
# begin egter 'n oortjie-opsienommer, wat 'n VOLLE reël moet lees tot
# Enter. Ons lees dus eers EEN karakter stil: as dit 'n syfer is, druk ons
# dit self en lees die res van die reël normaalweg (die terminal hanteer
# eggo/terugspasie self); as dit ESC is, ontleed ons 'n moontlike
# pyltjie-volgorde (om tussen oortjies te wissel); andersins is dit 'n
# oombliklike enkelletter-opdrag.
#
# Uitset (globale veranderlikes, nie 'n plaaslike return-waarde nie, want
# bash-funksies kan net een heelgetal-statuskode teruggee):
#   MAIN_INPUT_TYPE = "line" | "char" | "tab" | "none"
#   MAIN_INPUT_LINE = die getikte reël (by "line")
#   MAIN_INPUT_CHAR = die enkele karakter (by "char")
#   MAIN_INPUT_DIR  = "prev" | "next" (by "tab")
#
# Die FUNKSIE se eie return-status is die van die EERSTE (tydgrens-
# beperkte) lees, sodat die hooflus se bestaande uittyd/EOF-onderskeid
# (sien kommentaar by die hooflus) ongeskonde bly.
read_main_key() {
    MAIN_INPUT_TYPE="none"
    MAIN_INPUT_LINE=""
    MAIN_INPUT_CHAR=""
    MAIN_INPUT_DIR=""

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
        # Lees greep-vir-greep: as die volgende greep nie '[' is nie (of
        # niks kom betyds nie), gooi ons NIKS bykomend weg nie - 'n
        # vinnige regte toetsdruk direk ná 'n los ESC bly dus intak. Kom
        # daar wel '[', kyk na die derde greep om die pyltjie-rigting te
        # bepaal (A/D=links, B/C=regs - albei pare wissel oortjies, soos
        # die vorige oortjie-weergawe se pyltjie-hantering).
        local c2
        IFS= read -rsN1 -t 0.05 c2 || return 0
        if [ "$c2" = "[" ]; then
            local c3
            IFS= read -rsN1 -t 0.2 c3 || return 0
            case "$c3" in
                A|D) MAIN_INPUT_TYPE="tab"; MAIN_INPUT_DIR="prev" ;;
                B|C) MAIN_INPUT_TYPE="tab"; MAIN_INPUT_DIR="next" ;;
            esac
        fi
        return 0
    fi

    MAIN_INPUT_TYPE="char"
    MAIN_INPUT_CHAR="$c1"
    return 0
}

# Bou 'n geëtiketteerde afdelingskop soos "── STATUS ──────" wat presies
# tot die opgegewe breedte strek - gebruik om die skerm in duidelike
# afdelings te verdeel. Die kleur word deurgegee (nie hardgekodeer nie)
# sodat verskillende afdelings elk in 'n ander aksentkleur van die
# aktiewe kleurskema kan wys.
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

# Druk 'n stel opsies as 'n eweredig-belynde rooster: elke sel se breedte
# word bereken vanaf die LANGSTE opsie se SIGBARE lengte (sonder ANSI-
# kleurkodes), en die aantal kolomme pas by die terminaal se beskikbare
# breedte aan - so bly die opsies altyd in reguit, netjiese lyne, ongeag
# skermgrootte of watter opsie se teks toevallig kleur het.
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

# Druk 'n ry klein "kaartjies" (soos 'n dashboard-widget-ry) - elke
# kaartjie se breedte pas by sy EIE titel/waarde (nie 'n gedeelde
# rooster-breedte soos print_command_grid nie), en 'n nuwe kaartjie wat
# nie meer op die huidige reël pas nie begin outomaties 'n nuwe ry.
# _titles/_values/_colors moet dieselfde lengte hê; 'n leë kleur beteken
# geen kleur nie.
draw_status_cards() {
    local -n _titles="$1"
    local -n _values="$2"
    local -n _colors="$3"
    local avail="$4"

    local i w tlen vlen dash_fill pad
    local -a box_w=()

    for i in "${!_titles[@]}"; do
        tlen=${#_titles[$i]}
        vlen=${#_values[$i]}
        w=$(( vlen + 2 ))
        (( tlen + 3 > w )) && w=$(( tlen + 3 ))
        box_w[i]=$w
    done

    local top="" mid="" bot="" cur_width=0 piece_width dashes vpad

    for i in "${!_titles[@]}"; do
        w="${box_w[$i]}"
        piece_width=$(( w + 3 ))

        if [ "$cur_width" -gt 0 ] && (( cur_width + piece_width > avail )); then
            echo "  $top"
            echo "  $mid"
            echo "  $bot"
            top=""; mid=""; bot=""; cur_width=0
        fi

        tlen=${#_titles[$i]}
        vlen=${#_values[$i]}
        dash_fill=$(( w - tlen - 3 ))
        # ${var// /X} (bash se eie stringvervanging) i.p.v. "tr ' ' '─'" -
        # tr werk greep-vir-greep, en "─" is 'n multi-greep UTF-8-karakter;
        # tr sou net die EERSTE greep daarvan herhaal en ongeldige UTF-8
        # produseer (sien section_header()/accent_bar hierbo vir dieselfde
        # veilige patroon).
        dashes=$(printf '%*s' "$dash_fill" '')
        dashes=${dashes// /─}
        pad=$(( w - vlen - 2 ))
        vpad=$(printf '%*s' "$pad" '')

        top+="┌─ ${_titles[$i]} ${dashes}┐ "
        if [ -n "${_colors[$i]}" ]; then
            mid+="│ ${_colors[$i]}${_values[$i]}${RESET}${vpad} │ "
        else
            mid+="│ ${_values[$i]}${vpad} │ "
        fi
        local bot_dashes
        bot_dashes=$(printf '%*s' "$w" '')
        bot_dashes=${bot_dashes// /─}
        bot+="└${bot_dashes}┘ "

        cur_width=$(( cur_width + piece_width ))
    done

    echo "  $top"
    echo "  $mid"
    echo "  $bot"
}

# Bou die oortjiebalk se teks (bv. "[BEHEER] INSTELLINGS GEVAARLIK TOETS")
# - die aktiewe oortjie is vetgedruk in PRIMARY en tussen hakies.
compute_tab_bar() {
    local i name disp colored line=""

    for i in "${!TAB_NAMES[@]}"; do
        name="${TAB_NAMES[$i]}"
        if [ "$name" = "$ACTIVE_TAB" ]; then
            disp="[${name}]"
            colored="${BOLD}${PRIMARY}${disp}${RESET}"
        else
            disp="$name"
            colored="$disp"
        fi
        line+="${colored} "
    done

    printf '%s' "$line"
}

draw_beheer_tab() {
    local listen_item
    if [ "$PLAYING" = true ]; then
        listen_item="4) Monitor Af"
    else
        listen_item="4) Monitor Aan"
    fi

    # shellcheck disable=SC2034 # gebruik via naamverwysing (nameref) in print_command_grid
    local items=(
        "1) Begin" "2) Stop" "3) Herbegin" "$listen_item"
    )
    print_command_grid items items "$sep_width"
}

draw_inligting_tab() {
    echo "$STELSEL_BODY_CACHE"
    echo
    echo "  1) Logs"
    echo "  2) Media"
}

draw_instellings_tab() {
    # shellcheck disable=SC2034 # gebruik via naamverwysing (nameref) in print_command_grid
    local items=(
        "1) Stroom URL (primêr)" "2) Rugsteun-stroom URL"
        "3) Musiek/sweeper-verhouding" "4) Stasienaam"
        "5) ALSA-klanktoestel" "6) Heartbeat URL"
        "7) Maksimum stroom-buffer"
    )
    print_command_grid items items "$sep_width"
}

draw_onderhoud_tab() {
    # shellcheck disable=SC2034 # gebruik via naamverwysing (nameref) in print_command_grid
    local items=(
        "1) Rugsteun" "2) Opdateer sagteware"
        "3) Herkonfigureer" "4) Kleurskema"
    )
    print_command_grid items items "$sep_width"
}

draw_gevaarlik_tab() {
    echo "  1) ${RED}Wys wagwoorde${RESET}"
    echo "  2) ${RED}Verwyder alles (uninstall)${RESET}"
}

draw_toets_tab() {
    local bron1 bron2 internet
    bron1=$(sudo radioctl test-source-status 1 2>/dev/null)
    bron2=$(sudo radioctl test-source-status 2 2>/dev/null)
    internet=$(sudo radioctl test-internet-status 2>/dev/null)

    local p1 p2 p3 c1 c2 c3

    if [ "$bron1" = "gestop" ]; then
        p1="1) Bron 1: Herstel"; c1="1) ${RED}Bron 1: Herstel${RESET}"
    else
        p1="1) Bron 1: Simuleer wegval"; c1="$p1"
    fi

    if [ "$bron2" = "gestop" ]; then
        p2="2) Bron 2: Herstel"; c2="2) ${RED}Bron 2: Herstel${RESET}"
    else
        p2="2) Bron 2: Simuleer wegval"; c2="$p2"
    fi

    if [ "$internet" = "geblokkeer" ]; then
        p3="3) Internet: Herstel"; c3="3) ${RED}Internet: Herstel${RESET}"
    else
        p3="3) Internet: Simuleer verlies"; c3="$p3"
    fi

    # shellcheck disable=SC2034 # gebruik via naamverwysing (nameref) in print_command_grid
    local items_plain=(
        "$p1" "$p2" "$p3"
        "4) Diens-crash toets" "5) Heartbeat-toets nou" "6) Klankkaart-toets"
    )
    # shellcheck disable=SC2034 # gebruik via naamverwysing (nameref) in print_command_grid
    local items_colored=(
        "$c1" "$c2" "$c3"
        "4) Diens-crash toets" "5) Heartbeat-toets nou" "6) Klankkaart-toets"
    )
    print_command_grid items_plain items_colored "$sep_width"

    if [ "$internet" = "geblokkeer" ]; then
        echo
        echo "  ${RED}Internet is tans geblokkeer (toets) - herstel outomaties binnekort.${RESET}"
    fi
}

draw_tabs_body() {
    echo "$(compute_tab_bar)${GRAY}(◄ ► om te wissel)${RESET}"
    echo "$sep"
    echo

    case "$ACTIVE_TAB" in
        BEHEER)      draw_beheer_tab ;;
        INLIGTING)   draw_inligting_tab ;;
        INSTELLINGS) draw_instellings_tab ;;
        ONDERHOUD)   draw_onderhoud_tab ;;
        GEVAARLIK)   draw_gevaarlik_tab ;;
        TOETS)       draw_toets_tab ;;
    esac

    echo
    echo "  [Q] Verlaat na shell"

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

    # Kaartjie-waardes moet ANSI-vry wees om korrek te kan meet/opvul
    # (draw_status_cards() voeg self kleur by via card_colors) - status_body
    # hierbo bly wel gekleur, vir die stroom-URL-reël en "af"-status
    # hieronder wat die kleure direk hergebruik.
    local status_plain
    status_plain=$(printf '%s\n' "$status_body" | sed -E 's/\x1b\[[0-9;]*m//g')

    local bron_val aanlyn_val skyf_val
    bron_val=$(printf '%s\n' "$status_plain" | sed -n 's/^Aktiewe Bron *: *//p' | sed 's/ (.*//')
    [ -z "$bron_val" ] && bron_val="onbekend"
    aanlyn_val=$(printf '%s\n' "$status_plain" | sed -n 's/^Aanlyn *: *//p')
    skyf_val=$(printf '%s\n' "$status_plain" | sed -n 's/^Beskikbare skyfspasie: *//p')

    local svc_total svc_up
    svc_total=$(printf '%s\n' "$status_plain" | grep -cE '\.(service|timer) +loop( nie)?$')
    svc_up=$(printf '%s\n' "$status_plain" | grep -cE '\.(service|timer) +loop$')

    local dienste_val dienste_color
    dienste_val="${svc_up}/${svc_total} loop"
    if [ "$svc_total" -gt 0 ] && [ "$svc_up" -eq "$svc_total" ]; then
        dienste_color="$GREEN"
    else
        dienste_color="$RED"
    fi

    # shellcheck disable=SC2034 # gebruik via naamverwysing (nameref) in draw_status_cards
    local card_titles=(Bron Aanlyn Dienste Skyf)
    # shellcheck disable=SC2034 # gebruik via naamverwysing (nameref) in draw_status_cards
    local card_values=("$bron_val" "$aanlyn_val" "$dienste_val" "${skyf_val:-onbekend}")
    # shellcheck disable=SC2034 # gebruik via naamverwysing (nameref) in draw_status_cards
    local card_colors=("" "" "$dienste_color" "")

    local url_line down_lines
    url_line=$(printf '%s\n' "$status_body" | grep '^Stroom URL')
    down_lines=$(printf '%s\n' "$status_body" | grep 'loop nie')

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
    # funksie self. Loop dit net wanneer die INLIGTING-oortjie werklik
    # aktief is (dis nou tab-inhoud, nie meer altyd-sigbaar nie).
    if [ "$ACTIVE_TAB" = "INLIGTING" ]; then
        update_stelsel_body
    fi

    local frame
    frame=$(
        echo "$STATION_BANNER_TEXT"

        # Die aksentbalk en afdelingskop ("── STATUS ──" ens.) is suiwer
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
        draw_status_cards card_titles card_values card_colors "$sep_width"
        [ -n "$url_line" ] && echo "$url_line"
        [ -n "$down_lines" ] && printf '%s\n' "$down_lines"

        if [ "$PLAYING" = true ]; then
            echo "  ${GREEN}▶ Monitor speel${RESET}   $(fake_wave)"
        else
            echo
        fi

        [ "$compact" = false ] && echo

        echo "$sep"

        draw_tabs_body

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
                handle_tab_item "$MAIN_INPUT_LINE"
                ;;
            tab)
                cycle_tab "$MAIN_INPUT_DIR"
                ;;
            char)
                case "$MAIN_INPUT_CHAR" in
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
