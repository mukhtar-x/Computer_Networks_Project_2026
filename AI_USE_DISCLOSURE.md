# AI Use Disclosure

The group used Claude and an IDE coding assistant for planning, learning, coding assistance, debugging, documentation, and video generation. Most AI use was for learning and assistance: suggestions and explanations helped the students understand concepts and troubleshoot their work. Students reviewed and applied assistance while doing their assigned implementation, testing, and experiment work. AI did not run the network experiments; the results in the repository came from the students' runs on their Linux machine.

The initial proposal states that Claude helped draft the proposal's topology diagram, first addressing plan, and experiment table; the group checked and edited that material against the course handout. For the completed project, AI assistance also included:

- Learning support and planning
- Coding assistance and debugging for the switch, VLAN, topology, error-detection, and experiment work
- Documentation, including this disclosure and report material
- Assistance with video generation for the demo

## Member contributions and verification

The following assignments are from the group's proposal. Each member implemented and tested their assigned part, then ran through the relevant experiment or demonstration steps. The proposal also says that all members contributed to the report and live demo and checked one another's code.

- **Mashhood Riaz (24K-0530):** Implemented the learning-switch features F1–F3: MAC learning and aging, flooding and forwarding, and ARP handling. His assigned work also included the E1 and E2 scripts, Linux bridge baseline, and report sections on the switch. He ran through the assigned switch tests and E1/E2 comparisons.
- **Mukhtar (24K-0511):** Implemented F4–F5: access-port VLAN isolation, trunk ports, and the second switch. His assigned work also included R1 subinterfaces, E5 tests, and the README. He ran through the VLAN, trunk, routing-forwarding, and E5 checks.
- **Abdullah (24K-0532):** Implemented F6–F8: the noisy link, CRC-32 frame generator and receiver, parity, and Internet-checksum checks. His assigned work also included the R1/R2/S1 topology and traffic-control scripts, E3/E4, packet captures, and Wireshark screenshots. He ran through the assigned routed-link, error-detection, and capture tests.

The proposal specifies three runs per experimental condition and says each member was responsible for their assigned experiment work. Students ran those experiments on their own Linux machine; the submitted CSV results reflect those runs.

## Testing issues addressed

During implementation and testing, the group addressed these issues:

- The kernel strips VLAN tags from AF_PACKET frame data; `PACKET_AUXDATA` was used to recover VLAN metadata.
- Routes were deleted when an interface went down; route setup was corrected after interface reset.
- IPv6 traffic added noise to captures; IPv6 was disabled in the lab namespaces.
- `tcpdump` could ignore `SIGTERM` while idle; capture shutdown handling was adjusted.
- `dumpcap` lacked write permission for the capture directory; `tcpdump` was used where appropriate.
- The E4 noisy-link module was missing its `main()` entry point; it was added.
- E4 corruption could affect trailer bytes; the corruption range was corrected to protect the trailer.
