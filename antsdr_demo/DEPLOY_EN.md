# E200 + E316 local-UHD srsRAN 4G deployment

This document describes the validated E200/eNB and E316/UE LTE setup. EPC,
eNB, and UE run on one Linux host. The two SDRs use separate gigabit Ethernet
links for IQ transport; the RF path is provided by antennas in a screened
chamber or by two attenuated RF paths.

All commands use the absolute paths from this validated host:
`/home/wcc/mp_demo/SDR-APP/srsRAN_4G` for srsRAN and
`/home/wcc/wcc_demo/tmp/antsdr_uhd` for the ANTSDR UHD source.

## 1. Software, firmware, and hardware versions

| Item | Version or value |
|---|---|
| srsRAN 4G | `black-pigeon/srsRAN_4G` branch `release_25_10` (validated base commit `6bcbd9e5bf8686aa7085202cd847c5ddd64a9c16`) |
| srsRAN checkout | `/home/wcc/mp_demo/SDR-APP/srsRAN_4G` |
| ANTSDR UHD source | MicroPhase `antsdr_uhd`, commit `b5ebd04a5f405ac3102a772e5d1e8f1be21a7dc3` |
| UHD source checkout | `/home/wcc/wcc_demo/tmp/antsdr_uhd` |
| Private UHD installation | `/opt/antsdr-uhd`, `UHD 4.1.0.0-0-45cabfde` |
| Local srsRAN install | `/home/wcc/.local/srsran-antsdr` |
| Local build directory | `/home/wcc/mp_demo/SDR-APP/srsRAN_4G/build-antsdr-local` |
| E200 image | `/home/wcc/mp_demo/SDR-APP/srsRAN_4G/antsdr_demo/firmware/build_sdimg_e200.zip` |
| E316 image | `/home/wcc/mp_demo/SDR-APP/srsRAN_4G/antsdr_demo/firmware/build_sdimg_e316.zip` |
| Firmware build commit | U-Boot contains `b5ebd04a5f405ac3102a772e5d1e8f1be21a7dc3` |
| FPGA bitstream | E200 `antsdr_e200`; E316 `antsdr_e310v2`; Vivado `2019.1` |
| Device report | FPGA version `16.0`, firmware delivery `2024` |

Each image contains `BOOT.bin`, `antsdr.bit`, `uImage`, `uEnv.txt`,
`devicetree.dtb`, and `uramdisk.image.gz`. Use the E200 image only on E200 and
the E316 image only on E316. With the current firmware, `uhd_find_devices` may
label both units as `ANTSDR-E200`; identify them by IP, serial number, and role.

Verify the private UHD before starting the stack:

```bash
/opt/antsdr-uhd/bin/uhd_config_info --version
source /home/wcc/mp_demo/SDR-APP/srsRAN_4G/antsdr_demo/env.sh
ldd /home/wcc/mp_demo/SDR-APP/srsRAN_4G/build-antsdr-local/srsue/src/srsue | grep -E 'libuhd|libusb'
```

The output must resolve UHD from `/opt/antsdr-uhd`, leaving any system UHD 4.9
unused. `env.sh` sets `PATH`, `LD_LIBRARY_PATH`, and `UHD_IMAGES_DIR`, and the
wrappers preserve them through `sudo -E`.

## 2. Topology and addresses

| Device | Role | SDR IP | Host NIC | RF frequencies |
|---|---|---|---|---|
| E200 | eNB | `192.168.1.10` | `eth2` (host `192.168.1.100`) | DL `2635 MHz`, UL `2515 MHz` |
| E316 | UE | `192.168.10.122` | `eth0` (host `192.168.10.200`) | DL `2635 MHz`, UL `2515 MHz` |

Ethernet carries IQ and control traffic only; it is not the LTE RF path. For
antenna testing, keep both units in a screened enclosure. For a cabled test,
use separate attenuated paths E200 TX→E316 RX and E316 TX→E200 RX. Never connect
TX directly to RX.

