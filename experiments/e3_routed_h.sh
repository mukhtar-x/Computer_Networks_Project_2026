#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if [[ ${EUID} -ne 0 ]]; then
    printf 'Run as root.\n' >&2
    exit 1
fi

result=results/e3.csv
sw1_pid=
sw2_pid=
server_pid=

printf '==== E3 | Routed-link delay ====\n'
printf 'Measures ping RTT, TCP throughput, and H1-to-S1 traceroute at 20/100/200 ms.\n'

print_summary() {
    python3 - "$result" <<'PY'
import csv
import statistics
import sys

groups = {}
with open(sys.argv[1], newline="", encoding="utf-8") as source:
    for row in csv.DictReader(source):
        groups.setdefault((row["condition"], row["metric"]), []).append(
            float(row["value"])
        )
print("==== E3 result summary ====")
print(f"{'Condition':<14} | {'Metric':<18} | {'Mean':>10} | {'Std dev':>10}")
print(f"{'-' * 14}-+-{'-' * 18}-+-{'-' * 10}-+-{'-' * 10}")
for (condition, metric), values in sorted(groups.items()):
    mean = statistics.mean(values)
    stdev = statistics.stdev(values) if len(values) > 1 else 0
    print(f"{condition:<14} | {metric:<18} | {mean:>10.3f} | {stdev:>10.3f}")
print(f"CSV: {sys.argv[1]}")
PY
}

stop_processes() {
    for pid in "$sw1_pid" "$sw2_pid" "$server_pid"; do
        if [[ -n $pid ]]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    sw1_pid=
    sw2_pid=
    server_pid=
}
cleanup() {
    stop_processes
    topology/impair_h.sh clear r1-r2 || true
    rm -f results/.e3_iperf.log
}
trap cleanup EXIT

topology/setup_h.sh
topology/r1_subif_r.sh
topology/r1_forward_r.sh on >/dev/null
printf 'COMMAND: ip netns exec sw1 python3 switch/switch_d.py '
printf '%s\n' '--config switch/config_sw1_d.json'
ip netns exec sw1 python3 switch/switch_d.py --config switch/config_sw1_d.json > /dev/null 2>&1 &
sw1_pid=$!
printf 'COMMAND: ip netns exec sw2 python3 switch/switch_d.py '
printf '%s\n' '--config switch/config_sw2_d.json'
ip netns exec sw2 python3 switch/switch_d.py --config switch/config_sw2_d.json > /dev/null 2>&1 &
sw2_pid=$!
printf 'COMMAND: ip netns exec s1 iperf3 -s\n'
ip netns exec s1 iperf3 -s > results/.e3_iperf.log 2>&1 &
server_pid=$!
sleep 1
printf 'experiment,condition,run,metric,value\n' > "$result"

for delay in 20 100 200; do
    printf 'Condition: R1-R2 delay=%d ms\n' "$delay"
    printf 'COMMAND: topology/impair_h.sh r1-r2 %d 0\n' "$delay"
    topology/impair_h.sh r1-r2 "$delay" 0
    for run in 1 2 3; do
        printf 'E3 | delay=%dms | run %d/3\n' "$delay" "$run"
        printf 'COMMAND: ip netns exec h1 ping -n -c 5 -W 5 10.0.30.10\n'
        rtt=$(ip netns exec h1 ping -n -c 5 -W 5 10.0.30.10 | awk -F'=' '/rtt|round-trip/ {split($2,a,"/"); print a[2]; exit}')
        printf 'COMMAND: ip netns exec h1 iperf3 -c 10.0.30.10 -t 30 -J\n'
        throughput=$(ip netns exec h1 iperf3 -c 10.0.30.10 -t 30 -J | python3 -c 'import json,sys; print(json.load(sys.stdin)["end"]["sum_received"]["bits_per_second"] / 1000000)')
        printf 'COMMAND: ip netns exec h1 traceroute -n -m 5 -w 2 10.0.30.10\n'
        hops=$(ip netns exec h1 traceroute -n -m 5 -w 2 10.0.30.10 | awk '/^[[:space:]]*[0-9]+[[:space:]]/ {n++} END {print n+0}')
        printf 'E3,delay=%sms,%s,ping_rtt_ms,%s\n' "$delay" "$run" "${rtt:-0}" >> "$result"
        printf 'E3,delay=%sms,%s,throughput_mbps,%s\n' "$delay" "$run" "$throughput" >> "$result"
        printf 'E3,delay=%sms,%s,traceroute_hops,%s\n' "$delay" "$run" "$hops" >> "$result"
        printf 'E3 | delay=%dms | run %d/3 | RTT=%s ms | %.2f Mbit/s | hops=%s\n' \
            "$delay" "$run" "${rtt:-0}" "$throughput" "$hops"
    done
done
print_summary
