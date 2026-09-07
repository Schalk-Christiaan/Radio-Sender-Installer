#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/progress.sh"

progress 40 "Installeer radioctl"

install -m 755 \
    "$SCRIPT_DIR/../templates/radioctl.sh" \
    /usr/local/bin/radioctl

progress 100 "Klaar"
