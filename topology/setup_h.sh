#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAMESPACES=(h1 h2 h3 h4 h5 h6 sw1 sw2 r1 r2 s1)

if [[ ${EUID} -ne 0 ]]; then
    printf 'Run as root.\n' >&2
    exit 1
fi

if [[ -t 1 ]]; then
    GREEN=$'\033[32m'
    RED=$'\033[31m'
    RESET=$'\033[0m'
else
    GREEN=
    RED=
    RESET=
fi

trap 'result=$?; printf "%sSETUP FAILED at line %s: %s%s\n" "$RED" "$LINENO" "$BASH_COMMAND" "$RESET" >&2; exit "$result"' ERR

pass=0
fail=0
status() {
    local label=$1 result=$2
    if [[ $result -eq 0 ]]; then
        printf '%s: %s[PASS]%s\n' "$label" "$GREEN" "$RESET"
        pass=$((pass + 1))
    else
        printf '%s: %s[FAIL]%s\n' "$label" "$RED" "$RESET"
        fail=$((fail + 1))
    fi
}

printf '==== Namespaces ====\n'
"$ROOT/topology/teardown_h.sh" >/dev/null 2>&1
for ns in "${NAMESPACES[@]}"; do
    ip netns add "$ns" >/dev/null 2>&1
done

printf '==== Links ====\n'
add_pair() {
    local left_ns=$1 left_if=$2 right_ns=$3 right_if=$4
    ip link add "$left_if" netns "$left_ns" type veth peer name "$right_if" netns "$right_ns" \
        >/dev/null 2>&1
}

add_pair h1 eth0 sw1 p1
add_pair h2 eth0 sw1 p2
add_pair h3 eth0 sw1 p3
add_pair sw1 p4 sw2 p4
add_pair sw1 p5 r1 r1-sw
add_pair sw2 p1 h4 eth0
add_pair sw2 p2 h5 eth0
add_pair sw2 p3 h6 eth0
add_pair r1 r1-r2 r2 r2-r1
add_pair r2 r2-s1 s1 eth0

printf '==== Addressing ====\n'
ip -n h1 link set eth0 address 02:00:00:00:00:01 >/dev/null 2>&1
ip -n h2 link set eth0 address 02:00:00:00:00:02 >/dev/null 2>&1
ip -n h3 link set eth0 address 02:00:00:00:00:03 >/dev/null 2>&1
ip -n h4 link set eth0 address 02:00:00:00:00:04 >/dev/null 2>&1
ip -n h5 link set eth0 address 02:00:00:00:00:05 >/dev/null 2>&1
ip -n h6 link set eth0 address 02:00:00:00:00:06 >/dev/null 2>&1

ip -n h1 addr add 192.168.10.11/24 dev eth0 >/dev/null 2>&1
ip -n h2 addr add 192.168.20.11/24 dev eth0 >/dev/null 2>&1
ip -n h3 addr add 192.168.10.12/24 dev eth0 >/dev/null 2>&1
ip -n h4 addr add 192.168.20.12/24 dev eth0 >/dev/null 2>&1
ip -n h5 addr add 192.168.10.13/24 dev eth0 >/dev/null 2>&1
ip -n h6 addr add 192.168.20.13/24 dev eth0 >/dev/null 2>&1
ip -n r1 addr add 10.0.12.1/30 dev r1-r2 >/dev/null 2>&1
ip -n r2 addr add 10.0.12.2/30 dev r2-r1 >/dev/null 2>&1
ip -n r2 addr add 10.0.30.1/24 dev r2-s1 >/dev/null 2>&1
ip -n s1 addr add 10.0.30.10/24 dev eth0 >/dev/null 2>&1

INTERFACES=(h1:eth0 h2:eth0 h3:eth0 h4:eth0 h5:eth0 h6:eth0
    sw1:p1 sw1:p2 sw1:p3 sw1:p4 sw1:p5
    sw2:p1 sw2:p2 sw2:p3 sw2:p4
    r1:r1-sw r1:r1-r2 r2:r2-r1 r2:r2-s1 s1:eth0)
LINK_CHECKS=(sw1:p1 sw1:p2 sw1:p3 sw1:p4 sw1:p5
    sw2:p1 sw2:p2 sw2:p3 sw2:p4
    h1:eth0 h2:eth0 h3:eth0 h4:eth0 h5:eth0 h6:eth0)
declare -A link_states

printf '==== Interfaces up ====\n'
for ns in "${NAMESPACES[@]}"; do
    ip netns exec "$ns" sysctl -qw net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
    ip netns exec "$ns" sysctl -qw net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
