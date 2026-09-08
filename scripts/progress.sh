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
