# ANTSDR E200 + E316 local UHD / srsRAN 4G

See the complete from-scratch instructions in [DEPLOY_EN.md](DEPLOY_EN.md), or the
[Chinese deployment guide](DEPLOY_CN.md).

The fixed topology is **E200 as eNB and E316 as UE**. E200 is
`192.168.1.10` on host NIC `eth2`; E316 is `192.168.10.122` on host NIC `eth0`.
Ethernet carries IQ only. The RF path must use antennas in a screened chamber or two
separately attenuated RF paths.

This setup uses the private UHD built from MicroPhase `antsdr_uhd` commit
`b5ebd04a5f405ac3102a772e5d1e8f1be21a7dc3`, installed in `/opt/antsdr-uhd` as
`UHD_4.1.0.0-0-45cabfde`; system UHD 4.9 is not used. Firmware is in
[`firmware/`](firmware/): use `build_sdimg_e200.zip` for E200 and
`build_sdimg_e316.zip` for E316. The bitstreams are `antsdr_e200` and `antsdr_e310v2`,
built with Vivado `2019.1`; the tested devices report FPGA version `16.0`.

Start the local EPC, eNB, and UE from the repository root:

```bash
antsdr_demo/run_epc.sh
antsdr_demo/run_enb.sh --profile 25prb
antsdr_demo/run_ue.sh --profile 25prb
```

Validated profiles:

| Profile | Host IQ rate | eNB/UE timing | Result |
|---|---:|---:|---|
| `6prb` | 1.92 MSPS | `49/67` | attach + 10/10 ping |
| `15prb` | 3.84 MSPS | `25/83` | attach + 10/10 ping |
| `25prb` | 5.76 MSPS | `0/100` | attach + 10/10 ping |

Stop UE and eNB before switching profiles; EPC can remain running:

```bash
antsdr_demo/run_enb.sh --profile 15prb
antsdr_demo/run_ue.sh --profile 15prb
```

Verify the user plane from the UE namespace:

```bash
sudo ip netns exec ue1 ping -c 10 -i 0.3 -W 2 172.16.0.1
```

A first 50-PRB attempt at 11.52 MSPS did not complete cell search on this host, so it is
not currently a validated delivery profile. For the full setup and troubleshooting steps,
use [DEPLOY_EN.md](DEPLOY_EN.md).
