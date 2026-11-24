import argparse
import csv
import json
import select
import signal
import socket
import struct
import time
from pathlib import Path

from arp_log_d import ArpLog
from mac_table_d import MacTable
from vlan_r import egress, ingress


PACKET_OUTGOING = getattr(socket, "PACKET_OUTGOING", 4)
SOL_PACKET = 263
PACKET_ADD_MEMBERSHIP = 1
PACKET_MR_PROMISC = 1


def age_entries(table, aging, verbose, now=None):
    now = time.time() if now is None else now
    expired = [
        (vlan, mac, port)
        for (vlan, mac), (port, seen) in table.entries.items()
        if now - seen >= aging
    ]
    table.expire(now)
    if verbose:
        for vlan, mac, port in expired:
            print(f"AGED vlan{vlan} {mac} ({port}) after {aging:g}s", flush=True)


def print_table(table, aging, verbose):
    now = time.time()
    age_entries(table, aging, verbose, now)
    rows = sorted(
        (vlan, mac, port, now - seen)
        for (vlan, mac), (port, seen) in table.entries.items()
    )
    print(f"{'VLAN':<6} {'MAC':<17} {'PORT':<6} {'AGE(s)':>8}", flush=True)
    for vlan, mac, port, age in rows:
        print(f"{vlan:<6} {mac:<17} {port:<6} {age:>8.3f}", flush=True)


def frame_kind(frame):
    if int.from_bytes(frame[12:14], "big") != 0x0806 or len(frame) < 42:
        return "frame"
    operation = int.from_bytes(frame[20:22], "big")
    return {1: "ARP req", 2: "ARP reply"}.get(operation, "ARP")


def port_label(ports, port, vlan):
    cfg = ports[port]
    if cfg["role"] == "trunk":
        return f"{port}(tag{vlan})"
    return port


def describe_outputs(ports, output_ports, vlan):
    return " ".join(port_label(ports, port, vlan) for port in output_ports)


def print_startup(switch_name, ports, aging):
    print(f"==== {switch_name} learning switch ====", flush=True)
    print(f"Aging time: {aging:g}s", flush=True)
    for port, config in ports.items():
        if config["role"] == "access":
            role = f"access VLAN{config['vlan']}"
        else:
            role = "trunk VLANs " + ",".join(str(vlan) for vlan in config["vlans"])
        print(f"{switch_name} {port}: {role}", flush=True)


def run():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--aging", type=float)
    parser.add_argument("--stats")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    with open(args.config, encoding="utf-8") as config_file:
        config = json.load(config_file)
    ports = config["ports"]
    switch_name = config.get("name", "switch")
    aging = config.get("aging", 300) if args.aging is None else args.aging
    if aging <= 0:
        parser.error("--aging must be positive")
    table = MacTable(aging)
    arp = ArpLog()
    sockets = {}
    for port in ports:
        sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3))
        sock.bind((port, 0))
        membership = struct.pack("IHH8s", socket.if_nametoindex(port), PACKET_MR_PROMISC, 0, bytes(8))
        sock.setsockopt(SOL_PACKET, PACKET_ADD_MEMBERSHIP, membership)
        sock.setsockopt(263, 8, 1)
        sockets[sock] = port
    print_startup(switch_name, ports, aging)
    signal.signal(
        signal.SIGUSR1,
        lambda _signum, _frame: print_table(table, aging, args.verbose),
    )
    stats_writer = None
    stats_file = None
    if args.stats:
        stats_path = Path(args.stats)
        stats_path.parent.mkdir(parents=True, exist_ok=True)
        stats_file = stats_path.open("w", newline="", encoding="utf-8")
        stats_writer = csv.writer(stats_file)
        stats_writer.writerow(("time", "flooded", "forwarded", "total"))
        stats_file.flush()
    counts = {"flooded": 0, "forwarded": 0, "total": 0}
    next_stats = time.monotonic() + 1
    try:
        while True:
            ready, _, _ = select.select(sockets, [], [], 0.2)
            for sock in ready:
                frame, ancillary, _, address = sock.recvmsg(65535, 1024)
                in_port = sockets[sock]
                if address[2] == PACKET_OUTGOING or len(frame) < 14:
                    continue
                for level, message_type, data in ancillary:
                    if level == 263 and message_type == 8 and len(data) >= 20:
                        status, _, _, _, _, vlan_tci, vlan_tpid = struct.unpack("IIIHHHH", data[:20])
                        if status & 0x10 and int.from_bytes(frame[12:14], "big") not in (0x8100, 0x88A8):
                            tpid = vlan_tpid if status & 0x40 else 0x8100
                            frame = frame[:12] + struct.pack("!HH", tpid, vlan_tci) + frame[12:]
                        break
                result = ingress(ports[in_port], frame)
                if result is None:
                    if args.verbose:
                        print(f"{switch_name} | in {in_port} | DROP (invalid VLAN/frame)", flush=True)
                    continue
                vlan, frame = result
                counts["total"] += 1
                dst = frame[:6]
                src = frame[6:12]
                age_entries(table, aging, args.verbose)
                is_new = (vlan, src.hex(":")) not in table.entries
                table.learn(vlan, src.hex(":"), in_port)
                ether_type = int.from_bytes(frame[12:14], "big")
                arp_port = arp.observe(vlan, in_port, frame) if ether_type == 0x0806 else None
                target_port = arp_port if arp_port is not None else table.lookup(vlan, dst.hex(":"))
                if args.verbose and is_new:
                    print(f"LEARN vlan{vlan} {src.hex(':')} on {in_port}", flush=True)
                kind = frame_kind(frame)
                prefix = (
                    f"{switch_name} | in {in_port} vlan{vlan} | "
                    f"{src.hex(':')}->{dst.hex(':')} | {kind}| "
                )
                if dst[0] & 1 or target_port is None:
                    counts["flooded"] += 1
                    output_ports = []
                    for out_port, out_sock in ((p, s) for s, p in sockets.items()):
                        if out_port == in_port:
                            continue
                        out_frame = egress(ports[out_port], vlan, frame)
                        if out_frame is not None:
                            out_sock.send(out_frame)
                            output_ports.append(out_port)
                    if args.verbose:
                        outputs = describe_outputs(ports, output_ports, vlan)
                        print(f"{prefix}FLOOD {outputs or '(none)'}", flush=True)
                elif target_port != in_port:
                    out_frame = egress(ports[target_port], vlan, frame)
                    if out_frame is not None:
                        next(s for s, p in sockets.items() if p == target_port).send(out_frame)
                        counts["forwarded"] += 1
                        if args.verbose:
                            output = port_label(ports, target_port, vlan)
                            print(f"{prefix}FORWARD -> {output}", flush=True)
                    elif args.verbose:
                        print(f"{prefix}DROP (VLAN not allowed)", flush=True)
                elif args.verbose:
                    print(f"{prefix}DROP (destination on input port)", flush=True)
            now = time.monotonic()
            if stats_writer and now >= next_stats:
                stats_writer.writerow((time.time(), counts["flooded"], counts["forwarded"], counts["total"]))
                stats_file.flush()
                next_stats = now + 1
    except KeyboardInterrupt:
        pass
    finally:
        for sock in sockets:
            sock.close()
        if stats_file:
            stats_file.close()


if __name__ == "__main__":
    run()
