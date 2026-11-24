#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    printf 'Run as root.\n' >&2
    exit 1
fi

ip -n r1 link show r1-sw >/dev/null
for vlan in 10 20; do
    if ! ip -n r1 link show "r1-sw.$vlan" >/dev/null 2>&1; then
        ip -n r1 link add link r1-sw name "r1-sw.$vlan" type vlan id "$vlan"
    fi
    ip -n r1 addr replace "192.168.$vlan.1/24" dev "r1-sw.$vlan"
    ip -n r1 link set "r1-sw.$vlan" up
done

ip -n h1 route replace default via 192.168.10.1 dev eth0
ip -n h3 route replace default via 192.168.10.1 dev eth0
ip -n h5 route replace default via 192.168.10.1 dev eth0
ip -n h2 route replace default via 192.168.20.1 dev eth0
ip -n h4 route replace default via 192.168.20.1 dev eth0
ip -n h6 route replace default via 192.168.20.1 dev eth0
