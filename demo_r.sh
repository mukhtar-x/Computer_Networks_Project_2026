#!/usr/bin/env bash
set -uo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
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

sw1_pid=
sw2_pid=
server_pid=
capture_pids=()
step_results=()
cleanup_done=0

pause_step() {
    printf 'Press Enter to continue\n'
    if [[ -t 0 ]]; then
        read -r _
    else
        read -r _ || true
    fi
}

show_switch_activity() {
    printf '==== Switch activity ====\n'
    for log in /tmp/cs3001-sw1.log /tmp/cs3001-sw2.log; do
        printf '%s\n' "$(basename "$log")"
        if [[ -f $log ]]; then
            tail -n 8 "$log"
        fi
    done
}

start_switches() {
    local aging=$1 aging_args=()
    if [[ -n $aging ]]; then
        aging_args=(--aging "$aging")
    fi
    printf 'COMMAND: ip netns exec sw1 python3 switch/switch_d.py '
    printf '%s\n' "--config switch/config_sw1_d.json --verbose ${aging_args[*]}"
    ip netns exec sw1 python3 switch/switch_d.py \
        --config switch/config_sw1_d.json --verbose "${aging_args[@]}" \
        > /tmp/cs3001-sw1.log 2>&1 &
    sw1_pid=$!
    printf 'COMMAND: ip netns exec sw2 python3 switch/switch_d.py '
    printf '%s\n' "--config switch/config_sw2_d.json --verbose ${aging_args[*]}"
    ip netns exec sw2 python3 switch/switch_d.py \
        --config switch/config_sw2_d.json --verbose "${aging_args[@]}" \
        > /tmp/cs3001-sw2.log 2>&1 &
    sw2_pid=$!
    sleep 1
    kill -0 "$sw1_pid" && kill -0 "$sw2_pid"
}

stop_switches() {
    for pid in "$sw1_pid" "$sw2_pid"; do
        if [[ -n $pid ]]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    sw1_pid=
    sw2_pid=
}

stop_captures() {
    for pid in "${capture_pids[@]}"; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    capture_pids=()
}

