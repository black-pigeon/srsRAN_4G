# E200 + E316 本地 UHD / srsRAN 4G 从零部署指南

本文档描述当前已经在本机验证过的 E200/eNB + E316/UE 空口 LTE 实验环境。EPC、eNB 和 UE 都运行在同一台 Linux 上，两个 SDR 通过独立千兆网卡传输 IQ，RF 连接使用屏蔽箱内天线或合规的衰减器/耦合器。

## 1. 已验证的软件、固件和硬件版本

| 项目 | 当前版本或值 |
|---|---|
| srsRAN 4G | `release_25_10`，commit `6bcbd9e5bf8686aa7085202cd847c5ddd64a9c16` |
| ANTSDR UHD 源码 | MicroPhase `antsdr_uhd`，commit `b5ebd04a5f405ac3102a772e5d1e8f1be21a7dc3` |
| 本地 UHD 安装 | `/opt/antsdr-uhd`，`UHD 4.1.0.0-0-45cabfde` |
| srsRAN 本地安装 | `/home/wcc/.local/srsran-antsdr` |
| srsRAN 本地构建目录 | `/home/wcc/mp_demo/SDR-APP/srsRAN_4G/build-antsdr-local` |
| E200 固件包 | `antsdr_demo/firmware/build_sdimg_e200.zip` |
| E316 固件包 | `antsdr_demo/firmware/build_sdimg_e316.zip` |
| 固件构建提交 | U-Boot 字符串为 `b5ebd04a5f405ac3102a772e5d1e8f1be21a7dc3` |
| FPGA bitstream | E200 `antsdr_e200`；E316 `antsdr_e310v2`；Vivado `2019.1` |
| 设备报告 | FPGA version `16.0`，firmware delivery `2024` |

固件包内包含 `BOOT.bin`、`antsdr.bit`、`uImage`、`uEnv.txt`、`devicetree.dtb` 和 `uramdisk.image.gz`。E200 和 E316 必须使用各自的 SD 镜像，不能交叉刷写。`uhd_find_devices` 在当前固件下可能把两块板都显示为 `ANTSDR-E200`，应以 IP、序列号和实际角色为准。

检查本地 UHD：

```bash
/opt/antsdr-uhd/bin/uhd_config_info --version
source antsdr_demo/env.sh
ldd build-antsdr-local/srsue/src/srsue | grep -E 'libuhd|libusb'
```

输出应来自 `/opt/antsdr-uhd`，不能切换到系统 UHD 4.9。`antsdr_demo/env.sh` 设置了 `PATH`、`LD_LIBRARY_PATH` 和 `UHD_IMAGES_DIR`；三个启动脚本会通过 `sudo -E` 传递这些变量。

## 2. 硬件拓扑和地址

| 设备 | 角色 | SDR IP | PC 网卡 | RF 频率 |
|---|---|---|---|---|
| E200 | eNB | `192.168.1.10` | `eth2`（本机当前 `192.168.1.100`） | DL `2635 MHz`，UL `2515 MHz` |
| E316 | UE | `192.168.10.122` | `eth0`（本机当前 `192.168.10.200`） | DL `2635 MHz`，UL `2515 MHz` |

以太网只承载 IQ 和控制报文，不能代替 RF 空口。首次测试应在屏蔽箱内使用天线；使用射频线时必须分别连接 eNB TX→UE RX 和 UE TX→eNB RX，并加入足够衰减，不能直接把 TX 接到 RX。

## 3. 下载、编译和安装 ANTSDR UHD 与固件

UHD 主机驱动和固件均来自 MicroPhase 项目：

```bash
git clone https://github.com/MicroPhase/antsdr_uhd.git
cd antsdr_uhd
git checkout b5ebd04a5f405ac3102a772e5d1e8f1be21a7dc3
```

先编译到独立目录 `/opt/antsdr-uhd`，不要覆盖系统 UHD：

