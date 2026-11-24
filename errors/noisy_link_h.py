import argparse
import random
import select
import signal
import socket
import struct
import time


stopping = False


def request_stop(_signum, _frame):
    global stopping
    stopping = True


def corrupt(frame, mode, rng):
    if len(frame) <= 14:
        return frame
    payload_start = 14
    payload_end = len(frame) - 7
    bit_count = {"single": 1, "double": 2}.get(mode)
    if mode == "burst":
        bit_count = rng.randint(8, 32)
    available = (payload_end - payload_start) * 8
    if available < bit_count:
        return frame
    if mode == "burst":
        start = rng.randrange(available - bit_count + 1)
        positions = range(start, start + bit_count)
    else:
        positions = rng.sample(range(available), bit_count)
    changed = bytearray(frame)
    for position in positions:
        byte_index = payload_start + position // 8
        changed[byte_index] ^= 1 << (position % 8)
    return bytes(changed)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("in_interface")
    parser.add_argument("out_interface")
    parser.add_argument("--mode", choices=("single", "double", "burst"), required=True)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    if args.in_interface == args.out_interface:
        parser.error("input and output interfaces must differ")
    sockets = {}
    forwarded = 0
    for interface in (args.in_interface, args.out_interface):
        sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3))
        if interface == args.in_interface:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16 * 1024 * 1024)
        sock.bind((interface, 0))
        if interface == args.in_interface:
            membership = struct.pack(
                "IHH8s",
                socket.if_nametoindex(interface),
                1,
                0,
                bytes(8),
            )
            sock.setsockopt(263, 1, membership)
        sockets[interface] = sock
    rng = random.Random(args.seed)
    last_frame = None
    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    try:
        while not stopping:
            now = time.monotonic()
            if last_frame is None:
                timeout = 0.5
            else:
                remaining = 5 - (now - last_frame)
                if remaining <= 0:
                    break
                timeout = min(0.5, remaining)
            ready, _, _ = select.select([sockets[args.in_interface]], [], [], timeout)
            if not ready:
                continue
            frame, address = ready[0].recvfrom(65535)
            if address[2] == getattr(socket, "PACKET_OUTGOING", 4) or len(frame) < 14:
                continue
            if struct.unpack("!H", frame[12:14])[0] != 0x88B5:
                continue
            last_frame = time.monotonic()
            changed = corrupt(frame, args.mode, rng)
            if sockets[args.out_interface].send(changed) != len(changed):
                raise OSError("Raw socket sent a partial Ethernet frame")
            forwarded += 1
    finally:
        for sock in sockets.values():
            sock.close()
        print(f"forwarded_frames={forwarded}", flush=True)


if __name__ == "__main__":
    main()
