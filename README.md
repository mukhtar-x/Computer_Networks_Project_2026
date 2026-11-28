# CS3001 Project 30: Software Ethernet Switch

This repository implements and evaluates a user-space Ethernet learning switch, VLAN access and trunk behavior, router-on-a-stick forwarding, routed links, error-detection codes, and packet captures. Experiments E1–E5 have CSV results in `results/`; pcapng examples are in `captures/`. The isolated lab uses Linux network namespaces, virtual Ethernet pairs, and raw packet sockets.

## Team file ownership

Ownership is indicated by the filename suffix used in the project files.

| Suffix | Member |
|---|---|
| `_h` | Abdullah (24K-0532) |
| `_d` | Mashhood Riaz (24K-0530) |
| `_r` | Mukhtar (24K-0511) |

## Repository layout

| Path | Contents |
|---|---|
| `topology/` | Namespace and link setup/teardown, router subinterfaces and forwarding, link impairment |
| `switch/` | Python switch, VLAN handling, MAC learning, ARP logging, switch configurations |
| `errors/` | Parity, Internet checksum, CRC-32, frame generator, noisy link, receiver |
| `experiments/` | E1–E5 runners, Linux bridge baseline, analyzer, capture script |
| `tests/` | Error-code unit tests and raw-frame diagnostic |
| `results/` | E1–E5 CSV results and analyzer summary |
| `captures/` | ARP, trunk, CRC-32 test-frame, and traceroute pcapng files |
| `annotated_screenshots/` | Annotated Wireshark screenshots for ARP, CRC-32, traceroute, and trunk traffic |
| `CS3001_Project30-Proposal_0530,0511,0532.pdf` | Project proposal with team roll numbers and responsibilities |
| `demo_r.sh`, `requirements.sh` | Interactive demo and Ubuntu package installer |

See [ARCHITECTURE.md](./ARCHITECTURE.md) for topology and addressing details, [REPORT.md](./REPORT.md) for the results, and [AI_USE_DISCLOSURE.md](./AI_USE_DISCLOSURE.md) for the AI-use and student-verification statements.

## Prerequisites

Use Ubuntu or a compatible Linux system with `sudo` access. The lab requires Python 3, Scapy, `iproute2`, `iperf3`, `tcpdump`, `ethtool`, and `traceroute`. Wireshark is needed to view pcapng files; the capture-generation script also uses `dumpcap` and `capinfos`.

Install the repository's listed packages from the root:

```sh
sudo bash requirements.sh
```

The installer also installs `python3-pip` and `bridge-utils`.

## Run order

Run commands from the repository root. Times are approximate and machine-dependent; E4 runtime is especially dependent on the host.

| Step | Command | Approximate duration |
|---|---|---|
| Create the lab topology | `sudo ./topology/setup_h.sh` | Under a minute on a responsive host |
| Live demo | `sudo bash demo_r.sh` | About 5–10 minutes, depending on pauses between its stages |
| E1: learning/flooding | `sudo ./experiments/e1_learning_d.sh` | About 2–3 minutes |
| E2: switch/bridge throughput | `sudo ./experiments/e2_bridge_vs_switch_d.sh` | At least 9 minutes for the timed throughput tests, plus setup |
| E3: routed-link delay | `sudo ./experiments/e3_routed_h.sh` | At least 4.5 minutes for the timed throughput tests, plus setup |
| E4: error detection | `sudo python3 experiments/e4_errors_h.py` | Generator pacing alone is about 23 seconds total; overall time [TO CONFIRM] |
| E5: VLAN isolation | `sudo ./experiments/e5_vlan_isolation_r.sh` | About 1–2 minutes |
| Summarize CSV results | `python3 experiments/analyze_h.py` | Usually under a minute |
| Generate captures | `sudo ./experiments/captures_h.sh` | Usually under a minute |
| Run unit tests | `PYTHONPATH=. python3 tests/test_codes_h.py` | Usually under a minute |

The approximate E2 and E3 lower-bound estimates follow the script's thirty-second `iperf3` tests: E2 has three rates, two forwarding implementations, and three runs; E3 has three delay settings and three runs. E1–E5 runners recreate the topology they need; E4 creates its own temporary namespaces. The standalone topology setup is useful for manual work, but experiments do not require it to remain running. The live demo also creates and cleans up its own lab.

The experiment CSVs are rewritten by their runners. Run E1 through E5 before the analyzer; it reads `results/e1.csv` through `results/e5.csv` and writes `results/summary.csv`.

## Captures

The saved examples are `captures/arp.pcapng`, `captures/trunk.pcapng`, `captures/crc32.pcapng`, and `captures/traceroute.pcapng`. Open them in Wireshark, or inspect a capture with `tcpdump -nn -r captures/arp.pcapng`. To regenerate the set, run the capture script above.

### Annotated Wireshark screenshots

These annotated views correspond to the saved pcapng examples:

| ARP request/reply | CRC-32 test frames |
|---|---|
| ![Annotated ARP request and unicast reply](annotated_screenshots/wireshark_arp.png) | ![Annotated custom CRC-32 test frames](annotated_screenshots/wireshark_crc32.png) |

| Routed traceroute | VLAN trunk tag |
|---|---|
| ![Annotated traceroute hops](annotated_screenshots/wireshark_traceroute.png) | ![Annotated 802.1Q VLAN trunk traffic](annotated_screenshots/wireshark_trunk.png) |

If `dumpcap` cannot write under `captures/`, capture with `tcpdump` instead. For example, the demo's trunk capture uses this repository-verified command form:

```sh
sudo ip netns exec sw1 tcpdump -Q out -enn -i p4 -c 1 -w /tmp/cs3001-trunk.pcap vlan
```

## Troubleshooting

- **Root privileges:** topology, demo, experiment, switch, and packet-capture commands need root; run them with `sudo`.
- **Stale project namespaces:** remove them with `sudo bash topology/teardown_h.sh`, then retry the setup or experiment.
- **Leftover processes:** check for old `switch_d.py`, `tcpdump`, or `iperf3` processes with `ps`; stop only the identified process IDs with `kill PID`. The experiments rebuild the topology themselves, so a manually running lab or old switch can conflict.
- **Capture permissions:** `dumpcap` must be allowed to write into `captures/`. Use `tcpdump` for a capture when that permission is unavailable, or run the capture command with `sudo`.
- **Unexpected repeat-run state:** the topology setup starts by tearing down namespaces with the project's names. Do not use those namespace names for unrelated work.

## Tests

`tests/test_codes_h.py` validates CRC-32 against Python's `zlib`, checks Internet-checksum verification, and checks single-bit parity detection. `tests/raw_check_d.py` is a separate raw-frame diagnostic and expects a running topology.

## Course deliverables

The submitted proposal is [CS3001_Project30-Proposal_0530,0511,0532.pdf](./CS3001_Project30-Proposal_0530,0511,0532.pdf). The five-page report is available as [REPORT.md](./REPORT.md) and [REPORT.pdf](./REPORT.pdf). Proposal-based member contributions, AI use, and student verification are recorded in [AI_USE_DISCLOSURE.md](./AI_USE_DISCLOSURE.md).
