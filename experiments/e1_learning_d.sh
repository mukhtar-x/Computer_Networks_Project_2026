#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if [[ ${EUID} -ne 0 ]]; then
    printf 'Run as root.\n' >&2
    exit 1
fi

result=results/e1.csv
stats=results/.e1_sw1.csv
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

printf '==== E1 | MAC learning and flooding ====\n'
printf 'Measures flooded-frame ratio and learning time for 2, 4, and 6 hosts.\n'

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
print("==== E1 result summary ====")
print(f"{'Condition':<25} | {'Metric':<25} | {'Mean':>12} | {'Std dev':>12}")
print(f"{'-' * 25}-+-{'-' * 25}-+-{'-' * 12}-+-{'-' * 12}")
for (condition, metric), values in sorted(groups.items()):
    mean = statistics.mean(values)
    stdev = statistics.stdev(values) if len(values) > 1 else 0
    print(f"{condition:<25} | {metric:<25} | {mean:>12.4f} | {stdev:>12.4f}")
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
    rm -f "$stats" results/.e1_sw2.csv
}
trap cleanup EXIT

topology/setup_h.sh
topology/r1_subif_r.sh
topology/r1_forward_r.sh on >/dev/null
printf 'experiment,condition,run,metric,value\n' > "$result"

start_switches() {
    local stats_file=$1
    printf 'COMMAND: ip netns exec sw1 python3 switch/switch_d.py '
    printf '%s\n' "--config switch/config_sw1_d.json --stats $stats_file"
    ip netns exec sw1 python3 switch/switch_d.py --config switch/config_sw1_d.json --stats "$stats_file" > /dev/null 2>&1 &
    sw1_pid=$!
    printf 'COMMAND: ip netns exec sw2 python3 switch/switch_d.py '
    printf '%s\n' '--config switch/config_sw2_d.json --stats results/.e1_sw2.csv'
    ip netns exec sw2 python3 switch/switch_d.py --config switch/config_sw2_d.json --stats results/.e1_sw2.csv > /dev/null 2>&1 &
    sw2_pid=$!
    sleep 1
}

for active in 2 4 6; do
    printf 'Condition: %d hosts active (3 runs)\n' "$active"
    case "$active" in
        2) hosts=(h1 h3) ;;
        4) hosts=(h1 h3 h5 h2) ;;
        6) hosts=(h1 h2 h3 h4 h5 h6) ;;
    esac
    for run in 1 2 3; do
        printf 'E1 | hosts=%d | run %d/3 | measuring learning and flooding\n' "$active" "$run"
        stop_switches
        for host in "${hosts[@]}"; do
            ip -n "$host" neigh flush dev eth0 >/dev/null 2>&1 || true
        done
        start_switches "$stats"
        for source in "${hosts[@]}"; do
            for destination in "${hosts[@]}"; do
                if [[ $source != "$destination" ]]; then
                    address=$(ip -n "$destination" -4 -o addr show dev eth0 | awk '{split($4,a,"/"); print a[1]}')
                    printf 'COMMAND: ip netns exec %s ping -n -c 1 -W 1 %s\n' "$source" "$address"
                    if ip netns exec "$source" ping -n -c 1 -W 1 "$address" >/dev/null 2>&1; then
                        printf '%s[PASS]%s %s -> %s\n' "$GREEN" "$RESET" "$source" "$destination"
                    else
                        printf '%s[FAIL]%s %s -> %s\n' "$RED" "$RESET" "$source" "$destination"
                    fi
                fi
            done
        done
        sleep 2
        python3 - "$stats" results/.e1_sw2.csv "$result" "$active" "$run" <<'PY'
import csv
import sys

stats_paths = sys.argv[1:3]
result_path, active, run = sys.argv[3:]
all_rows = []
for stats_path in stats_paths:
    with open(stats_path, newline="", encoding="utf-8") as source:
        all_rows.append(list(csv.DictReader(source)))
samples = []
if all_rows and all(all_rows):
    for index in range(min(map(len, all_rows))):
        total = sum(int(rows[index]["total"]) for rows in all_rows)
        flooded = sum(int(rows[index]["flooded"]) for rows in all_rows)
        forwarded = sum(int(rows[index]["forwarded"]) for rows in all_rows)
        samples.append((flooded / total if total else 0, forwarded))
learned = next((index + 1 for index, (_, forwarded) in enumerate(samples) if forwarded), 0)
ratios = [ratio for ratio, _ in samples]
mean_ratio = sum(ratios) / len(ratios) if ratios else 0
print(
    f"E1 | hosts={active} | run {run}/3 | flooded ratio={mean_ratio:.4f} | "
    f"learning={learned}s"
)
with open(result_path, "a", newline="", encoding="utf-8") as output:
    writer = csv.writer(output)
    for second, (ratio, _) in enumerate(samples, 1):
        writer.writerow(("E1", f"hosts={active}_time={second}s", run, "flooded_frame_ratio", f"{ratio:.6f}"))
    writer.writerow(("E1", f"hosts={active}", run, "learning_time_seconds", f"{learned:.3f}"))
PY
    done
done
print_summary
