import struct


def ingress(port_cfg, frame):
    if len(frame) < 14:
        return None
    ether_type = struct.unpack("!H", frame[12:14])[0]
    role = port_cfg["role"]
    if role == "access":
        if ether_type == 0x8100:
            return None
        return port_cfg["vlan"], frame
    if role == "trunk":
        if ether_type != 0x8100 or len(frame) < 18:
            return None
        tci, inner_type = struct.unpack("!HH", frame[14:18])
        vlan = tci & 0x0FFF
        if vlan not in port_cfg["vlans"]:
            return None
        return vlan, frame[:12] + struct.pack("!H", inner_type) + frame[18:]
    return None


def egress(port_cfg, vlan, frame):
    role = port_cfg["role"]
    if role == "access":
        return frame if vlan == port_cfg["vlan"] else None
    if role == "trunk":
        if vlan not in port_cfg["vlans"]:
            return None
        return frame[:12] + struct.pack("!HH", 0x8100, vlan & 0x0FFF) + frame[12:]
    return None
