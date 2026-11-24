# CS3001 Project 30

This project implements a user-space Ethernet learning switch, VLAN access and trunk handling, ARP observation, CRC/parity/checksum test frames, and the requested network experiments. Run network commands as root on Ubuntu.

## Prerequisites

```sh
sudo apt update
sudo apt install -y python3 python3-pip python3-scapy iproute2 ethtool iperf3 tcpdump wireshark traceroute bridge-utils
```

`dumpcap` from Wireshark is used to write the packet captures in pcapng format.

## Build and remove the topology

From `cn-project30/`:

```sh
sudo ./topology/setup_h.sh
sudo ./topology/r1_subif_r.sh
sudo ./topology/teardown_h.sh
```

`setup_h.sh` creates the namespaces and links, assigns addresses and routes, and checks the R1-to-S1 path. It intentionally does not create R1 VLAN sub-interfaces or host default gateways; `r1_subif_r.sh` adds those. `r1_forward_r.sh on|off` controls IPv4 forwarding in R1.

## Start the Python switches

From `cn-project30/`, run each command in a separate terminal:

```sh
sudo ip netns exec sw1 python3 switch/switch_d.py --config switch/config_sw1_d.json
sudo ip netns exec sw2 python3 switch/switch_d.py --config switch/config_sw2_d.json
```

Use `--aging 10` to shorten MAC aging or `--stats results/switch.csv` to write the one-second switch counters. Send `SIGUSR1` to the switch process to print its MAC table.

## Linux bridge baseline

Stop both Python switches before starting the bridges:

```sh
sudo ./experiments/bridge_baseline_d.sh start
sudo ./experiments/bridge_baseline_d.sh stop
```

## Experiments and analysis

Run each experiment from `cn-project30/` as root. The E2 and E3 experiments run iperf3 for 30 seconds per measurement and therefore take several minutes.

```sh
sudo ./experiments/e1_learning_d.sh
sudo ./experiments/e2_bridge_vs_switch_d.sh
sudo ./experiments/e3_routed_h.sh
sudo python3 experiments/e4_errors_h.py
sudo ./experiments/e5_vlan_isolation_r.sh
python3 experiments/analyze_h.py
```

Each experiment writes `results/e1.csv` through `results/e5.csv` with the columns `experiment,condition,run,metric,value`. Analysis is written to `results/summary.csv`.

## Captures and demo

```sh
sudo ./experiments/captures_h.sh
sudo ./demo_r.sh
```

Captures are written to `captures/` as pcapng files. The demo pauses between stages for observation.

## Tests

```sh
PYTHONPATH=. python3 tests/test_codes_h.py
sudo ip netns exec sw1 python3 tests/raw_check_d.py p1 10
```

## Folder structure

```text
captures/       Packet captures
errors/         Error codes, test-frame generator, noisy link, receiver
experiments/    E1-E5 runners, Linux bridge baseline, analysis, captures
results/        Experiment CSV results and summary
screenshots/    Wireshark screenshots
switch/         Python switch, MAC table, ARP log, VLAN handling, configs
tests/          Error-code tests and raw-frame check
topology/       Namespace setup, teardown, link impairment, R1 helpers
```