## 3. Downloading and building ANTSDR UHD and firmware

The host driver and firmware come from the MicroPhase repository:

```bash
test -d /home/wcc/wcc_demo/tmp/antsdr_uhd/.git || git clone https://github.com/MicroPhase/antsdr_uhd.git /home/wcc/wcc_demo/tmp/antsdr_uhd
git -C /home/wcc/wcc_demo/tmp/antsdr_uhd checkout b5ebd04a5f405ac3102a772e5d1e8f1be21a7dc3
```

Build the private host UHD without replacing a system UHD installation:

```bash
sudo apt-get update
sudo apt-get install -y autoconf automake build-essential ccache cmake \
  cpufrequtils doxygen ethtool g++ git inetutils-tools libboost-all-dev \
  libncurses5 libncurses5-dev libusb-1.0-0 libusb-1.0-0-dev libusb-dev \
  python3-dev python3-mako python3-numpy python3-requests python3-scipy \
  python3-setuptools python3-ruamel.yaml

cd /home/wcc/wcc_demo/tmp/antsdr_uhd/host
cmake -S /home/wcc/wcc_demo/tmp/antsdr_uhd/host -B /home/wcc/wcc_demo/tmp/antsdr_uhd/host/build-antsdr \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/opt/antsdr-uhd \
  -DENABLE_ANT=ON -DENABLE_USB=ON \
  -DENABLE_X400=OFF -DENABLE_N320=OFF -DENABLE_X300=OFF \
  -DENABLE_USRP2=OFF -DENABLE_USRP1=OFF -DENABLE_N300=OFF \
  -DENABLE_E320=OFF -DENABLE_E300=OFF -DENABLE_B200=OFF \
  -DENABLE_B100=OFF -DENABLE_OCTOCLOCK=OFF \
  -DENABLE_PYTHON_API=ON -DENABLE_TESTS=OFF
cmake --build /home/wcc/wcc_demo/tmp/antsdr_uhd/host/build-antsdr --parallel
sudo cmake --install /home/wcc/wcc_demo/tmp/antsdr_uhd/host/build-antsdr
```

The ANT component currently requires `ENABLE_USB=ON` at build time even though
the E200/E316 data path uses Ethernet. Verify the result before building
srsRAN:

```bash
export PATH=/opt/antsdr-uhd/bin:$PATH
export LD_LIBRARY_PATH=/opt/antsdr-uhd/lib:${LD_LIBRARY_PATH:-}
export UHD_IMAGES_DIR=/opt/antsdr-uhd/share/uhd/images
/opt/antsdr-uhd/bin/uhd_config_info --version
/opt/antsdr-uhd/bin/uhd_find_devices --args="addr=192.168.1.10"
/opt/antsdr-uhd/bin/uhd_usrp_probe --args="addr=192.168.1.10,product=E200"
```

To rebuild the SD images from source, install Vivado/SDK 2019.1 and source
their settings scripts. The firmware repository defaults to
`/opt/Xilinx/Vivado/2019.1` and `/opt/Xilinx/SDK/2019.1`:

```bash
sudo apt-get install -y git build-essential fakeroot ccache bc bison flex \
  libncurses5-dev libssl-dev libtinfo5 cpio zip unzip rsync file wget mtools \
  device-tree-compiler u-boot-tools

source /opt/Xilinx/Vivado/2019.1/settings64.sh
source /opt/Xilinx/SDK/2019.1/settings64.sh
cd /home/wcc/wcc_demo/tmp/antsdr_uhd/firmware
/home/wcc/wcc_demo/tmp/antsdr_uhd/firmware/scripts/build_image.sh e200
/home/wcc/wcc_demo/tmp/antsdr_uhd/firmware/scripts/build_image.sh e310v2
```

