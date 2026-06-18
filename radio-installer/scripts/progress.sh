progress() {

    local percent="$1"
    local message="$2"

    local bars=$((percent / 5))

    echo

    printf "   ["

    for ((i=0;i<20;i++)); do
        if [ "$i" -lt "$bars" ]; then
            printf "#"
        else
            printf "-"
        fi
    done

    printf "] %3d%% %s\n" "$percent" "$message"
}