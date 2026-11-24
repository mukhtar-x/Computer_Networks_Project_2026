import struct


class ArpLog:
    def __init__(self):
        self.addresses = {}
        self.announced = {}

    def observe(self, vlan, in_port, frame):
        if len(frame) < 42 or struct.unpack("!H", frame[12:14])[0] != 0x0806:
            return None
        htype, ptype, hlen, plen, operation = struct.unpack("!HHBBH", frame[14:22])
        if htype != 1 or ptype != 0x0800 or hlen != 6 or plen != 4:
            return None
        sender_mac = frame[22:28].hex(":")
        sender_ip = ".".join(str(value) for value in frame[28:32])
        target_ip = ".".join(str(value) for value in frame[38:42])
        if sender_ip != "0.0.0.0":
            key = (vlan, sender_ip)
            value = (sender_mac, in_port)
            self.addresses[key] = value
            if self.announced.get(key) != sender_mac:
                print(f"VLAN {vlan} {sender_ip} is at {sender_mac}", flush=True)
                self.announced[key] = sender_mac
        if operation == 2:
            target = self.addresses.get((vlan, target_ip))
            if target is not None:
                return target[1]
        return None