Use `--rebuild-fpga` when the tracked FPGA sources must be regenerated. The
resulting `/home/wcc/wcc_demo/tmp/antsdr_uhd/firmware/build_sdimg/` contains `BOOT.bin`, `antsdr.bit`, `uImage`,
`uEnv.txt`, `devicetree.dtb`, and `uramdisk.image.gz`. If Vivado is not
available, use the supplied images in `/home/wcc/mp_demo/SDR-APP/srsRAN_4G/antsdr_demo/firmware/` in this srsRAN
checkout instead.

## 4. Loading the firmware

Unpack the appropriate image:

```bash
mkdir -p /tmp/antsdr-e200 /tmp/antsdr-e316
unzip /home/wcc/mp_demo/SDR-APP/srsRAN_4G/antsdr_demo/firmware/build_sdimg_e200.zip -d /tmp/antsdr-e200
unzip /home/wcc/mp_demo/SDR-APP/srsRAN_4G/antsdr_demo/firmware/build_sdimg_e316.zip -d /tmp/antsdr-e316
```

Copy the six files under `/home/wcc/wcc_demo/tmp/antsdr_uhd/firmware/build_sdimg/` to the root of the matching FAT32 SD
card, power the unit off, insert the card, and boot it. Then probe each radio:

```bash
source /home/wcc/mp_demo/SDR-APP/srsRAN_4G/antsdr_demo/env.sh
/opt/antsdr-uhd/bin/uhd_usrp_probe --args 'type=ant,addr=192.168.1.10'
/opt/antsdr-uhd/bin/uhd_usrp_probe --args 'type=ant,addr=192.168.10.122'
```

Both devices should report FPGA version `16.0`. Verify Ethernet reachability
before starting srsRAN.

## 5. Host networking and build

Connect each radio to a separate gigabit NIC and configure the host addresses:

```bash
sudo ip addr add 192.168.1.100/24 dev eth2
sudo ip addr add 192.168.10.200/24 dev eth0
ping -c 3 192.168.1.10
ping -c 3 192.168.10.122
```

The host needs CMake, GNU C/C++, Boost, FFTW, mbedTLS, SCTP, ZeroMQ, libusb,
and real-time thread permissions. Install the srsRAN build dependencies:

```bash
sudo apt-get install -y build-essential cmake ninja-build \
  libfftw3-dev libmbedtls-dev libpcsclite-dev \
  libboost-program-options-dev libboost-system-dev libconfig++-dev \
  libsctp-dev libzmq3-dev
```

Download the matching srsRAN source if it is not already available:

```bash
test -d /home/wcc/mp_demo/SDR-APP/srsRAN_4G/.git || git clone --branch release_25_10 --single-branch https://github.com/black-pigeon/srsRAN_4G.git /home/wcc/mp_demo/SDR-APP/srsRAN_4G
git -C /home/wcc/mp_demo/SDR-APP/srsRAN_4G remote set-url origin https://github.com/black-pigeon/srsRAN_4G.git
git -C /home/wcc/mp_demo/SDR-APP/srsRAN_4G fetch origin release_25_10
git -C /home/wcc/mp_demo/SDR-APP/srsRAN_4G checkout release_25_10
```

Configure CMake with `UHD_DIR`; this project’s `FindUHD.cmake` reads that
environment variable and otherwise may select a system UHD:

```bash
cd /home/wcc/mp_demo/SDR-APP/srsRAN_4G
source /home/wcc/mp_demo/SDR-APP/srsRAN_4G/antsdr_demo/env.sh
export UHD_DIR=/opt/antsdr-uhd
cmake -S /home/wcc/mp_demo/SDR-APP/srsRAN_4G -B /home/wcc/mp_demo/SDR-APP/srsRAN_4G/build-antsdr-local \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/home/wcc/.local/srsran-antsdr \
  -DENABLE_UHD=ON -DENABLE_GUI=OFF \
  -DENABLE_BLADERF=OFF -DENABLE_SOAPYSDR=OFF \
  -DENABLE_ZEROMQ=ON
cmake --build /home/wcc/mp_demo/SDR-APP/srsRAN_4G/build-antsdr-local -j"$(nproc)"
cmake --install /home/wcc/mp_demo/SDR-APP/srsRAN_4G/build-antsdr-local
```

