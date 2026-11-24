#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    printf 'Run as root.\n' >&2
    exit 1
fi

if [[ $# -ne 1 || ($1 != on && $1 != off) ]]; then
    printf 'Usage: %s on|off\n' "$0" >&2
    exit 2
fi

value=0
if [[ $1 == on ]]; then
    value=1
fi
ip netns exec r1 sysctl -w "net.ipv4.ip_forward=$value"
ip netns exec r1 sysctl -n net.ipv4.ip_forward
