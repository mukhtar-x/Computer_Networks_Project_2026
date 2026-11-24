import argparse
import select
import socket
import struct
import time

from codes_h import crc32, even_parity, internet_checksum


def check_frame(frame):
    if len(frame) < 14 + 64 + 7 or struct.unpack("!H", frame[12:14])[0] != 0x88B5:
        return None
    payload = frame[14:-7]
    parity = frame[-7]
    checksum = struct.unpack("!H", frame[-6:-4])[0]
    expected_crc = struct.unpack("!I", frame[-4:])[0]
    parity_ok = even_parity(payload) == parity
    checksum_ok = internet_checksum(payload + (b"\x00" if len(payload) & 1 else b"") + frame[-6:-4]) == 0
    crc_ok = crc32(frame[14:-4]) == expected_crc
    return parity_ok, checksum_ok, crc_ok


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("interface")
    parser.add_argument("--count", type=int, default=100000)
    args = parser.parse_args()
    if args.count < 1:
        parser.error("--count must be positive")
    sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3))
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16 * 1024 * 1024)
    sock.bind((args.interface, 0))
    counts = {"parity": 0, "checksum": 0, "crc32": 0}
    received = 0
    changed = 0
    last_frame = None
    try:
        while received < args.count:
            timeout = 5 if last_frame is None else 5 - (time.monotonic() - last_frame)
            if timeout <= 0:
                break
            ready, _, _ = select.select([sock], [], [], timeout)
            if not ready:
                break
            frame, address = sock.recvfrom(65535)
            if address[2] == getattr(socket, "PACKET_OUTGOING", 4) or len(frame) < 14:
                continue
            last_frame = time.monotonic()
            result = check_frame(frame)
            if result is None:
                continue
            received += 1
            for name, valid in zip(counts, result):
                if not valid:
                    counts[name] += 1
            if not all(result):
                changed += 1
    except KeyboardInterrupt:
        pass
    finally:
        sock.close()
        print(f"received={received} expected={args.count}", flush=True)
        if received < args.count:
            print(
                f"WARNING: received {received} of {args.count} expected frames",
                flush=True,
            )
    print(f"received={received} changed={changed} detected={changed} missed={received - changed}")
    for name, detected in counts.items():
        missed = received - detected
        rate = f"{detected * 100 / received:.6f}" if received else "NA"
        print(f"{name}: detected={detected} missed={missed} detection_rate_pct={rate}")


if __name__ == "__main__":
    main()