```bash
sudo apt-get update
sudo apt-get install -y autoconf automake build-essential ccache cmake \
  cpufrequtils doxygen ethtool g++ git inetutils-tools libboost-all-dev \
  libncurses5 libncurses5-dev libusb-1.0-0 libusb-1.0-0-dev libusb-dev \
  python3-dev python3-mako python3-numpy python3-requests python3-scipy \
  python3-setuptools python3-ruamel.yaml

cd host
cmake -S . -B build-antsdr \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/opt/antsdr-uhd \
  -DENABLE_ANT=ON -DENABLE_USB=ON \
  -DENABLE_X400=OFF -DENABLE_N320=OFF -DENABLE_X300=OFF \
  -DENABLE_USRP2=OFF -DENABLE_USRP1=OFF -DENABLE_N300=OFF \
  -DENABLE_E320=OFF -DENABLE_E300=OFF -DENABLE_B200=OFF \
  -DENABLE_B100=OFF -DENABLE_OCTOCLOCK=OFF \
  -DENABLE_PYTHON_API=ON -DENABLE_TESTS=OFF
cmake --build build-antsdr --parallel
sudo cmake --install build-antsdr
```

ANT 组件目前构建时仍需要 `ENABLE_USB=ON`。安装后检查：

```bash
export PATH=/opt/antsdr-uhd/bin:$PATH
export LD_LIBRARY_PATH=/opt/antsdr-uhd/lib:${LD_LIBRARY_PATH:-}
export UHD_IMAGES_DIR=/opt/antsdr-uhd/share/uhd/images
/opt/antsdr-uhd/bin/uhd_config_info --version
uhd_find_devices --args="addr=192.168.1.10"
uhd_usrp_probe --args="addr=192.168.1.10,product=E200"
```

若要从源码重新生成 SD 固件，需要安装 Xilinx Vivado/SDK 2019.1，默认路径为
`/opt/Xilinx/Vivado/2019.1` 和 `/opt/Xilinx/SDK/2019.1`：

```bash
sudo apt-get install -y git build-essential fakeroot ccache bc bison flex \
  libncurses5-dev libssl-dev libtinfo5 cpio zip unzip rsync file wget mtools \
  device-tree-compiler u-boot-tools
source /opt/Xilinx/Vivado/2019.1/settings64.sh
source /opt/Xilinx/SDK/2019.1/settings64.sh
cd ../firmware
scripts/build_image.sh e200
scripts/build_image.sh e310v2
```

使用 `--rebuild-fpga` 可强制重新生成 FPGA 工程。没有 Vivado 时，直接使用本项目
本项目 `antsdr_demo/firmware/` 目录中已经生成的两个 zip 镜像。

## 4. 固件准备

分别解压对应文件：

```bash
mkdir -p /tmp/antsdr-e200 /tmp/antsdr-e316
cd /path/to/srsRAN_4G
unzip antsdr_demo/firmware/build_sdimg_e200.zip -d /tmp/antsdr-e200
unzip antsdr_demo/firmware/build_sdimg_e316.zip -d /tmp/antsdr-e316
```

将对应 `build_sdimg/` 中的六个文件复制到对应设备的 FAT32 SD 卡根目录，关机插卡后启动设备。刷写后检查：

```bash
source antsdr_demo/env.sh
uhd_usrp_probe --args 'type=ant,addr=192.168.1.10'
uhd_usrp_probe --args 'type=ant,addr=192.168.10.122'
```

应看到 FPGA version `16.0`。固件升级后先单独确认两块板可 ping，再启动 srsRAN。

## 5. 主机网络、srsRAN 下载和编译

将两块 SDR 接到独立的千兆网口，配置 PC 地址并确认链路：

```bash
sudo ip addr add 192.168.1.100/24 dev eth2
sudo ip addr add 192.168.10.200/24 dev eth0
ping -c 3 192.168.1.10
ping -c 3 192.168.10.122
```

安装 srsRAN 依赖：

```bash
sudo apt-get install -y build-essential cmake ninja-build \
  libfftw3-dev libmbedtls-dev libpcsclite-dev \
  libboost-program-options-dev libboost-system-dev libconfig++-dev \
  libsctp-dev libzmq3-dev
```

如果尚未取得源码：

```bash
git clone https://github.com/black-pigeon/srsRAN_4G.git
cd srsRAN_4G
git checkout release_25_10
```

当前工程已经使用 ANTSDR UHD 编译完成；重新编译时必须设置 `UHD_DIR`，否则项目的
`FindUHD.cmake` 可能找到系统 UHD 4.9：

