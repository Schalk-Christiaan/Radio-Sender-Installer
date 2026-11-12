#!/bin/bash
# Gedeelde voorkoms vir install.sh en setup.sh: kleure, banier, afdelings,
# boodskappe en die stap-spinner.
#
# Op die Linux-konsole (TERM=linux, bv. tty1) ontbreek die meeste
# Unicode-tekens in die lettertipe en is daar net 8 kleure - dan word
# gewone ASCII en basiese kleure gebruik (dieselfde reël as radio-dash).

if [ "${TERM:-}" = "linux" ]; then
    UI_OK="+" UI_FAIL="x" UI_WARN="!" UI_ARROW=">"
    UI_SPIN=("|" "/" "-" "\\")
    UI_BAR_ON="#" UI_BAR_OFF="-" UI_H="-"
else
    UI_OK="✓" UI_FAIL="✗" UI_WARN="!" UI_ARROW="▸"
    UI_SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    UI_BAR_ON="━" UI_BAR_OFF="─" UI_H="─"
fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    if [ "${TERM:-}" = "linux" ]; then
        C_ACC=$'\e[1;33m' C_SEC=$'\e[1;36m'
    else
        C_ACC=$'\e[38;5;208m' C_SEC=$'\e[38;5;39m'
    fi
    C_OK=$'\e[32m' C_ERR=$'\e[31m' C_DIM=$'\e[2m' C_B=$'\e[1m' C_0=$'\e[0m'
    UI_ANIM=true
else
    C_ACC="" C_SEC="" C_OK="" C_ERR="" C_DIM="" C_B="" C_0=""
    UI_ANIM=false
fi

ui_banner() {
    printf '\n'

    # Linux-konsole: die lettertipe het geen blok-tekens nie - ASCII.
    if [ "${TERM:-}" = "linux" ]; then
        printf '%s' "$C_ACC"
        cat <<'EOF'
   ___           _  _           ___                    _
  | _ \ __ _  __| |(_) ___     / _ \  _ _  __ _  _ _  (_) __ _
  |   // _` |/ _` || |/ _ \   | (_) || '_|/ _` || ' \ | |/ _` |
  |_|_\\__,_|\__,_||_|\___/    \___/ |_|  \__,_||_||_||_|\__,_|
EOF
        printf '%s\n' "$C_0"
    else
        # Seinmas in blou, naam in oranje (Radio Orania se kleure, soos
        # radio-dash). C.UTF-8 sodat ${line:0:13} hele multigreep-tekens sny.
        local LC_ALL=C.UTF-8 line
        while IFS= read -r line; do
            printf '  %s%s%s%s%s\n' "$C_SEC$C_B" "${line:0:13}" "$C_ACC" "${line:13}" "$C_0"
        done <<'EOF'
((( ● )))    █▀▀█ ▄▀▀▄ █▀▀▄ ▀█▀ ▄▀▀▄    ▄▀▀▄ █▀▀█ ▄▀▀▄ █▄ █ ▀█▀ ▄▀▀▄
   ╱█╲       █▀█▀ █▀▀█ █  █  █  █  █    █  █ █▀█▀ █▀▀█ █ ▀█  █  █▀▀█
  ╱ █ ╲      ▀  ▀ ▀  ▀ ▀▀▀  ▀▀▀  ▀▀      ▀▀  ▀  ▀ ▀  ▀ ▀  ▀ ▀▀▀ ▀  ▀
EOF
        printf '\n'
    fi

    printf '  %s%s%s\n\n' "$C_SEC" "$1" "$C_0"
}

# ui_section [<nr> <totaal>] <titel>
ui_section() {
    local head="$UI_H$UI_H $1 "
    [ "$#" -eq 3 ] && head="$UI_H$UI_H $1/$2  $3 "
    local fill=""
    while [ "${#fill}" -lt $((60 - ${#head})) ]; do fill+="$UI_H"; done
    printf '\n%s%s%s%s\n\n' "$C_ACC$C_B" "$head" "$fill" "$C_0"
}

ui_hint() { printf '  %s%s%s\n' "$C_DIM" "$1" "$C_0"; }
ui_ok()   { printf '  %s%s%s %s\n' "$C_OK" "$UI_OK" "$C_0" "$1"; }
ui_fail() { printf '  %s%s%s %s\n' "$C_ERR" "$UI_FAIL" "$C_0" "$1"; }
ui_warn() { printf '  %s%s%s %s\n' "$C_ACC" "$UI_WARN" "$C_0" "$1"; }

# Prompt-teks vir "read -rp": ui_q <vraag> [verstek]
ui_q() {
    printf '  %s%s%s %s%s: ' "$C_SEC" "$UI_ARROW" "$C_0" "$1" "${2:+ ${C_DIM}[$2]$C_0}"
}

# Opsomming-reël: ui_kv <sleutel> <waarde>
ui_kv() { printf '  %s%-18s%s %s\n' "$C_DIM" "$1" "$C_0" "$2"; }

# ui_spin <etiket> <log> <opdrag...>
# Voer die opdrag in die agtergrond uit (uitset na die log) en wys intussen
# een lewendige reël: spinner, etiket, die stap se eie progress()-boodskap
# (via PROGRESS_FILE - sien progress.sh) en verstreke tyd. Eindig as
# "✓ etiket  12s", of "✗" plus die laaste log-reëls van hierdie stap.
ui_spin() {

    local label="$1" log="$2"
    shift 2

    local offset pf pid status=0 i=0 t0=$SECONDS detail cols bar pct msg n
    offset=$(stat -c %s "$log" 2>/dev/null || echo 0)
    pf=$(mktemp)

    PROGRESS_FILE="$pf" "$@" >>"$log" 2>&1 </dev/null &
    pid=$!

    if [ "$UI_ANIM" = true ]; then
        while kill -0 "$pid" 2>/dev/null; do
            detail=""
            IFS='|' read -r pct msg <"$pf" 2>/dev/null || true
            if [ -n "${pct:-}" ]; then
                bar=""
                for ((n = 0; n < 10; n++)); do
                    if [ "$n" -lt $((pct / 10)) ]; then bar+="$UI_BAR_ON"; else bar+="$UI_BAR_OFF"; fi
                done
                cols=$(tput cols 2>/dev/null || echo 80)
                msg="${msg:0:$((cols > 70 ? cols - 70 : 0))}"
                detail="$C_ACC$bar$C_0 $C_DIM$msg$C_0"
            fi
            printf '\r\e[K  %s%s%s %-34s %s %s%ds%s' \
                "$C_SEC" "${UI_SPIN[i % ${#UI_SPIN[@]}]}" "$C_0" "$label" \
                "$detail" "$C_DIM" $((SECONDS - t0)) "$C_0"
            i=$((i + 1))
            sleep 0.15
        done
    fi

    wait "$pid" || status=$?
    rm -f "$pf"

    [ "$UI_ANIM" = true ] && printf '\r\e[K'

    if [ "$status" -eq 0 ]; then
        printf '  %s%s%s %-34s %s%ds%s\n' "$C_OK" "$UI_OK" "$C_0" "$label" "$C_DIM" $((SECONDS - t0)) "$C_0"
    else
        printf '  %s%s %-34s (kode %d)%s\n\n' "$C_ERR" "$UI_FAIL" "$label" "$status" "$C_0"
        tail -c +$((offset + 1)) "$log" | grep -vE '^\s*$|^   \[' | tail -12 | sed "s/^/    $C_DIM/; s/\$/$C_0/"
        printf '\n'
    fi

    return "$status"
}
