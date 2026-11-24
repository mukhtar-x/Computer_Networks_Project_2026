# CS3001 Project 30 — Ethernet Switching, VLANs, and Error Detection

This project builds an isolated Linux network to study Ethernet learning switches, VLAN access and trunk links, routing, link impairment, packet captures, and simple error-detection codes. It includes a user-space Python switch, a Linux bridge baseline, five repeatable experiments (E1–E5), unit and raw-frame tests, saved CSV results, pcapng captures, and an interactive demonstration.

The lab uses Linux network namespaces, virtual Ethernet pairs, `AF_PACKET` raw sockets, and root privileges. Run it on a Linux host (the scripts and package commands target Ubuntu); it is not intended to configure a physical network.

## Team ownership

Member branches contain the shared files from `main` plus the member-owned files listed below. The ownership split is based on the filename suffix.

| Member | Branch | Work |
|---|---|---|
| Abdullah | `abdullah-topology-errors` | Topology creation, teardown, link impairment, error-code implementation and tests, noisy-link frame corruption and receiver, E3/E4 experiment runners, result analysis, and capture automation. See [topology/](./topology/), [errors/](./errors/), [tests/test_codes_h.py](./tests/test_codes_h.py), and the corresponding `_h` files in [experiments/](./experiments/). |
| Mashhood | `mashhood-switch-learning` | Ethernet learning-switch core, VLAN-aware MAC table, ARP observation, switch configurations, Linux bridge baseline, E1 learning/flooding measurements, E2 switch-versus-bridge comparison, and raw-frame inspection. See [switch/](./switch/), [tests/raw_check_d.py](./tests/raw_check_d.py), and the corresponding `_d` files in [experiments/](./experiments/). |
| Mukhtar | `mukhtar-vlan-demo` | VLAN tag handling, router-on-a-stick subinterfaces and forwarding controls, E5 VLAN-isolation experiment, and the nine-step live demo. See [switch/vlan_r.py](./switch/vlan_r.py), the `_r` files in [topology/](./topology/), [experiments/e5_vlan_isolation_r.sh](./experiments/e5_vlan_isolation_r.sh), and [demo_r.sh](./demo_r.sh). |
| Shared (`main`) | `main` | Project documentation, dependency installer, committed experiment CSVs, and pcapng captures. |

## Network design

`topology/setup_h.sh` creates 11 namespaces and their virtual Ethernet links:

```text
 h1 (VLAN 10) ─┐                         ┌─ h4 (VLAN 20)
 h2 (VLAN 20) ─┼─ SW1 ═══ trunk ═══ SW2 ┼─ h5 (VLAN 10)
 h3 (VLAN 10) ─┘    │                    └─ h6 (VLAN 20)
                    │ trunk
                    R1 ── routed link ── R2 ── S1
```

The hosts connect to access ports on SW1 and SW2. SW1–SW2 and SW1–R1 are 802.1Q trunks carrying VLANs 10 and 20. R1 provides a VLAN gateway when its subinterfaces are configured; R1 and R2 connect the host VLANs to the S1 server network.

| Component | Interface / port | VLAN / network | Address |
|---|---|---|---|
| SW1 | `p1`—h1, `p3`—h3 | Access VLAN 10 | h1 `192.168.10.11/24`; h3 `192.168.10.12/24` |
| SW1 | `p2`—h2 | Access VLAN 20 | h2 `192.168.20.11/24` |
| SW1 | `p4`—SW2, `p5`—R1 | Trunks for VLANs 10, 20 | — |
| SW2 | `p1`—h4, `p3`—h6 | Access VLAN 20 | h4 `192.168.20.12/24`; h6 `192.168.20.13/24` |
| SW2 | `p2`—h5 | Access VLAN 10 | h5 `192.168.10.13/24` |
| R1 | `r1-sw.10`, `r1-sw.20` | VLAN 10, VLAN 20 gateways | `192.168.10.1/24`, `192.168.20.1/24` |
| R1–R2 | `r1-r2`, `r2-r1` | `10.0.12.0/30` | R1 `10.0.12.1`; R2 `10.0.12.2` |
| R2–S1 | `r2-s1`, `eth0` | `10.0.30.0/24` | R2 `10.0.30.1`; S1 `10.0.30.10` |

The namespaces are `h1`–`h6`, `sw1`, `sw2`, `r1`, `r2`, and `s1`. The topology setup disables IPv6 in the lab namespaces, configures routes and forwarding for its baseline connectivity checks, disables common NIC offloads where supported, and checks links, pings, and traceroute.

## Requirements and setup

Use Ubuntu or a compatible Linux system with permission to create network namespaces and raw packet sockets. Install the packages from the repository root:

```sh
sudo bash requirements.sh
```

