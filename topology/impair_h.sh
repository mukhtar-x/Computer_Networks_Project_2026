#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    printf 'Run as root.\n' >&2
    exit 1
fi

if [[ $# -eq 2 && $1 == clear ]]; then
    action=clear
    target=$2
elif [[ $# -eq 2 && $2 == clear ]]; then
    action=clear
    target=$1
elif [[ $# -eq 3 ]]; then
    action=apply
    target=$1
    delay=$2
    rate=$3
else
    printf 'Usage: %s LINK DELAY_MS RATE_MBIT | clear LINK\n' "$0" >&2
    exit 2
fi

case "$target" in
    r1-r2) ns=r1; iface=r1-r2 ;;
    h1|h2|h3|h4|h5|h6) ns=$target; iface=eth0 ;;
    *) printf 'Unsupported link: %s\n' "$target" >&2; exit 2 ;;
esac

if ! ip netns list | awk '{print $1}' | grep -Fxq "$ns"; then
    printf 'Namespace %s does not exist.\n' "$ns" >&2
    exit 1
fi

if [[ $action == clear ]]; then
    ip netns exec "$ns" tc qdisc del dev "$iface" root 2>/dev/null || true
    exit 0
fi

if [[ ! $delay =~ ^[0-9]+([.][0-9]+)?$ || ! $rate =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf 'Delay and rate must be non-negative numbers.\n' >&2
    exit 2
fi

ip netns exec "$ns" tc qdisc del dev "$iface" root 2>/dev/null || true
if awk -v rate="$rate" 'BEGIN { exit !(rate == 0) }'; then
    ip netns exec "$ns" tc qdisc add dev "$iface" root netem delay "${delay}ms"
else
    ip netns exec "$ns" tc qdisc add dev "$iface" root handle 1: tbf rate "${rate}mbit" burst 32k latency 400ms
    ip netns exec "$ns" tc qdisc add dev "$iface" parent 1:1 handle 10: netem delay "${delay}ms"
fi
