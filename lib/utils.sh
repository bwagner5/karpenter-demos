#!/usr/bin/env bash
set -euo pipefail

## 10-100
SPEED=30

function cmd() {
    local cmd="${1}"
    if [[ ! -z ${cmd} ]]; then
        echo -e "\n"
        echo -en "> ${cmd}" | pv -qL "${SPEED}"
        read -n 1 -s
        echo -e "\n"
        eval $cmd
        echo -e "\n"
        read -n 1 -s
    fi
}