This installs Python 3, Scapy, `iproute2`, `ethtool`, `iperf3`, `tcpdump`, Wireshark (`dumpcap`/`capinfos`), `traceroute`, and `bridge-utils`.

Build the lab and configure the router-on-a-stick interfaces:

```sh
sudo ./topology/setup_h.sh
sudo ./topology/r1_subif_r.sh
sudo ./topology/r1_forward_r.sh on
```

`setup_h.sh` first removes existing namespaces with these project names, then recreates and verifies them. Use this lab on a system where those namespace names are reserved for this project. The setup script creates the base links, addressing, and routes; `r1_subif_r.sh` adds the R1 VLAN interfaces and host default gateways.

To remove the lab after use:

```sh
sudo ./topology/teardown_h.sh
```

This deletes the project namespaces and their virtual links. Stop foreground switch processes with `Ctrl-C` before teardown when running them manually.

## User-space learning switch

Start each switch in a separate terminal from the repository root:

```sh
sudo ip netns exec sw1 python3 switch/switch_d.py --config switch/config_sw1_d.json
sudo ip netns exec sw2 python3 switch/switch_d.py --config switch/config_sw2_d.json
```

The switch opens raw packet sockets on each configured port, learns source MAC addresses per VLAN, forwards known unicast traffic, and floods unknown unicast and multicast/broadcast frames only to eligible ports in that VLAN. Access ports accept and emit untagged traffic for their configured VLAN. Trunks accept and emit 802.1Q-tagged traffic only for their configured VLAN list.

The MAC table defaults to a 300-second aging interval. Useful options:

```sh
sudo ip netns exec sw1 python3 switch/switch_d.py \
  --config switch/config_sw1_d.json --aging 10 --verbose \
  --stats results/switch.csv
```

`--aging` sets a positive aging interval; `--verbose` prints learning, aging, forwarding, flooding, and drop events. `--stats` writes one-second counters (`time,flooded,forwarded,total`). Send `SIGUSR1` to a switch process to print its current VLAN/MAC/port table. The configs in [switch/config_sw1_d.json](./switch/config_sw1_d.json) and [switch/config_sw2_d.json](./switch/config_sw2_d.json) define the port roles and VLAN memberships.

The switch also observes ARP sender IP/MAC addresses per VLAN and can use a learned ARP target port when forwarding ARP replies. The standalone VLAN transformations are in [switch/vlan_r.py](./switch/vlan_r.py); the VLAN-aware MAC table and ARP observer are in [switch/mac_table_d.py](./switch/mac_table_d.py) and [switch/arp_log_d.py](./switch/arp_log_d.py).

## Experiments

Run the experiment scripts from the repository root. They require root because they create namespaces, configure links, or use raw sockets. E2 and E3 run multiple 30-second throughput tests and take several minutes.

| Experiment | Purpose and conditions | Recorded metrics |
|---|---|---|
| E1 — [experiments/e1_learning_d.sh](./experiments/e1_learning_d.sh) | Observe learning and flooding with 2, 4, and 6 active hosts; 3 runs per condition. | Flooded-frame ratio over time and learning time. |
| E2 — [experiments/e2_bridge_vs_switch_d.sh](./experiments/e2_bridge_vs_switch_d.sh) | Compare the Python switch with the Linux bridge at 10 Mbit/s, 100 Mbit/s, and unlimited rate; 3 runs per mode/rate. | TCP throughput, ping RTT, and CPU utilization. |
| E3 — [experiments/e3_routed_h.sh](./experiments/e3_routed_h.sh) | Add 20 ms, 100 ms, and 200 ms delay to the R1–R2 link; 3 runs per delay. | Ping RTT, TCP throughput, and traceroute hop count from H1 to S1. |
| E4 — [experiments/e4_errors_h.py](./experiments/e4_errors_h.py) | Send 100,000 custom Ethernet frames per run through a noisy link with single-bit, double-bit, or 8–32-bit burst corruption; 3 runs per error type. | Detection rates and missed-frame counts for parity, Internet checksum, and CRC-32. |
| E5 — [experiments/e5_vlan_isolation_r.sh](./experiments/e5_vlan_isolation_r.sh) | Test H1-to-H5 reachability across a VLAN trunk, then H1-to-H2 cross-VLAN reachability with R1 forwarding off and on; 3 runs per case. | Ping result and captured frames on the VLAN 20 access link to check for leakage. |

Run them individually:

```sh
sudo ./experiments/e1_learning_d.sh
sudo ./experiments/e2_bridge_vs_switch_d.sh
sudo ./experiments/e3_routed_h.sh
sudo python3 experiments/e4_errors_h.py
sudo ./experiments/e5_vlan_isolation_r.sh
```

E4 creates and removes its own temporary namespaces (`e4src`, `e4mid`, and `e4dst`). The other experiments rebuild the main project topology as needed. When finished, remove any remaining project namespaces with `sudo ./topology/teardown_h.sh`.

