#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    printf 'Run as root.\n' >&2
    exit 1
fi

if [[ $# -ne 1 || ($1 != start && $1 != stop) ]]; then
    printf 'Usage: %s start|stop\n' "$0" >&2
    exit 2
fi

configure_bridge() {
    local ns=$1
    shift
    ip netns exec "$ns" ip link add br0 type bridge vlan_filtering 1
    ip netns exec "$ns" ip link set br0 up
    ip netns exec "$ns" bridge vlan add dev br0 vid 10 self
    ip netns exec "$ns" bridge vlan add dev br0 vid 20 self
    for spec in "$@"; do
        local port=${spec%%:*}
        local vlans=${spec#*:}
        ip netns exec "$ns" ip link set "$port" master br0
        if [[ $vlans == *","* ]]; then
            for vlan in ${vlans//,/ }; do
                ip netns exec "$ns" bridge vlan add dev "$port" vid "$vlan"
            done
        elif [[ $port == p4 || $port == p5 ]]; then
            for vlan in 10 20; do
                ip netns exec "$ns" bridge vlan add dev "$port" vid "$vlan"
            done
        else
            ip netns exec "$ns" bridge vlan add dev "$port" vid "$vlans" pvid untagged
        fi
    done
}

if [[ $1 == stop ]]; then
    for ns in sw1 sw2; do
        if ip -n "$ns" link show br0 >/dev/null 2>&1; then
            ip -n "$ns" link del br0
        fi
    done
    exit 0
fi

for ns in sw1 sw2; do
    if ip -n "$ns" link show br0 >/dev/null 2>&1; then
        printf 'Bridge already exists in %s.\n' "$ns" >&2
        exit 1
    fi
done

configure_bridge sw1 p1:10 p2:20 p3:10 p4:10,20 p5:10,20
configure_bridge sw2 p1:20 p2:10 p3:20 p4:10,20
