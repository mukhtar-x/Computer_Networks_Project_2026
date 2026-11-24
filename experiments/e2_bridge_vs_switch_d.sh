#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if [[ ${EUID} -ne 0 ]]; then
    printf 'Run as root.\n' >&2
    exit 1
fi

result=results/e2.csv
sw1_pid=
sw2_pid=
server_pid=

printf '==== E2 | Python switch vs Linux bridge ====\n'
printf 'Measures TCP throughput, ping RTT, and CPU at 10/100 Mbit/s and no limit.\n'

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
print("==== E2 result summary ====")
print(f"{'Condition':<37} | {'Metric':<18} | {'Mean':>10} | {'Std dev':>10}")
print(f"{'-' * 37}-+-{'-' * 18}-+-{'-' * 10}-+-{'-' * 10}")
for (condition, metric), values in sorted(groups.items()):
    mean = statistics.mean(values)
    stdev = statistics.stdev(values) if len(values) > 1 else 0
    print(f"{condition:<37} | {metric:<18} | {mean:>10.3f} | {stdev:>10.3f}")
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

stop_server() {
    if [[ -n $server_pid ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
        server_pid=
    fi
}

cleanup() {
    stop_server
    stop_switches
    experiments/bridge_baseline_d.sh stop || true
    topology/impair_h.sh clear h1 || true
    rm -f results/.e2_iperf.log
}
trap cleanup EXIT

topology/setup_h.sh
topology/r1_subif_r.sh
printf 'experiment,condition,run,metric,value\n' > "$result"

start_switches() {
    printf 'COMMAND: ip netns exec sw1 python3 switch/switch_d.py '
    printf '%s\n' '--config switch/config_sw1_d.json'
    ip netns exec sw1 python3 switch/switch_d.py --config switch/config_sw1_d.json > /dev/null 2>&1 &
    sw1_pid=$!
    printf 'COMMAND: ip netns exec sw2 python3 switch/switch_d.py '
    printf '%s\n' '--config switch/config_sw2_d.json'
    ip netns exec sw2 python3 switch/switch_d.py --config switch/config_sw2_d.json > /dev/null 2>&1 &
    sw2_pid=$!
    sleep 1
}

measure() {
    local mode=$1 rate=$2 run=$3 cpu=0 rtt throughput cpu_before cpu_after rate_label
    rate_label="${rate}mbit"
    if [[ $rate == 0 ]]; then
        rate_label=unlimited
    fi
    printf 'COMMAND: ip netns exec h1 ping -n -c 5 -W 2 192.168.10.12\n'
    rtt=$(ip netns exec h1 ping -n -c 5 -W 2 192.168.10.12 | awk -F'=' '/rtt|round-trip/ {split($2,a,"/"); print a[2]; exit}')
    if [[ -z $rtt ]]; then
        rtt=0
    fi
    cpu_before=$(awk '/^cpu / {busy=$2+$3+$4+$7+$8; total=busy+$5+$6+$9; print busy,total}' /proc/stat)
    printf 'COMMAND: ip netns exec h1 iperf3 -c 192.168.10.12 -t 30 -J\n'
    throughput=$(ip netns exec h1 iperf3 -c 192.168.10.12 -t 30 -J | python3 -c 'import json,sys; print(json.load(sys.stdin)["end"]["sum_received"]["bits_per_second"] / 1000000)')
    if [[ $mode == python ]]; then
        cpu=$(ps -p "$sw1_pid,$sw2_pid" -o %cpu= | awk '{sum+=$1} END {print sum}')
        cpu=${cpu:-0}
    else
        cpu_after=$(awk '/^cpu / {busy=$2+$3+$4+$7+$8; total=busy+$5+$6+$9; print busy,total}' /proc/stat)
        cpu=$(awk -v before="$cpu_before" -v after="$cpu_after" 'BEGIN {split(before,a); split(after,b); total=b[2]-a[2]; if (total > 0) print (b[1]-a[1])/total*100; else print 0}')
    fi
    printf 'E2,%s,%s,throughput_mbps,%s\n' "rate=${rate_label}_mode=$mode" "$run" "$throughput" >> "$result"
    printf 'E2,%s,%s,ping_rtt_ms,%s\n' "rate=${rate_label}_mode=$mode" "$run" "$rtt" >> "$result"
    printf 'E2,%s,%s,switch_cpu_pct,%s\n' "rate=${rate_label}_mode=$mode" "$run" "$cpu" >> "$result"
    printf 'E2 | rate=%s | switch=%s | run %s/3 | %.2f Mbit/s\n' \
        "$rate_label" "$mode" "$run" "$throughput"
    printf '   RTT %.3f ms | CPU %.2f%%\n' "$rtt" "$cpu"
}

for rate in 10 100 0; do
    rate_label="${rate}mbit"
    if [[ $rate == 0 ]]; then
        rate_label=unlimited
    fi
    printf 'Condition: rate=%s, switch=python and bridge\n' "$rate_label"
    printf 'COMMAND: topology/impair_h.sh h1 0 %s\n' "$rate"
    topology/impair_h.sh h1 0 "$rate"
    start_switches
    printf 'COMMAND: ip netns exec h3 iperf3 -s\n'
    ip netns exec h3 iperf3 -s > results/.e2_iperf.log 2>&1 &
    server_pid=$!
    sleep 1
    for run in 1 2 3; do
        printf 'E2 | rate=%s | switch=python | run %d/3\n' "$rate_label" "$run"
        measure python "$rate" "$run"
    done
    stop_server
    stop_switches
    printf 'COMMAND: experiments/bridge_baseline_d.sh start\n'
    experiments/bridge_baseline_d.sh start
    printf 'COMMAND: ip netns exec h3 iperf3 -s\n'
    ip netns exec h3 iperf3 -s > results/.e2_iperf.log 2>&1 &
    server_pid=$!
    sleep 1
    for run in 1 2 3; do
        printf 'E2 | rate=%s | switch=bridge | run %d/3\n' "$rate_label" "$run"
        measure bridge "$rate" "$run"
    done
    stop_server
    printf 'COMMAND: experiments/bridge_baseline_d.sh stop\n'
    experiments/bridge_baseline_d.sh stop
done
print_summary
