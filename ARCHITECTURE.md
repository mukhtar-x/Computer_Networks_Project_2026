# Network Architecture

## Topology

`topology/setup_h.sh` creates the namespaces and veth links below. The router VLAN interfaces and host default gateways are added by `topology/r1_subif_r.sh`.

```text
 h1 -- SW1 p1 (access VLAN10)      SW2 p1 (access VLAN20) -- h4
 h2 -- SW1 p2 (access VLAN20)      SW2 p2 (access VLAN10) -- h5
 h3 -- SW1 p3 (access VLAN10)      SW2 p3 (access VLAN20) -- h6
             SW1 p4 (trunk VLAN10,20) -- SW2 p4
             SW1 p5 (trunk VLAN10,20) -- R1 r1-sw
                                             | r1-sw.10 / r1-sw.20
                                       R1 r1-r2 -- R2 r2-r1
                                                       |
                                                 R2 r2-s1 -- S1 eth0
```

## Devices and namespaces

| Namespace | Role |
|---|---|
| `h1`–`h6` | End hosts attached to SW1 or SW2 access ports |
| `sw1`, `sw2` | User-space learning switches; `switch/config_sw1_d.json` and `switch/config_sw2_d.json` define their ports |
| `r1` | Router-on-a-stick; VLAN subinterfaces are configured on `r1-sw` |
| `r2` | Routes between the R1–R2 link and the server network |
| `s1` | Server host on the R2–S1 network |

## IPv4 subnets

| Segment | Subnet | Addresses configured by topology scripts |
|---|---|---|
| VLAN10 | `192.168.10.0/24` | R1 `192.168.10.1`; h1 `192.168.10.11`; h3 `192.168.10.12`; h5 `192.168.10.13` |
| VLAN20 | `192.168.20.0/24` | R1 `192.168.20.1`; h2 `192.168.20.11`; h4 `192.168.20.12`; h6 `192.168.20.13` |
| R1–R2 | `10.0.12.0/30` | R1 `10.0.12.1`; R2 `10.0.12.2` |
| R2–S1 server network | `10.0.30.0/24` | R2 `10.0.30.1`; S1 `10.0.30.10` |

The host addresses and R1–R2/server-side addresses are set in `topology/setup_h.sh`. `topology/r1_subif_r.sh` creates `r1-sw.10` at `192.168.10.1/24` and `r1-sw.20` at `192.168.20.1/24`, then adds the corresponding host default routes.

## Host MAC addresses

`topology/setup_h.sh` assigns these addresses to host `eth0` interfaces:

| Host | MAC address |
|---|---|
| h1 | `02:00:00:00:00:01` |
| h2 | `02:00:00:00:00:02` |
| h3 | `02:00:00:00:00:03` |
| h4 | `02:00:00:00:00:04` |
| h5 | `02:00:00:00:00:05` |
| h6 | `02:00:00:00:00:06` |

No MAC addresses for router, switch, or server interfaces are configured in the topology scripts.

## Switch ports

Access ports use the configured VLAN and send/receive untagged frames. Trunks carry the configured VLAN set using 802.1Q tags. Peer interfaces and memberships below are verified from `topology/setup_h.sh` and each switch's JSON configuration.

| Switch | Port | Mode and VLAN(s) | Peer |
|---|---|---|---|
| SW1 | p1 | Access VLAN10 | h1 `eth0` |
| SW1 | p2 | Access VLAN20 | h2 `eth0` |
| SW1 | p3 | Access VLAN10 | h3 `eth0` |
| SW1 | p4 | Trunk VLAN10, VLAN20 | SW2 p4 |
| SW1 | p5 | Trunk VLAN10, VLAN20 | R1 `r1-sw` |
| SW2 | p1 | Access VLAN20 | h4 `eth0` |
| SW2 | p2 | Access VLAN10 | h5 `eth0` |
| SW2 | p3 | Access VLAN20 | h6 `eth0` |
| SW2 | p4 | Trunk VLAN10, VLAN20 | SW1 p4 |

## Communication flows

1. **ARP request flood and reply:** a host's ARP request is a broadcast. The switch learns the source on ingress and floods the frame to eligible ports in that VLAN, excluding the ingress port. A reply is directed back to the requester; ARP observation and the learned MAC table can identify the destination port.
2. **Same-VLAN unicast after learning:** after source MACs have been learned, a known unicast destination is looked up by `(VLAN, MAC)` and forwarded only to its learned port (unless it is on the ingress port).
3. **Tagged trunk traffic:** a frame entering a trunk must carry an allowed 802.1Q VLAN tag. The switch removes the tag for internal processing, then adds a tag when transmitting on an allowed trunk. Access egress remains untagged.
4. **Inter-VLAN routing through R1:** with the VLAN subinterfaces configured and R1 IPv4 forwarding enabled, a host sends traffic for the other subnet to its VLAN gateway (`r1-sw.10` or `r1-sw.20`). Traffic crosses SW1 p5 as a tagged frame and R1 routes it between the VLAN interfaces.
5. **Routed path to S1 through R2:** H1's path to `10.0.30.10` is H1 → SW1 → R1 → R2 over `10.0.12.0/30` → S1 over `10.0.30.0/24`. The setup script installs the route from R1 to the server network, the return VLAN routes on R2, and S1's default route.
6. **E4 error-detection pipeline:** `experiments/e4_errors_h.py` sets up a source, noisy-link, and destination namespace path. `errors/generator_h.py` emits custom Ethernet frames; `errors/noisy_link_h.py` forwards frames while injecting single-bit, double-bit, or burst errors; `errors/receiver_h.py` reports parity, Internet-checksum, and CRC-32 detection results.
