import csv
import os
import random
import signal
import statistics
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NAMESPACES = ("e4src", "e4mid", "e4dst")


def command(*args, check=True):
    return subprocess.run(args, cwd=ROOT, check=check)


def add_pair(left_ns, left_if, right_ns, right_if):
    command("ip", "link", "add", left_if, "type", "veth", "peer", "name", right_if)
    command("ip", "link", "set", left_if, "netns", left_ns)
    command("ip", "link", "set", right_if, "netns", right_ns)
    command("ip", "-n", left_ns, "link", "set", left_if, "up")
    command("ip", "-n", right_ns, "link", "set", right_if, "up")


def cleanup():
    for namespace in NAMESPACES:
        command("ip", "netns", "del", namespace, check=False)


def read_count(output, name):
    prefix = f"{name}="
    for line in output.splitlines():
        if line.startswith(prefix):
            return int(line[len(prefix):].split()[0])
    raise RuntimeError(f"Missing {name} count from process output")


def read_optional_count(output, name):
    prefix = f"{name}="
    for line in output.splitlines():
        if line.startswith(prefix):
            try:
                return int(line[len(prefix):].split()[0])
            except ValueError:
                return None
    return None


def stop_process(process, signum, timeout):
    if process.poll() is None:
        try:
            os.killpg(process.pid, signum)
        except ProcessLookupError:
            pass
    try:
        return process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        return process.communicate()