```bash
cd /home/wcc/mp_demo/SDR-APP/srsRAN_4G
source antsdr_demo/env.sh
export UHD_DIR=/opt/antsdr-uhd
cmake -S . -B build-antsdr-local \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/home/wcc/.local/srsran-antsdr \
  -DENABLE_UHD=ON -DENABLE_GUI=OFF \
  -DENABLE_BLADERF=OFF -DENABLE_SOAPYSDR=OFF \
  -DENABLE_ZEROMQ=ON
cmake --build build-antsdr-local -j"$(nproc)"
cmake --install build-antsdr-local
```

如果 CMake 缓存过系统 UHD，应删除构建目录后重新配置。启动 banner 必须显示 `UHD_4.1.0.0-0-45cabfde`。

## 6. 启动 EPC、eNB 和 UE

EPC 在本机运行，S1/核心网地址是 `127.0.1.100`，SPGW 用户面网关是 `172.16.0.1`。按以下顺序打开三个终端：

```bash
cd /home/wcc/mp_demo/SDR-APP/srsRAN_4G
antsdr_demo/run_epc.sh
```

第二个终端启动 eNB，E200 固定作为 eNB：

```bash
cd /home/wcc/mp_demo/SDR-APP/srsRAN_4G
antsdr_demo/run_enb.sh --profile 25prb
```

第三个终端启动 UE，E316 固定作为 UE：

```bash
cd /home/wcc/mp_demo/SDR-APP/srsRAN_4G
antsdr_demo/run_ue.sh --profile 25prb
```

UE 看到 `Network attach successful. IP: 172.16.0.x` 后，从 UE 的 network namespace 测试用户面：

```bash
sudo ip netns exec ue1 ip addr show tun_srsue
sudo ip netns exec ue1 ip route
sudo ip netns exec ue1 ping -c 10 -i 0.3 -W 2 172.16.0.1
```

必须在 `ue1` 内 ping。EPC 和 UE 同机时，直接从主机 ping 可能命中本地 SGI 路由，不能证明 LTE 用户面已经通过空口。

## 7. 已验证 PRB 档位

| Profile | 带宽 | 主机 IQ 采样率 | eNB `time_adv_nsamples` | UE `time_adv_nsamples` | 结果 |
|---|---:|---:|---:|---:|---|
| `6prb` | 1.4 MHz | 1.92 MSPS | 49 | 67 | attach，ping 10/10 |
| `15prb` | 3 MHz | 3.84 MSPS | 25 | 83 | attach，ping 10/10 |
| `25prb` | 5 MHz | 5.76 MSPS | 0 | 100 | attach，ping 10/10 |

切换时只停止 UE 和 eNB，EPC 可以保持运行：

```bash
antsdr_demo/run_enb.sh --profile 15prb
antsdr_demo/run_ue.sh --profile 15prb
```

50 PRB（11.52 MSPS）在当前主机上曾用 23.04 MHz 和 46.08 MHz 主时钟尝试，UE 未进入小区搜索成功状态，因此目前不作为交付档位。高采样率需要继续检查 CPU 实时性、UHD 缓冲和以太网传输；不能仅靠修改 `time_adv_nsamples` 解决。

## 8. 故障排查

- UE 找不到小区：确认两端 EARFCN、RF 天线方向、设备 IP 和 UHD banner；先降回 `25prb`。
- eNB 能检测 PRACH 但 Msg3 CRC 错误：检查 UE 的 `time_adv_nsamples`，以 eNB `preamble` 与 UE `seq` 一致为准。
- attach 成功但 ping 失败：从 `sudo ip netns exec ue1 ...` 测试，并等待第一次 Service Request 完成。
- 出现 `SCHED: Could not transmit RAR within the window`：停止 UE/eNB，清理设备锁后重新按 eNB→UE 顺序启动：

```bash
sudo python3 -c 'import glob,os; [os.unlink(f) for f in glob.glob("/run/lock/iqtaxi-device-*.lock")]'
```

- 不要同时运行 `uhd_usrp_probe`、`benchmark_rate` 和 srsRAN；ANTSDR 后端同一块板只允许一个 UHD handle。

停止顺序为 UE、eNB、EPC。Band 7 发射只应在屏蔽环境或获得授权的测试环境中进行。
