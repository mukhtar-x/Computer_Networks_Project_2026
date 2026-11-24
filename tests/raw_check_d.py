import argparse
import socket


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("interface")
    parser.add_argument("count", type=int)
    args = parser.parse_args()
    if args.count < 1:
        parser.error("count must be positive")
    sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3))
    sock.bind((args.interface, 0))
    received = 0
    while received < args.count:
        frame, address = sock.recvfrom(65535)
        if address[2] == socket.PACKET_OUTGOING or len(frame) < 14:
            continue
        print(f"{frame[:6].hex(':')} {frame[6:12].hex(':')} 0x{int.from_bytes(frame[12:14], 'big'):04x}")
        received += 1
    sock.close()


if __name__ == "__main__":
    main()
