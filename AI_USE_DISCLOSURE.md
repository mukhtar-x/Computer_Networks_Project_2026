# AI Use Disclosure

Claude (chat) and an IDE coding assistant were used for planning, code generation, debugging, and documentation. The students ran the experiments on their own Linux machine; the committed results are from those runs. AI assistance did not run or independently validate the experiments.

## AI-assisted areas

- Ethernet switch core
- VLAN module
- Topology scripts
- Error-detection modules
- Experiment runners and analysis
- Project documentation

## Problems found and fixed during testing

The following testing issues were reported by the group:

- The kernel strips VLAN tags from AF_PACKET frame data; this was addressed using `PACKET_AUXDATA`.
- Routes were deleted when an interface went down; route setup was corrected after interface reset.
- IPv6 traffic added noise to captures; IPv6 was disabled in the lab namespaces.
- `tcpdump` could ignore `SIGTERM` while idle; capture shutdown handling was adjusted.
- `dumpcap` lacked write permission for the capture directory; `tcpdump` was used where appropriate.
- The E4 noisy-link module was missing its `main()` entry point; it was added.
- E4 corruption could affect trailer bytes; the corruption range was corrected to protect the trailer.

## Student verification and contributions

Each member should confirm or amend their contribution statement before submission.

- **Abdullah:** [TO CONFIRM BY GROUP]
- **Mashhood Riaz:** [TO CONFIRM BY GROUP]
- **Mukhtar:** [TO CONFIRM BY GROUP]

Mukhtar's roll number: [TO CONFIRM]