If the CMake cache previously selected system UHD, remove the build directory
and configure it again. The srsRAN startup banner must show
`UHD_4.1.0.0-0-45cabfde`.

## 6. Starting EPC, eNB, and UE

The EPC runs on the host. S1 uses `127.0.1.100`, and the SPGW gateway is
`172.16.0.1`. Start three terminals in this order:

```bash
cd /home/wcc/mp_demo/SDR-APP/srsRAN_4G
/home/wcc/mp_demo/SDR-APP/srsRAN_4G/antsdr_demo/run_epc.sh
```

E200 is always the eNB in this setup:

```bash
/home/wcc/mp_demo/SDR-APP/srsRAN_4G/antsdr_demo/run_enb.sh --profile 25prb
```

E316 is always the UE:

```bash
/home/wcc/mp_demo/SDR-APP/srsRAN_4G/antsdr_demo/run_ue.sh --profile 25prb
```

After `Network attach successful. IP: 172.16.0.x`, test the data plane from
the UE network namespace:

```bash
sudo ip netns exec ue1 ip addr show tun_srsue
sudo ip netns exec ue1 ip route
sudo ip netns exec ue1 ping -c 10 -i 0.3 -W 2 172.16.0.1
```

The namespace is required for a same-host EPC/UE test. A host-side ping can
take the local SGI route and does not prove that packets crossed the LTE link.

## 7. Validated PRB profiles

| Profile | Bandwidth | Host IQ rate | eNB `time_adv_nsamples` | UE `time_adv_nsamples` | Result |
|---|---:|---:|---:|---:|---|
| `6prb` | 1.4 MHz | 1.92 MSPS | 49 | 67 | attach, 10/10 ping |
| `15prb` | 3 MHz | 3.84 MSPS | 25 | 83 | attach, 10/10 ping |
| `25prb` | 5 MHz | 5.76 MSPS | 0 | 100 | attach, 10/10 ping |

Stop UE and eNB before switching profiles; EPC can remain running:

```bash
/home/wcc/mp_demo/SDR-APP/srsRAN_4G/antsdr_demo/run_enb.sh --profile 15prb
/home/wcc/mp_demo/SDR-APP/srsRAN_4G/antsdr_demo/run_ue.sh --profile 15prb
```

A first 50-PRB attempt at 11.52 MSPS did not reach successful cell search on
this host, with both 23.04 MHz and 46.08 MHz master clocks. It is therefore
not marked as validated. Higher rates need additional CPU, UHD buffering, and
Ethernet real-time investigation; changing only `time_adv_nsamples` cannot fix
a failure that occurs before PRACH detection.

## 8. Troubleshooting

- No cell: check EARFCN, RF antenna path, both IPs, and the UHD banner; fall back to `25prb`.
- PRACH detected but Msg3 CRC fails: tune the UE timing value until eNB `preamble` equals UE `seq`.
- Attach succeeds but ping fails: run ping inside `ue1` and allow the first Service Request to complete.
- `SCHED: Could not transmit RAR within the window`: stop UE/eNB, clear stale device locks, then restart eNB followed by UE:

```bash
sudo python3 -c 'import glob,os; [os.unlink(f) for f in glob.glob("/run/lock/iqtaxi-device-*.lock")]'
```

Do not run `uhd_usrp_probe`, `benchmark_rate`, and srsRAN against the same
radio at the same time; the ANTSDR backend allows one UHD handle per unit.

Stop in the order UE, eNB, EPC. Band 7 transmission is restricted to a
screened or otherwise authorized test environment.
