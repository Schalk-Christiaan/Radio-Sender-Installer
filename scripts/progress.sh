#!/bin/bash

progress() {

    local percent="$1"
    local message="$2"

    local bars=$((percent / 5))
    local bar=""
    local i

    for ((i=0; i<20; i++)); do
        if [ "$i" -lt "$bars" ]; then
            bar="${bar}#"
        else
            bar="${bar}-"
        fi
    done

    # Plat weergawe: elke opdatering op sy eie reël. Dit beland in
    # installer.log, en verskyn ook so op die skerm in --verbose modus.
    echo
    printf "   [%s] %3d%% %s\n" "$bar" "$percent" "$message"

    # Geanimeerde weergawe: geskryf direk na die beheerterminaal (indien een
    # bestaan) en oorskryf homself op dieselfde reël, ongeag hoe install.sh
    # hierdie skrip se gewone uitset herlei of deur tee stuur.
    #
    # Bash stel herleidings van links na regs op; as "> /dev/tty" EERSTE
    # kom en misluk (bv. geen beheerterminaal nie, soos wanneer radioctl
    # via sudo/su vanaf 'n ander skrip aangeroep word), druk dit die fout
    # op die destydse (nog-nie-herlei-nie) stderr, en "2>/dev/null" wat
    # daarna volg kom nooit betyds nie. Deur "2>/dev/null" EERSTE te sit,
    # is stderr reeds stilgemaak teen die tyd wat die /dev/tty-poging
    # (moontlik) misluk.
    {
        printf "\r   [%s] %3d%% %-48s" "$bar" "$percent" "$message"
        if [ "$percent" -ge 100 ]; then
            printf "\n"
        fi
    } 2>/dev/null > /dev/tty || true
}

# Skryf teks direk na die beheerterminaal (indien een bestaan), ongeag hoe
# install.sh hierdie skrip se gewone uitset herlei - sien progress() hierbo
# vir dieselfde patroon en die rede vir die herleiding-volgorde. 'n Leidende
# \n dwing 'n vars reël af, ongeag waar progress() se kursor-animasie
# (\r...geen \n nie by <100%) die kursor laat staan het.
to_screen() {
    { printf '\n%s\n' "$1"; } 2>/dev/null > /dev/tty || true
}

# 'n Waarskuwing wat, soos progress() hierbo, altyd die skerm moet bereik -
# nie net installer.log nie. install.sh se verstek (nie-verbose) run_step
# herlei elke stap se hele stdout/stderr na die log toe (>>"$LOG_FILE" 2>&1),
# so 'n gewone "echo" hier sou 'n operateur wat nie --verbose gebruik nie
# nooit bereik nie.
#
# In --verbose modus ("tee -a" na die log) beland die eerste echo hieronder
# reeds op die skerm - VERBOSE (deur install.sh uitgevoer) laat die
# to_screen()-kopie dan oor, anders sou die waarskuwing twee keer agtermekaar
# verskyn.
warn() {

    local message="$1"

    echo "Waarskuwing: $message" || true

    if [ "${VERBOSE:-false}" != true ]; then
        to_screen "Waarskuwing: $message"
    fi
}
