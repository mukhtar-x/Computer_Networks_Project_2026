#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if [[ ${EUID} -ne 0 ]]; then
    printf 'Run as root.\n' >&2
    exit 1
fi

result=results/e5.csv
sw1_pid=
sw2_pid=
if [[ -t 1 ]]; then
    GREEN=$'\033[32m'
    RED=$'\033[31m'
    RESET=$'\033[0m'
else
    GREEN=
    RED=
    RESET=
fi

printf '==== E5 | VLAN isolation ====\n'
printf 'Measures same-VLAN trunk reachability and cross-VLAN forwarding isolation.\n'
printf 'Conditions: same VLAN; cross VLAN with R1 forwarding OFF and ON.\n'

print_summary() {
    python3 - "$result" <<'PY'
import csv
import statistics
import sys

expected = {
    "same_vlan_trunk": 1,
    "cross_vlan_forward_off": 0,
    "cross_vlan_forward_on": 1,
}
groups = {}
with open(sys.argv[1], newline="", encoding="utf-8") as source:
    for row in csv.DictReader(source):
        groups.setdefault((row["condition"], row["metric"]), []).append(
            float(row["value"])
        )
print("==== E5 result summary ====")
print(f"{'Case':<26} | {'Metric':<15} | {'Mean':>10} | {'Std dev':>10} | {'Outcome':<8}")
print(f"{'-' * 26}-+-{'-' * 15}-+-{'-' * 10}-+-{'-' * 10}-+-{'-' * 8}")
for (condition, metric), values in sorted(groups.items()):
    mean = statistics.mean(values)
    stdev = statistics.stdev(values) if len(values) > 1 else 0
    outcome = ""
    if metric == "ping_pass":
        outcome = "PASS" if all(value == expected[condition] for value in values) else "FAIL"
    print(
        f"{condition:<26} | {metric:<15} | {mean:>10.3f} | {stdev:>10.3f} | "
        f"{outcome:<8}"
    )
print(f"CSV: {sys.argv[1]}")
PY
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
cleanup() {
    stop_switches
    rm -f results/.e5_capture.pcap
}
trap cleanup EXIT

topology/setup_h.sh
topology/r1_subif_r.sh
ip netns exec sw1 python3 switch/switch_d.py --config switch/config_sw1_d.json > /dev/null 2>&1 &
sw1_pid=$!
ip netns exec sw2 python3 switch/switch_d.py --config switch/config_sw2_d.json > /dev/null 2>&1 &
sw2_pid=$!
sleep 1
ip netns exec h1 ping -n -c 1 -W 2 192.168.10.1 >/dev/null
printf 'experiment,condition,run,metric,value\n' > "$result"

for run in 1 2 3; do
    for case_name in same_vlan_trunk cross_vlan_forward_off cross_vlan_forward_on; do
        expected=1
        label='h1 -> h5, VLAN10 trunk'
        case "$case_name" in
            same_vlan_trunk) destination=192.168.10.13 ;;
            cross_vlan_forward_off)
                topology/r1_forward_r.sh off >/dev/null
                destination=192.168.20.11
                expected=0
                label='h1 -> h2, R1 forwarding OFF'
                ;;
            cross_vlan_forward_on)
                topology/r1_forward_r.sh on >/dev/null
                destination=192.168.20.11
                label='h1 -> h2, R1 forwarding ON'
                ;;
        esac
        expected_text=pass
        if [[ $expected -eq 0 ]]; then
            expected_text=fail
        fi
        printf 'Condition: %s | expected: %s | run %d/3\n' "$label" "$expected_text" "$run"
        printf 'COMMAND: ip netns exec sw1 tcpdump -Q out -e -ni p2 '
        printf "'ether host 02:00:00:00:00:01' -w results/.e5_capture.pcap\n"
        printf 'COMMAND: tcpdump -nn -r results/.e5_capture.pcap\n'
        printf 'COMMAND: ip netns exec h1 ping -n -c 2 -W 2 %s\n' "$destination"
        ip netns exec sw1 tcpdump -U -Q out -e -ni p2 "ether host 02:00:00:00:00:01" -w results/.e5_capture.pcap >/dev/null 2>&1 &
        capture_pid=$!
        sleep 0.2
        if ip netns exec h1 ping -n -c 2 -W 2 "$destination" >/dev/null 2>&1; then
            pass=1
        else
            pass=0
        fi
        sleep 0.2
        pkill -f "tcpdump.*e5_capture" 2>/dev/null || true
        kill -9 "$capture_pid" 2>/dev/null || true
        sleep 0.3
        kill -9 "$capture_pid" 2>/dev/null || true
        leaked=$(tcpdump -nn -r results/.e5_capture.pcap 2>/dev/null | wc -l)
        printf 'E5,%s,%s,ping_pass,%s\n' "$case_name" "$run" "$pass" >> "$result"
        printf 'E5,%s,%s,leaked_frames,%s\n' "$case_name" "$run" "$leaked" >> "$result"
        got=fail
        if [[ $pass -eq 1 ]]; then
            got=pass
        fi
        if [[ $pass -eq $expected ]]; then
            mark=PASS
            color=$GREEN
        else
            mark=FAIL
            color=$RED
        fi
        printf '%s | expected: %s | got: %s | [%s%s%s] | leaked frames: %s\n' \
            "$label" "$expected_text" "$got" "$color" "$mark" "$RESET" "$leaked"
    done
done
print_summary