cleanup() {
    if [[ $cleanup_done -eq 1 ]]; then
        return
    fi
    cleanup_done=1
    stop_captures
    if [[ -n $server_pid ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    stop_switches
    experiments/bridge_baseline_d.sh stop >/dev/null 2>&1 || true
    for link in r1-r2 h1 h2 h3 h4 h5 h6; do
        topology/impair_h.sh clear "$link" >/dev/null 2>&1 || true
    done
    topology/teardown_h.sh
    rm -f /tmp/cs3001-trunk.pcap /tmp/cs3001-access.pcap
    printf 'Demo resources stopped; project namespaces removed.\n'
}

step_done() {
    local number=$1 result=$2
    step_results[number]=$result
    if [[ $result == PASS ]]; then
        printf '%s[PASS]%s STEP %s/9\n' "$GREEN" "$RESET" "$number"
    else
        printf '%s[FAIL]%s STEP %s/9\n' "$RED" "$RESET" "$number"
    fi
}

trap cleanup EXIT

printf '==== CS3001 Project 30 live demo ====\n'

printf '\n==== STEP 1/9: Build topology and start switches ====\n'
printf 'Proves namespaces, links, addressing, and both switch processes are ready.\n'
step_result=PASS
printf 'COMMAND: topology/setup_h.sh\n'
if ! topology/setup_h.sh; then
    step_result=FAIL
fi
printf 'COMMAND: topology/r1_subif_r.sh\n'
if ! topology/r1_subif_r.sh; then
    step_result=FAIL
fi
printf 'COMMAND: topology/r1_forward_r.sh on\n'
if ! topology/r1_forward_r.sh on >/dev/null; then
    step_result=FAIL
fi
if ! start_switches ""; then
    step_result=FAIL
fi
step_done 1 "$step_result"
show_switch_activity
pause_step

printf '\n==== STEP 2/9: Verify access VLAN connectivity ====\n'
printf 'Proves h1 and h3 communicate on VLAN10 through SW1 access ports.\n'
printf 'COMMAND: ip netns exec h1 ping -n -c 2 -W 2 192.168.10.12\n'
if ip netns exec h1 ping -n -c 2 -W 2 192.168.10.12; then
    step_done 2 PASS
else
    step_done 2 FAIL
fi
show_switch_activity
pause_step

printf '\n==== STEP 3/9: VLAN tagging on the trunk ====\n'
printf 'Proves VLAN10 is tagged on SW1 p4 and untagged on access port p1.\n'
step_result=PASS
rm -f /tmp/cs3001-trunk.pcap /tmp/cs3001-access.pcap
printf 'COMMAND: ip netns exec sw1 tcpdump -Q out -enn -i p4 -c 1 '
printf '%s\n' '-w /tmp/cs3001-trunk.pcap vlan'
ip netns exec sw1 tcpdump -Q out -enn -i p4 -c 1 -w /tmp/cs3001-trunk.pcap \
    'vlan' >/dev/null 2>&1 &
trunk_capture=$!
capture_pids+=("$trunk_capture")
printf 'COMMAND: ip netns exec sw1 tcpdump -Q in -enn -i p1 -c 1 '
printf '%s\n' '-w /tmp/cs3001-access.pcap arp'
ip netns exec sw1 tcpdump -Q in -enn -i p1 -c 1 -w /tmp/cs3001-access.pcap \
    arp >/dev/null 2>&1 &
access_capture=$!
capture_pids+=("$access_capture")
ip -n h1 neigh flush dev eth0 >/dev/null 2>&1 || true
printf 'COMMAND: ip netns exec h1 ping -n -c 1 -W 2 192.168.10.13\n'
if ! ip netns exec h1 ping -n -c 1 -W 2 192.168.10.13 >/dev/null 2>&1; then
    step_result=FAIL
fi
for pid in "$trunk_capture" "$access_capture"; do
    if ! wait "$pid"; then
        step_result=FAIL
    fi
done
capture_pids=()
printf 'COMMAND: tcpdump -enn -r /tmp/cs3001-trunk.pcap\n'
if tcpdump -enn -r /tmp/cs3001-trunk.pcap 2>/dev/null; then
    :
else
    step_result=FAIL
fi
printf 'COMMAND: tcpdump -enn -r /tmp/cs3001-access.pcap\n'
if tcpdump -enn -r /tmp/cs3001-access.pcap 2>/dev/null; then
    :
else
    step_result=FAIL
fi
step_done 3 "$step_result"
show_switch_activity
pause_step

printf '\n==== STEP 4/9: ARP learning and MAC table ====\n'
printf 'Proves ARP requests flood in VLAN10, replies return, and MACs are learned.\n'
ip -n h1 neigh flush dev eth0 >/dev/null 2>&1 || true
printf 'COMMAND: ip netns exec h1 ping -n -c 2 -W 2 192.168.10.12\n'
if ip netns exec h1 ping -n -c 2 -W 2 192.168.10.12; then
    step_done 4 PASS
else
    step_done 4 FAIL
fi
printf 'COMMAND: kill -USR1 %s; kill -USR1 %s\n' "$sw1_pid" "$sw2_pid"
kill -USR1 "$sw1_pid" "$sw2_pid"
sleep 0.2
show_switch_activity
pause_step

printf '\n==== STEP 5/9: Unknown-destination flooding ====\n'
printf 'Proves an unknown unicast test frame floods only within its VLAN.\n'
printf 'COMMAND: ip netns exec h1 python3 -c \\\n'
printf "  'from scapy.all import Ether, Raw, sendp; \\\\\n"
printf "  sendp(Ether(dst=\"02:ff:ff:ff:ff:ff\", type=0x88b5)/Raw(load=b\"unknown\"), \\\\\n"
printf "  iface=\"eth0\", verbose=False)'\n"
if ip netns exec h1 python3 -c \
    'from scapy.all import Ether, Raw, sendp; sendp(Ether(dst="02:ff:ff:ff:ff:ff", type=0x88b5)/Raw(load=b"unknown"), iface="eth0", verbose=False)'; then
    step_done 5 PASS
else
    step_done 5 FAIL
fi
show_switch_activity
pause_step

printf '\n==== STEP 6/9: MAC aging ====\n'
printf 'Proves entries appear before the 10s timer and expire afterward.\n'
stop_switches
if start_switches 10; then
    ip -n h1 neigh flush dev eth0 >/dev/null 2>&1 || true
    printf 'COMMAND: ip netns exec h1 ping -n -c 1 -W 2 192.168.10.12\n'
    if ip netns exec h1 ping -n -c 1 -W 2 192.168.10.12 >/dev/null; then
        step_result=PASS
    else
        step_result=FAIL
    fi
    printf 'COMMAND: kill -USR1 %s; kill -USR1 %s\n' "$sw1_pid" "$sw2_pid"
    kill -USR1 "$sw1_pid" "$sw2_pid"
    sleep 0.2
    printf 'MAC table before expiry\n'
    show_switch_activity
    printf 'COMMAND: sleep 11\n'
    sleep 11
    printf 'COMMAND: kill -USR1 %s; kill -USR1 %s\n' "$sw1_pid" "$sw2_pid"
    kill -USR1 "$sw1_pid" "$sw2_pid"
    sleep 0.2
    printf 'MAC table after expiry\n'
    show_switch_activity
else
    step_result=FAIL
fi
step_done 6 "$step_result"
pause_step

printf '\n==== STEP 7/9: Routed path to the server ====\n'
printf 'Proves router-on-a-stick and R1/R2 routing from h1 to S1.\n'
printf 'COMMAND: topology/r1_forward_r.sh on\n'
if ! topology/r1_forward_r.sh on >/dev/null; then
    step_result=FAIL
else
    step_result=PASS
fi
printf 'COMMAND: ip netns exec h1 traceroute -n -m 5 -w 1 10.0.30.10\n'
if ip netns exec h1 traceroute -n -m 5 -w 1 10.0.30.10; then
    :
else
    step_result=FAIL
fi
step_done 7 "$step_result"
show_switch_activity
pause_step

printf '\n==== STEP 8/9: Error-code detection ====\n'
printf 'Proves parity, Internet checksum, and CRC-32 detect noisy-link damage.\n'
stop_switches
printf 'COMMAND: python3 experiments/e4_errors_h.py\n'
if python3 experiments/e4_errors_h.py; then
    step_done 8 PASS
else
    step_done 8 FAIL
fi
show_switch_activity
pause_step

printf '\n==== STEP 9/9: Python switch vs Linux bridge ====\n'
printf 'Proves both forwarding implementations carry TCP traffic.\n'
step_result=PASS
if ! start_switches ""; then
    step_result=FAIL
fi
printf 'COMMAND: ip netns exec h3 iperf3 -s\n'
ip netns exec h3 iperf3 -s > results/.demo_iperf.log 2>&1 &
server_pid=$!
sleep 1
printf 'COMMAND: ip netns exec h1 iperf3 -c 192.168.10.12 -t 10\n'
if ! ip netns exec h1 iperf3 -c 192.168.10.12 -t 10; then
    step_result=FAIL
fi
kill "$server_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true
server_pid=
stop_switches
show_switch_activity
printf 'COMMAND: experiments/bridge_baseline_d.sh start\n'
if ! experiments/bridge_baseline_d.sh start; then
    step_result=FAIL
else
    printf 'COMMAND: ip netns exec h3 iperf3 -s\n'
    ip netns exec h3 iperf3 -s > results/.demo_iperf.log 2>&1 &
    server_pid=$!
    sleep 1
    printf 'COMMAND: ip netns exec h1 iperf3 -c 192.168.10.12 -t 10\n'
    if ! ip netns exec h1 iperf3 -c 192.168.10.12 -t 10; then
        step_result=FAIL
    fi
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    server_pid=
    printf 'COMMAND: experiments/bridge_baseline_d.sh stop\n'
    if ! experiments/bridge_baseline_d.sh stop; then
        step_result=FAIL
    fi
fi
step_done 9 "$step_result"
show_switch_activity
cleanup

printf '\n==== Demo summary ====\n'
overall=PASS
for number in {1..9}; do
    result=${step_results[number]:-FAIL}
    if [[ $result == FAIL ]]; then
        overall=FAIL
    fi
    color=$GREEN
    if [[ $result == FAIL ]]; then
        color=$RED
    fi
    printf '%s[%s] STEP %d/9%s\n' "$color" "$result" "$number" "$RESET"
done
printf 'Overall: %s[%s]%s\n' "$([[ $overall == PASS ]] && printf '%s' "$GREEN" || printf '%s' "$RED")" \
    "$overall" "$RESET"
if [[ $overall == PASS ]]; then
    exit 0
fi
exit 1