done
for ns in "${NAMESPACES[@]}"; do
    ip -n "$ns" link set lo up >/dev/null 2>&1
done
for pair in "${INTERFACES[@]}"; do
    ns=${pair%%:*}
    iface=${pair#*:}
    ip -n "$ns" link set "$iface" up >/dev/null 2>&1
done

printf '==== Offloads ====\n'
for pair in "${INTERFACES[@]}"; do
    ns=${pair%%:*}
    iface=${pair#*:}
    ip netns exec "$ns" ethtool -K "$iface" rx off tx off rxvlan off txvlan off \
        tso off gso off gro off >/dev/null 2>&1
done

printf '==== Link reset ====\n'
for ns in "${NAMESPACES[@]}"; do
    ip -n "$ns" link set lo down >/dev/null 2>&1
done
for pair in "${INTERFACES[@]}"; do
    ns=${pair%%:*}
    iface=${pair#*:}
    ip -n "$ns" link set "$iface" down >/dev/null 2>&1
done
for ns in "${NAMESPACES[@]}"; do
    ip -n "$ns" link set lo up >/dev/null 2>&1
done
for pair in "${INTERFACES[@]}"; do
    ns=${pair%%:*}
    iface=${pair#*:}
    ip -n "$ns" link set "$iface" up >/dev/null 2>&1
done
sleep 1

link_fail=0
for pair in "${LINK_CHECKS[@]}"; do
    ns=${pair%%:*}
    iface=${pair#*:}
    if ip -n "$ns" -o link show dev "$iface" 2>/dev/null | grep -q 'LOWER_UP'; then
        link_states["$pair"]=UP
    else
        link_states["$pair"]=DOWN
        link_fail=1
    fi
done

printf '==== Routes ====\n'
ip -n r1 route add 10.0.30.0/24 via 10.0.12.2 >/dev/null 2>&1
ip -n r2 route add 192.168.10.0/24 via 10.0.12.1 >/dev/null 2>&1
ip -n r2 route add 192.168.20.0/24 via 10.0.12.1 >/dev/null 2>&1
ip -n s1 route add default via 10.0.30.1 >/dev/null 2>&1
ip netns exec r1 sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
ip netns exec r2 sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

if ip netns exec r1 ping -c 1 -W 2 10.0.12.2 >/dev/null 2>&1; then
    r2_ping=0
else
    r2_ping=1
fi
if ip netns exec r1 ping -c 1 -W 2 10.0.30.10 >/dev/null 2>&1; then
    s1_ping=0
else
    s1_ping=1
fi
if ip netns exec r1 traceroute -n -m 5 -w 1 10.0.30.10 >/dev/null 2>&1; then
    trace=0
else
    trace=1
fi

printf '==== Topology summary ====\n'
printf 'Namespaces (11): %s\n' "${NAMESPACES[*]}"
printf 'SW1 ports: p1=h1/VLAN10 p2=h2/VLAN20 p3=h3/VLAN10 p4=SW2 p4 p5=R1\n'
printf 'SW2 ports: p1=h4/VLAN20 p2=h5/VLAN10 p3=h6/VLAN20 p4=SW1 p4\n'
printf '%-12s %-18s %s\n' 'Segment' 'Subnet' 'Addresses'
printf '%-12s %-18s %s\n' 'VLAN10' '192.168.10.0/24' 'R1 .1, h1 .11, h3 .12, h5 .13'
printf '%-12s %-18s %s\n' 'VLAN20' '192.168.20.0/24' 'R1 .1, h2 .11, h4 .12, h6 .13'
printf '%-12s %-18s %s\n' 'Router link' '10.0.12.0/30' 'R1 .1, R2 .2'
printf '%-12s %-18s %s\n' 'Server' '10.0.30.0/24' 'R2 .1, S1 .10'
printf '==== Verification ====\n'
for pair in "${LINK_CHECKS[@]}"; do
    ns=${pair%%:*}
    iface=${pair#*:}
    state=${link_states[$pair]}
    result=0
    if [[ $state != UP ]]; then
        result=1
    fi
    status "$ns $iface $state" "$result"
done
if [[ $link_fail -gt 0 ]]; then
    false
fi
status 'r1 ping r2 (10.0.12.2)' "$r2_ping"
status 'r1 ping s1 (10.0.30.10)' "$s1_ping"
status 'r1 traceroute s1 (10.0.30.10)' "$trace"
printf 'Verification total: %d PASS, %d FAIL\n' "$pass" "$fail"
if [[ $fail -gt 0 ]]; then
    exit 1
fi
