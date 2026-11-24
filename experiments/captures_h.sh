#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if [[ ${EUID} -ne 0 ]]; then
    printf 'Run as root.\n' >&2
    exit 1
fi
if ! command -v dumpcap >/dev/null 2>&1; then
    printf 'dumpcap is required; install the wireshark package.\n' >&2
    exit 1
fi

printf '==== Captures | ARP, VLAN trunk, CRC frames, traceroute ====\n'
printf 'Conditions: h1 ARP, SW1 p4 tagged traffic, EtherType 0x88B5, H1 to S1.\n'

sw1_pid=
sw2_pid=
capture_pids=()
cleanup() {
    for pid in "${capture_pids[@]}"; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    for pid in "$sw1_pid" "$sw2_pid"; do
        if [[ -n $pid ]]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
}
trap cleanup EXIT

mkdir -p captures
topology/setup_h.sh
topology/r1_subif_r.sh
topology/r1_forward_r.sh on >/dev/null
ip netns exec sw1 python3 switch/switch_d.py --config switch/config_sw1_d.json > /dev/null 2>&1 &
sw1_pid=$!
ip netns exec sw2 python3 switch/switch_d.py --config switch/config_sw2_d.json > /dev/null 2>&1 &
sw2_pid=$!
sleep 1

printf 'COMMAND: ip netns exec sw1 dumpcap -q -i p1 -f arp -w captures/arp.pcapng\n'
ip netns exec sw1 dumpcap -q -i p1 -f arp -w captures/arp.pcapng >/dev/null 2>&1 &
capture_pids+=("$!")
printf 'COMMAND: ip netns exec sw1 dumpcap -q -i p4 -f vlan -w captures/trunk.pcapng\n'
ip netns exec sw1 dumpcap -q -i p4 -f vlan -w captures/trunk.pcapng >/dev/null 2>&1 &
capture_pids+=("$!")
printf 'COMMAND: ip netns exec sw1 dumpcap -q -i p1 \\\n'
printf "  -f 'ether proto 0x88b5' -w captures/crc32.pcapng\n"
ip netns exec sw1 dumpcap -q -i p1 -f 'ether proto 0x88b5' -w captures/crc32.pcapng >/dev/null 2>&1 &
capture_pids+=("$!")
printf 'COMMAND: ip netns exec sw1 dumpcap -q -i p1 -f icmp '
printf '%s\n' '-w captures/traceroute.pcapng'
ip netns exec sw1 dumpcap -q -i p1 -f icmp -w captures/traceroute.pcapng >/dev/null 2>&1 &
capture_pids+=("$!")
sleep 1
ip -n h1 neigh flush dev eth0 >/dev/null 2>&1 || true
printf 'COMMAND: ip netns exec h1 ping -n -c 2 -W 2 192.168.10.12\n'
ip netns exec h1 ping -n -c 2 -W 2 192.168.10.12
printf 'COMMAND: ip netns exec h1 ping -n -c 2 -W 2 192.168.10.13\n'
ip netns exec h1 ping -n -c 2 -W 2 192.168.10.13
printf 'COMMAND: ip netns exec h1 python3 errors/generator_h.py eth0 '
printf '02:00:00:00:00:03 --count 100\n'
ip netns exec h1 python3 errors/generator_h.py eth0 02:00:00:00:00:03 --count 100
printf 'COMMAND: ip netns exec h1 traceroute -n -m 5 -w 1 10.0.30.10\n'
ip netns exec h1 traceroute -n -m 5 -w 1 10.0.30.10
sleep 1
for pid in "${capture_pids[@]}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
done
capture_pids=()
printf '==== Capture files ====\n'
for file in captures/arp.pcapng captures/trunk.pcapng captures/crc32.pcapng \
    captures/traceroute.pcapng; do
    packets=$(capinfos -c "$file" 2>/dev/null | awk -F': ' '/Number of packets/ {print $2}')
    size=$(du -h "$file" | awk '{print $1}')
    printf '%-22s packets=%-8s size=%s\n' "$file" "${packets:-unknown}" "$size"
done
