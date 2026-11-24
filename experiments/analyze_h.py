import csv
import statistics
import sys
from pathlib import Path


RESULTS = Path(__file__).resolve().parents[1] / "results"
EXPERIMENTS = ("e1", "e2", "e3", "e4", "e5")
RUNNERS = {
    "e1": "sudo ./experiments/e1_learning_d.sh",
    "e2": "sudo ./experiments/e2_bridge_vs_switch_d.sh",
    "e3": "sudo ./experiments/e3_routed_h.sh",
    "e4": "sudo python3 experiments/e4_errors_h.py",
    "e5": "sudo ./experiments/e5_vlan_isolation_r.sh",
}


def read_rows():
    rows = []
    for name in EXPERIMENTS:
        path = RESULTS / f"{name}.csv"
        if not path.exists():
            print(f"Missing {name.upper()} results: {path}")
            print(f"Run this experiment first: {RUNNERS[name]}")
            raise SystemExit(1)
        with path.open(newline="", encoding="utf-8") as source:
            for row in csv.DictReader(source):
                row["experiment"] = row["experiment"] or name.upper()
                rows.append(row)
    return rows


def summarize(rows):
    grouped = {}
    for row in rows:
        try:
            value = float(row["value"])
        except ValueError:
            continue
        key = (row["experiment"], row["condition"], row["metric"])
        grouped.setdefault(key, []).append(value)
    summary = []
    for (experiment, condition, metric), values in sorted(grouped.items()):
        mean = statistics.mean(values)
        stdev = statistics.stdev(values) if len(values) > 1 else 0
        minimum = min(values) if experiment == "E4" else ""
        maximum = max(values) if experiment == "E4" else ""
        outcome = ""
        if experiment == "E5" and metric == "ping_pass":
            expected = 0 if condition == "cross_vlan_forward_off" else 1
            outcome = "PASS" if all(value == expected for value in values) else "FAIL"
        summary.append(
            (experiment, condition, metric, mean, stdev, minimum, maximum, outcome, len(values))
        )
    return summary


def print_experiment(experiment, rows):
    selected = [row for row in rows if row[0] == experiment]
    green = "\033[32m" if sys.stdout.isatty() else ""
    red = "\033[31m" if sys.stdout.isatty() else ""
    reset = "\033[0m" if sys.stdout.isatty() else ""
    print(f"\n==== {experiment} results ====")
    headers = ["Condition", "Metric", "Mean", "Std dev"]
    if experiment == "E4":
        headers.append("Range")
    if experiment == "E5":
        headers.append("Outcome")
    widths = [24, 20, 10, 10]
    if experiment == "E4":
        widths.append(20)
    if experiment == "E5":
        widths.append(10)
    print(" | ".join(f"{head:<{width}}" for head, width in zip(headers, widths)))
    print("-+-".join("-" * width for width in widths))
    for row in selected:
        _, condition, metric, mean, stdev, minimum, maximum, outcome, _ = row
        display_metric = metric.replace("_detection_rate_pct", " detect %")
        display_metric = display_metric.replace("_missed_frames", " missed")
        cells = [condition, display_metric, f"{mean:.4f}", f"{stdev:.4f}"]
        if experiment == "E4":
            cells.append(f"{minimum:.4f}-{maximum:.4f}")
        if experiment == "E5":
            cells.append(f"[{outcome}]" if metric == "ping_pass" else "")
        formatted = []
        for index, (cell, width) in enumerate(zip(cells, widths)):
            color = ""
            if experiment == "E5" and index == len(cells) - 1:
                color = green if outcome == "PASS" else red
                if not outcome:
                    color = ""
            formatted.append(f"{color}{cell}{reset}{' ' * max(0, width - len(cell))}")
        print(" | ".join(formatted))


def main():
    rows = read_rows()
    summary = summarize(rows)
    for experiment in EXPERIMENTS:
        print_experiment(experiment.upper(), summary)
    print("\n==== One-screen summary ====")
    print(f"{'Experiment':<12} | {'Groups':>6} | {'Metrics':>7} | {'Values':>6}")
    print(f"{'-' * 12}-+-{'-' * 6}-+-{'-' * 7}-+-{'-' * 6}")
    for experiment in EXPERIMENTS:
        selected = [row for row in summary if row[0] == experiment.upper()]
        groups = len({row[1] for row in selected})
        metrics = len({row[2] for row in selected})
        runs = sum(row[8] for row in selected)
        print(f"{experiment.upper():<12} | {groups:>6} | {metrics:>7} | {runs:>6}")
    with (RESULTS / "summary.csv").open("w", newline="", encoding="utf-8") as output:
        writer = csv.writer(output)
        writer.writerow(
            (
                "experiment",
                "condition",
                "metric",
                "mean",
                "standard_deviation",
                "minimum",
                "maximum",
                "outcome",
            )
        )
        for experiment, condition, metric, mean, stdev, minimum, maximum, outcome, _ in summary:
            writer.writerow(
                (
                    experiment,
                    condition,
                    metric,
                    f"{mean:.6f}",
                    f"{stdev:.6f}",
                    minimum,
                    maximum,
                    outcome.lower() if outcome else "",
                )
            )
    print(f"\nSummary CSV: {RESULTS / 'summary.csv'}")


if __name__ == "__main__":
    main()