def main():
    if os.geteuid() != 0:
        raise SystemExit("Run as root.")
    if len(sys.argv) > 1:
        raise SystemExit("Usage: python3 experiments/e4_errors_h.py")
    print("==== E4 | Parity, Internet checksum, and CRC-32 ====")
    print("Measures detection and missed frames for 100000 single, double, and burst errors.")
    result_path = ROOT / "results" / "e4.csv"
    result_path.parent.mkdir(parents=True, exist_ok=True)
    rng = random.SystemRandom()
    try:
        cleanup()
        for namespace in NAMESPACES:
            command("ip", "netns", "add", namespace)
        for namespace in NAMESPACES:
            command(
                "ip", "netns", "exec", namespace, "sysctl", "-qw",
                "net.ipv6.conf.all.disable_ipv6=1",
            )
            command(
                "ip", "netns", "exec", namespace, "sysctl", "-qw",
                "net.ipv6.conf.default.disable_ipv6=1",
            )
        add_pair("e4src", "e4s0", "e4mid", "e4m0")
        add_pair("e4mid", "e4m1", "e4dst", "e4d0")
        command("ip", "-n", "e4dst", "link", "set", "e4d0", "address", "02:00:00:00:04:03")
        with result_path.open("w", newline="", encoding="utf-8") as output:
            writer = csv.writer(output)
            writer.writerow(("experiment", "condition", "run", "metric", "value"))
            for mode in ("single", "double", "burst"):
                error_label = "burst 8-32-bit" if mode == "burst" else f"{mode}-bit"
                print(f"Condition: {error_label} errors; 3 runs of 100000 frames")
                for run in range(1, 4):
                    seed = rng.randrange(1, 2**31)
                    print(
                        f"E4 | error={error_label} | run {run}/3 | seed={seed} | "
                        "frames=100000"
                    )
                    receiver = None
                    noisy = None
                    receiver_output = ""
                    receiver_error = ""
                    noisy_output = ""
                    noisy_error = ""
                    sent_frames = 0
                    try:
                        print(
                            "COMMAND: ip netns exec e4dst python3 errors/receiver_h.py "
                            "e4d0 --count 100000"
                        )
                        receiver = subprocess.Popen(
                            [
                                "ip", "netns", "exec", "e4dst", "python3",
                                "errors/receiver_h.py", "e4d0", "--count", "100000",
                            ],
                            cwd=ROOT,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            text=True,
                            start_new_session=True,
                        )
                        print(
                            "COMMAND: ip netns exec e4mid python3 "
                            "errors/noisy_link_h.py \\"
                        )
                        print(f"  e4m0 e4m1 --mode {mode} --seed {seed}")
                        noisy = subprocess.Popen(
                            [
                                "ip", "netns", "exec", "e4mid", "python3",
                                "errors/noisy_link_h.py", "e4m0", "e4m1",
                                "--mode", mode, "--seed", str(seed),
                            ],
                            cwd=ROOT,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            text=True,
                            start_new_session=True,
                        )
                        time.sleep(1)
                        print(
                            "COMMAND: ip netns exec e4src python3 "
                            "errors/generator_h.py \\"
                        )
                        print(
                            f"  e4s0 02:00:00:00:04:03 --count 100000 --seed {seed + run}"
                        )
                        generated = subprocess.run(
                            [
                                "ip", "netns", "exec", "e4src", "python3",
                                "errors/generator_h.py", "e4s0",
                                "02:00:00:00:04:03", "--count", "100000",
                                "--seed", str(seed + run),
                            ],
                            cwd=ROOT,
                            check=True,
                            capture_output=True,
                            text=True,
                        )
                        sent_frames = read_count(generated.stdout, "sent_frames")
                        receiver_output, receiver_error = receiver.communicate(timeout=300)
                        if receiver.returncode != 0:
                            raise RuntimeError(receiver_error.strip() or "Receiver failed")
                    finally:
                        if receiver is not None:
                            receiver_output, receiver_error = stop_process(
                                receiver,
                                signal.SIGINT,
                                10,
                            )
                        if noisy is not None:
                            noisy_output, noisy_error = stop_process(
                                noisy,
                                signal.SIGTERM,
                                10,
                            )
                    forwarded_frames = read_optional_count(noisy_output, "forwarded_frames")
                    if forwarded_frames is None:
                        print(
                            "WARNING: noisy link did not report forwarded_frames; "
                            "continuing with receiver counts"
                        )
                        if noisy_error.strip():
                            print(noisy_error.strip())
                    received_frames = read_count(receiver_output, "received")
                    print(
                        f"E4 | error={error_label} | run {run}/3 | sent={sent_frames} "
                        f"forwarded={forwarded_frames if forwarded_frames is not None else 'unknown'} "
                        f"received={received_frames}"
                    )
                    for line in receiver_output.splitlines():
                        if line.startswith("WARNING:"):
                            print(line)
                    detected = {}
                    for line in receiver_output.splitlines():
                        if ":" in line and "detected=" in line:
                            name, values = line.split(":", 1)
                            detected[name] = dict(
                                part.split("=", 1) for part in values.strip().split()
                            )
                    for code in ("parity", "checksum", "crc32"):
                        if code not in detected:
                            raise RuntimeError(f"Missing {code} results from receiver")
                        code_label = "Internet checksum" if code == "checksum" else code
                        writer.writerow(("E4", mode, run, f"{code}_detection_rate_pct", detected[code]["detection_rate_pct"]))
                        writer.writerow(("E4", mode, run, f"{code}_missed_frames", detected[code]["missed"]))
                        print(
                            f"E4 | error={error_label} | run {run}/3 | {code_label} detection="
                            f"{detected[code]['detection_rate_pct']}% | "
                            f"missed={detected[code]['missed']}"
                        )
                    output.flush()
    finally:
        cleanup()
    with result_path.open(newline="", encoding="utf-8") as source:
        rows = list(csv.DictReader(source))
    rates = {}
    missed = {}
    for row in rows:
        try:
            value = float(row["value"])
        except ValueError:
            continue
        key = (row["condition"], row["metric"].split("_", 1)[0])
        target = rates if row["metric"].endswith("detection_rate_pct") else missed
        target.setdefault(key, []).append(value)
    print("==== E4 detection-rate summary ====")
    print(f"{'Error type':<16} | {'Code':<17} | {'Mean %':>10} | {'Std dev':>10} | {'Range %':>21}")
    print(f"{'-' * 16}-+-{'-' * 17}-+-{'-' * 10}-+-{'-' * 10}-+-{'-' * 21}")
    for (mode, code), values in sorted(rates.items()):
        mean = sum(values) / len(values)
        stdev = statistics.stdev(values) if len(values) > 1 else 0
        error_label = "burst 8-32-bit" if mode == "burst" else f"{mode}-bit"
        code_label = "Internet checksum" if code == "checksum" else code
        print(
            f"{error_label:<16} | {code_label:<17} | {mean:>10.4f} | {stdev:>10.4f} | "
            f"{min(values):.4f}-{max(values):.4f}"
        )
    if not rates:
        print("No frames received; detection rates unavailable.")
    print("==== E4 missed-frame summary ====")
    print(f"{'Error type':<16} | {'Code':<17} | {'Mean missed':>12} | {'Std dev':>10}")
    print(f"{'-' * 16}-+-{'-' * 17}-+-{'-' * 12}-+-{'-' * 10}")
    for (mode, code), values in sorted(missed.items()):
        mean = sum(values) / len(values)
        stdev = statistics.stdev(values) if len(values) > 1 else 0
        error_label = "burst 8-32-bit" if mode == "burst" else f"{mode}-bit"
        code_label = "Internet checksum" if code == "checksum" else code
        print(f"{error_label:<16} | {code_label:<17} | {mean:>12.2f} | {stdev:>10.2f}")
    print(f"CSV: {result_path}")


if __name__ == "__main__":
    main()
