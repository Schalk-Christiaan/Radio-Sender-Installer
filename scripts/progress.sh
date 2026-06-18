#!/bin/bash

progress() {

    local percent="$1"
    local message="$2"

    local bars=$((percent / 5))

    printf "\r   ["

    for ((i=0;i<20;i++)); do

        if [ "$i" -lt "$bars" ]; then
            printf "#"
        else
            printf "-"
        fi

    done

    printf "] %3d%% %s" "$percent" "$message"

    if [ "$percent" -eq 100 ]; then
        echo
    fi
}