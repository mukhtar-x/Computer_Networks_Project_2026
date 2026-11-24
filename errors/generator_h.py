import argparse
import random
import socket
import struct
import time

from codes_h import crc32, even_parity, internet_checksum


def build_frame(source, destination, sequence, rng):
    payload = struct.pack("!I", sequence) + bytes(rng.getrandbits(8) for _ in range(60))
    parity = bytes((even_parity(payload),))
    checksum = struct.pack("!H", internet_checksum(payload))
    protected = payload + parity + checksum
    return destination + source + struct.pack("!H", 0x88B5) + protected + struct.pack("!I", crc32(protected))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("interface")
    parser.add_argument("dst_mac")
    parser.add_argument("--count", type=int, default=100000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    if args.count < 1:
        parser.error("--count must be positive")
    try:
        destination = bytes.fromhex(args.dst_mac.replace(":", ""))
    except ValueError:
        parser.error("dst_mac must be a six-byte MAC address")
    if len(destination) != 6:
        parser.error("dst_mac must be a six-byte MAC address")
    sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    sock.bind((args.interface, 0))
    source = sock.getsockname()[4]
    if len(source) != 6:
        raise RuntimeError(f"Could not read the MAC address for {args.interface}")
    rng = random.Random(args.seed)
    sent = 0
    try:
        for sequence in range(args.count):
            frame = build_frame(source, destination, sequence, rng)
            if sock.send(frame) != len(frame):
                raise OSError("Raw socket sent a partial Ethernet frame")
            sent += 1
            if sent % 200 == 0:
                time.sleep(0.005)
    finally:
        sock.close()
        print(f"sent_frames={sent}", flush=True)


if __name__ == "__main__":
    main()