Each runner writes `results/e1.csv` through `results/e5.csv` using the columns `experiment,condition,run,metric,value`. These tracked CSVs are example/result snapshots and are overwritten when their corresponding experiment is run. Temporary experiment logs and captures use hidden files under `results/` and are excluded by [.gitignore](./.gitignore).

After all five result CSVs exist, calculate grouped means and standard deviations:

```sh
python3 experiments/analyze_h.py
```

The analyzer writes `results/summary.csv`. It includes E4 minimum/maximum detection rates and marks the expected E5 `ping_pass` outcomes as `pass` or `fail`. It exits with an explanation if an experiment result file is missing.

## Error-detection frame format

E4 uses a custom Ethernet EtherType `0x88B5`. The protected data contains a 4-byte sequence number and 60 pseudorandom bytes. The generator appends one even-parity byte, a 16-bit Internet checksum, and a 32-bit CRC-32. The noisy-link process forwards only these test frames and flips bits in the protected data; the receiver independently checks each code and reports detection and missed-frame counts. Seeds are recorded by the runner to make each generated run reproducible.

The checksum and CRC/parity implementations are in [errors/codes_h.py](./errors/codes_h.py); frame generation, corruption, and validation are in [errors/generator_h.py](./errors/generator_h.py), [errors/noisy_link_h.py](./errors/noisy_link_h.py), and [errors/receiver_h.py](./errors/receiver_h.py).

## Captures

Generate the four pcapng examples with:

```sh
sudo ./experiments/captures_h.sh
```

The script requires Wireshark's `dumpcap` and captures ARP, tagged trunk traffic, custom `0x88B5` error-test frames, and ICMP traffic used by traceroute. It writes [captures/arp.pcapng](./captures/arp.pcapng), [captures/trunk.pcapng](./captures/trunk.pcapng), [captures/crc32.pcapng](./captures/crc32.pcapng), and [captures/traceroute.pcapng](./captures/traceroute.pcapng). Capture files are replaced when regenerated. Open them in Wireshark or inspect them with `tcpdump`/`capinfos`.

## Interactive demonstration

Run the nine-stage demonstration as root:

```sh
sudo ./demo_r.sh
```

It pauses between stages and demonstrates topology startup, access-VLAN connectivity, trunk tagging versus access-port untagging, ARP/MAC learning, VLAN-scoped unknown-destination flooding, MAC aging, the routed H1-to-S1 path, E4 error detection, and TCP throughput through both the Python switch and Linux bridge. It prints a pass/fail summary and removes the demo namespaces and processes when it exits.

## Tests and diagnostics

Run the checksum/parity/CRC unit tests without creating a network lab:

```sh
PYTHONPATH=. python3 tests/test_codes_h.py
```

The tests compare CRC-32 with Python's `zlib`, verify Internet-checksum packets, and confirm parity changes after a single-bit flip.

`tests/raw_check_d.py` is a raw-frame diagnostic. With the topology running, start it on a switch port and generate traffic on that port:

```sh
sudo ip netns exec sw1 python3 tests/raw_check_d.py p1 10
```

It prints the destination MAC, source MAC, and EtherType for each of the requested number of received frames.

## Linux bridge baseline

E2 uses this helper to replace the user-space switches with VLAN-aware Linux bridges. It can also be run manually after stopping both Python switch processes:

```sh
sudo ./experiments/bridge_baseline_d.sh start
sudo ./experiments/bridge_baseline_d.sh stop
```

The `start` action creates `br0` in `sw1` and `sw2`, enables VLAN filtering, and applies the same access/trunk membership. `stop` removes those bridges.

## Repository map

| Path | Contents |
|---|---|
| [topology/](./topology/) | Namespace/link setup and teardown, link delay/rate impairment, R1 forwarding and VLAN subinterface helpers. |
| [switch/](./switch/) | User-space Ethernet switch, VLAN ingress/egress, MAC learning/aging, ARP observation, and per-switch configs. |
| [errors/](./errors/) | Parity, Internet checksum, CRC-32, custom-frame generator, noisy link, and receiver. |
| [experiments/](./experiments/) | E1–E5 runners, Linux bridge baseline, result analysis, and pcapng capture generation. |
| [tests/](./tests/) | Error-code unit tests and raw Ethernet frame inspection. |
| [results/](./results/) | E1–E5 result CSVs and generated summary CSV. |
| [captures/](./captures/) | Saved ARP, VLAN trunk, CRC test-frame, and traceroute pcapng examples. |
| [demo_r.sh](./demo_r.sh) | Interactive nine-stage live demonstration. |
| [requirements.sh](./requirements.sh) | Ubuntu package installation helper. |
| [.gitignore](./.gitignore) | Excludes Python caches, hidden temporary results, logs, editor state, and virtual environments. |
