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
    {
        printf "\r   [%s] %3d%% %-48s" "$bar" "$percent" "$message"
        if [ "$percent" -ge 100 ]; then
            printf "\n"
        fi
    } > /dev/tty 2>/dev/null || true
}
