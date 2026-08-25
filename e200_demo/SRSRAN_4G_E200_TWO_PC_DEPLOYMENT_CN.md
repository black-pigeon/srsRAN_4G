# 两台电脑、两台 E200 搭建 srsRAN_4G

本文说明如何在两台 Ubuntu 电脑上分别连接一台 E200，搭建一个 LTE FDD
srsRAN_4G 系统。电脑 A 运行 EPC 和 eNB，电脑 B 运行 UE。内容覆盖主机网络、
IQTAXI 驱动、IQTAXI UHD 动态插件、srsRAN_4G、不同 PRB profile、外部
10 MHz 参考以及数据面验证。

本文使用当前工程中已经验证过的 strict-timestamp 实现。不要把旧版 E200
rootfs、旧 FPGA 或其他 UHD ABI 下编译的 `libIQTaxiUHD.so` 与本文软件混用。

## 1. 拓扑和地址约定

```text
电脑 A（EPC + eNB）                         电脑 B（UE）

srsEPC + srsENB                             srsUE（netns: ue1）
        |                                            |
SDR 网口 192.168.1.100/24                   SDR 网口 192.168.10.200/24
        |                                            |
E200 192.168.1.10                           E200 192.168.10.2
        |                                            |
        +------------ LTE Band 7 空口 ---------------+
```

两台电脑还可以通过另外的普通管理网络互相 SSH，但管理网络不能和上述两个 SDR
子网冲突。EPC 和 eNB 都在电脑 A 上，所以 `e200_demo/enb.conf` 中的
`mme_addr=127.0.1.100`、`gtp_bind_addr=127.0.1.1` 和
`s1c_bind_addr=127.0.1.1` 不需要改成电脑 B 的地址。UE 通过 LTE 空口接入 EPC。

本文假设两台电脑都有以下目录：

```text
/home/wcc/vm_box/xilinx_image_builder
/home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
```

如果用户名或安装位置不同，替换命令中的路径即可。两台电脑应使用同一版本的
IQTAXI、UHD、srsRAN_4G 和 `e200_demo` 配置。

## 2. 硬件、参考时钟和射频安全

准备以下硬件：

- 两台千兆网口的 Ubuntu 电脑；
- 两台已更新到当前 E200 固件/FPGA 的 E200；
- 两条射频链路及足够的衰减器，或合规的屏蔽测试环境；
- 可选：同一个 10 MHz 参考源的两路输出。

Band 7 是许可频段，只能在屏蔽环境或获得授权的条件下发射。线缆直连必须使用
两条单向链路，并在每条链路中加入足够衰减：

```text
eNB TX -> 衰减器 -> UE RX
UE TX  -> 衰减器 -> eNB RX
```

禁止把 TX 不经衰减直接连接 RX。第一次测试可使用 internal 参考。使用 external
参考时，两台 E200 必须连接同一个 10 MHz 源。10 MHz 统一频率，但本例 LTE
attach 不要求公共 PPS。

## 3. 检查 E200 板端

E200 的 SSH 用户和密码均为 `root`。分别在对应电脑上执行：

```bash
ping -c 3 <E200-IP>
ssh root@<E200-IP>
/etc/init.d/S46init-ad9361 status
sha256sum /usr/sbin/e200_v25_server
tail -n 100 /var/log/e200_v25_server.log
```

server 应处于运行状态，日志中不应有持续初始化失败。当前固件应包含 strict timed
TX、低采样率 FIR 和 23.04 MSPS 支持。若板端版本不一致，应先使用当前工程生成的
E200 SD 镜像统一两台设备，再继续主机部署。

当前已验证 rootfs 中的参考哈希为：

```text
e200_v25_server SHA256:
436172dce148924d6bbe67a915b98c9b4e53da80baf94f582d792dbabd94e80e

e200_iqtaxi.bit SHA256:
c8d44d13bbbe28f262c0394295ac4418fe0a223ea755196d1adaa2794dd83744
```

重新构建正式交付镜像后哈希可能改变；实际要求是两台板使用同一套已验证产物，并
保留对应构建记录。

两块新板若都是默认地址 `192.168.1.10`，它们分属两台电脑时不会互相冲突；但为了
直接使用现有 profile，建议将 UE 板持久化为 `192.168.10.2`。只连接 UE 板时，在
`xilinx_image_builder` 根目录执行：

```bash
python3 scripts/e206_fw_tcp_update.py \
  --host 192.168.1.10 set-ip-addr 192.168.10.2
```

这里的脚本名虽然包含 `e206`，但也是当前 E200/E206 共用的网络与固件更新工具。
修改后重新上电。如果不修改 UE 板地址，不能只在 `run_ue.sh` 命令末尾覆盖
`device_args`，因为脚本会先 ping profile 中的默认地址。此时应参考第 13 节直接启动
`srsue`，或在自定义 profile 中同时修改 `E200_UE_ADDR`。

## 4. 配置两台电脑的 SDR 网口

先用下面的命令找出实际接口名：

```bash
ip -br link
```

电脑 A：

```bash
sudo ip link set <ENB_NIC> up
sudo ip address replace 192.168.1.100/24 dev <ENB_NIC>
ping -c 3 192.168.1.10
ethtool <ENB_NIC> | grep -E 'Speed|Duplex|Link detected'
```

电脑 B：

```bash
sudo ip link set <UE_NIC> up
sudo ip address replace 192.168.10.200/24 dev <UE_NIC>
ping -c 3 192.168.10.2
ethtool <UE_NIC> | grep -E 'Speed|Duplex|Link detected'
```

两条链路都应显示 `1000Mb/s`、`Full` 和 `Link detected: yes`。不要在远程 SSH
所依赖的接口上执行 `ip addr flush`。上述 `ip` 配置重启后会消失，长期使用时请用
NetworkManager 或 netplan 持久化相同地址。

建议两台电脑都设置较大的 UDP 接收缓冲：

```bash
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.rmem_default=16777216
sudo sysctl -w net.core.netdev_max_backlog=10000
```

100 PRB 时这些参数尤其重要。

## 5. 安装 UHD

以下步骤在电脑 A、电脑 B 都要执行。IQTAXI UHD module 必须和运行时 UHD 使用
同一 ABI。当前验证环境是：

```text
UHD 4.9.0.0-11-gcf78e1cf
install prefix: /usr/local
```

先检查现有环境：

```bash
which uhd_config_info
uhd_config_info --version
uhd_config_info --install-prefix
ldconfig -p | grep libuhd
```

如果电脑已经安装兼容版本，可直接使用。如果需要复现 UHD 4.9，可执行：

```bash
sudo apt update
sudo apt install -y \
  build-essential cmake pkg-config \
  libboost-all-dev libusb-1.0-0-dev \
  python3-mako python3-numpy python3-requests python3-setuptools

git clone --branch v4.9.0.0 https://github.com/EttusResearch/uhd.git
cmake -S uhd/host -B uhd/host/build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build uhd/host/build -j"$(nproc)"
sudo cmake --install uhd/host/build
sudo ldconfig
```

也可以使用 Ubuntu 的 `libuhd-dev` 和 `uhd-host`，但之后必须针对那套 UHD 重新
构建 IQTAXI 插件和 srsRAN，不能复用 `/usr/local` 下由另一 UHD 版本生成的 `.so`。

## 6. 安装 IQTAXI 和 UHD 插件

### 6.1 安装依赖并构建

两台电脑都执行：

```bash
sudo apt update
sudo apt install -y \
  build-essential cmake pkg-config \
  libboost-all-dev libsoapysdr-dev \
  libgl1-mesa-dev libglfw3-dev libglew-dev

cd /home/wcc/vm_box/xilinx_image_builder/host_app/e200/MICROPHASE_IQ_TAXI

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_GNURADIO_IQTAXI=OFF

cmake --build build -j"$(nproc)"
sudo cmake --install build
sudo ldconfig
```

这一次安装同时完成两部分：

- IQTAXI 核心和设备驱动：`libsdr_core.so`、`libsdr_driver.so`；
- 系统 UHD 动态插件：`lib/uhd/modules/libIQTaxiUHD.so`。

因此不需要再把 UHD 插件手工复制到 srsRAN 目录。以 `/usr/local` UHD 为例，正常
安装结果为：

```text
/usr/local/lib/libsdr_core.so
/usr/local/lib/libsdr_driver.so
/usr/local/lib/uhd/modules/libIQTaxiUHD.so
```

### 6.2 处理 `ldconfig` 的“不是符号链接”提示

正常的版本链接应类似：

```text
libsdr_driver.so -> libsdr_driver.so.1
libsdr_driver.so.1 -> libsdr_driver.so.1.0.0
```

检查：

```bash
ls -l /usr/local/lib/libsdr_driver.so*
ls -l /usr/local/lib/libsdr_core.so*
```

不要用 `cp` 把真实 `.so` 文件覆盖到无版本名称。如果 `libsdr_driver.so` 已经是普通
文件，可先把它改名保留，再重新安装：

```bash
sudo mv /usr/local/lib/libsdr_driver.so \
  /usr/local/lib/libsdr_driver.so.pre-iqtaxi-install
sudo cmake --install build
sudo ldconfig
```

仅在 `ls -l` 确认它确实不是符号链接时执行上述 `mv`。

### 6.3 验证 UHD 插件

电脑 A：

```bash
ldd /usr/local/lib/uhd/modules/libIQTaxiUHD.so | grep 'not found' || true
uhd_find_devices --args 'addr=192.168.1.10'
uhd_usrp_probe --args 'addr=192.168.1.10'
```

电脑 B：

```bash
ldd /usr/local/lib/uhd/modules/libIQTaxiUHD.so | grep 'not found' || true
uhd_find_devices --args 'addr=192.168.10.2'
uhd_usrp_probe --args 'addr=192.168.10.2'
```

预期包含：

```text
name: ANTSDR-E200
product: E200
type: iqtaxi
```

`ldd` 不应输出 `not found`。不要在 srsENB 或 srsUE 正在占用设备时运行 probe。
两板接好公共 10 MHz 后，可分别用 external 参数再次 probe，确认最终锁定：

```bash
uhd_usrp_probe \
  --args 'addr=<本机E200-IP>,clock=external,clock_source=external'
```

可选的纯 RX 检查：

```bash
cd /home/wcc/vm_box/xilinx_image_builder/host_app/e200/MICROPHASE_IQ_TAXI
./build/src/example/e200_iq_example \
  --addr <本机E200-IP> \
  --mode rx \
  --duration 10 \
  --sample-rate 15360000 \
  --rx-lo 2680000000 \
  --rx-gain 20 \
  --rx-request 4096
```

结果应为 `PASS`，且 `recv errors`、`timestamp gaps`、`wire seq errors` 和
`host drops` 均为 0。

## 7. 构建 srsRAN_4G

两台电脑都执行：

```bash
sudo apt update
sudo apt install -y \
  build-essential cmake pkg-config \
  libfftw3-dev libmbedtls-dev libpcsclite-dev \
  libboost-program-options-dev libconfig++-dev libsctp-dev \
  iproute2 iputils-ping ethtool iperf3

cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_UHD=ON
cmake --build build -j"$(nproc)"
```

确认 CMake 使用了预期 UHD：

```bash
grep -E 'UHD_(INCLUDE_DIRS|LIBRARIES)' build/CMakeCache.txt
ldd build/srsenb/src/srsenb | grep -E 'uhd|srsran_rf' || true
```

本方案直接运行 `build/` 中的程序，不要求安装 srsRAN 到系统。两台电脑的仓库根目录
都必须包含完整 `e200_demo/`，尤其是：

```text
e200_demo/enb.conf
e200_demo/ue.conf
e200_demo/epc.conf
e200_demo/user_db.csv
e200_demo/run_epc.sh
e200_demo/run_enb.sh
e200_demo/run_ue.sh
e200_demo/load_profile.sh
e200_demo/profiles/*.conf
e200_demo/profiles/sib_6prb.conf
```

检查脚本权限：

```bash
chmod +x e200_demo/run_epc.sh \
         e200_demo/run_enb.sh \
         e200_demo/run_ue.sh \
         e200_demo/load_profile.sh
```

`ue.conf` 中的 IMSI、K、OPc 必须与电脑 A 的 `user_db.csv` 完全一致。当前演示配置
已经匹配，复制文件时不要只复制其中一个。

## 8. PRB 和 profile 选择

当前 E200 profile 如下：

| 启动参数 | LTE 带宽 | PRB | 采样率 | E200 状态 |
| --- | ---: | ---: | ---: | --- |
| `6prb` | 1.4 MHz | 6 | 1.92 MSPS | 已验证 attach，internal |
| `6prb_external` | 1.4 MHz | 6 | 1.92 MSPS | 已验证 attach，共用 10 MHz |
| `15prb` | 3 MHz | 15 | 3.84 MSPS | 已验证 attach |
| `25prb` | 5 MHz | 25 | 5.76 MSPS | 已验证 attach |
| `50prb` | 10 MHz | 50 | 11.52 MSPS | 已验证 attach |
| `75prb` | 15 MHz | 75 | 15.36 MSPS | 已验证 attach 和 iperf3 |
| `100prb` | 20 MHz | 100 | 23.04 MSPS | 已验证 attach、ping、iperf3；满载仍需实时性调优 |

profile 会同时配置 PRB、采样率、SDR 地址、时钟源和 UE timing advance。E200 UE 的
`time_adv_nsamples=215` 是当前 strict-timestamp 管线的已验证固定补偿，不要按采样率
换算。6 PRB 必须使用 `profiles/sib_6prb.conf`，因为普通 SIB 的 PRACH offset 对
6 PRB 越界，启动脚本会自动选择正确 SIB。

除 `6prb_external` 外，现有通用 profile 默认都是 internal。若其他 PRB 也要使用公共
10 MHz，可在命令最后覆盖本机的完整 `device_args`。电脑 A 示例：

```bash
sudo ./e200_demo/run_enb.sh --profile 25prb \
  --rf.device_args=addr=192.168.1.10,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external
```

电脑 B 示例：

```bash
sudo ./e200_demo/run_ue.sh --profile 25prb \
  --rf.device_args=addr=192.168.10.2,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external
```

两端的 PRB、采样率、EARFCN 和时钟模式必须匹配。不要在一端选择 `25prb`、另一端
选择 `50prb`。

## 9. 第一次启动：6 PRB / internal

先停止可能占用设备的测试程序。严格按 EPC、eNB、UE 的顺序启动。

电脑 A 终端 1：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_epc.sh
```

电脑 A 终端 2：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_enb.sh --profile 6prb
```

电脑 B：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_ue.sh --profile 6prb
```

若两板已接同一个外部 10 MHz 源，将两端 `6prb` 都改为
`6prb_external`。E200 外部参考捕获通常需要约 17--18 秒，启动协议栈前应确认两板
最终均为 `ref_locked=true`。

成功时 UE 依次出现类似输出：

```text
Found Cell
Found PLMN
Random Access Complete
RRC Connected
Network attach successful. IP: 172.16.0.x
```

## 10. 切换到其他 PRB

先在电脑 B 退出 UE，再在电脑 A 退出 eNB；EPC 可以继续运行。然后两端选择同一个
profile。例如 50 PRB：

电脑 A：

```bash
sudo ./e200_demo/run_enb.sh --profile 50prb
```

电脑 B：

```bash
sudo ./e200_demo/run_ue.sh --profile 50prb
```

依次验证时建议采用以下顺序：

```text
6prb -> 15prb -> 25prb -> 50prb -> 75prb -> 100prb
```

100 PRB 除前述 `rmem` 参数外，建议把 CPU governor 设置为 performance，并降低
srsRAN 高频日志：

```bash
sudo cpupower frequency-set -g performance
```

启动 eNB、UE 时可在命令最后增加：

```text
--log.all_level=warning --log.rf_level=info
```

23.04 MSPS 的单向 SC16 IQ payload 约为 737 Mbit/s，加协议开销后接近千兆链路上限，
SDR 必须使用独占的千兆全双工链路。已验证 100 PRB 可 attach、ping 和双向 iperf3，
但持续满载仍可能出现少量 underflow 或 RRC 重建，不应把它作为首次部署验收档。

## 11. 数据面验证

UE attach 后，在电脑 B 检查 UE namespace 和 TUN：

```bash
sudo ip netns exec ue1 ip -br address show tun_srsue
sudo ip netns exec ue1 ip route show dev tun_srsue
sudo ip netns exec ue1 ping -c 10 172.16.0.1
```

记下 UE 控制台分配的地址，例如 `172.16.0.2`。电脑 A 反向测试：

```bash
ping -c 10 172.16.0.2
```

下行 iperf3，先在电脑 B 启动服务端：

```bash
sudo ip netns exec ue1 iperf3 -s -1 -B 172.16.0.2
```

再在电脑 A 启动客户端：

```bash
iperf3 -c 172.16.0.2 -B 172.16.0.1 -t 20 -O 2
```

上行 iperf3，先在电脑 A 启动服务端：

```bash
iperf3 -s -1 -B 172.16.0.1
```

再在电脑 B 启动客户端：

```bash
sudo ip netns exec ue1 \
  iperf3 -c 172.16.0.1 -B 172.16.0.2 -t 20 -O 2
```

UE 侧的 ping 和 iperf3 必须在 `ue1` namespace 中执行，否则 Linux 路由可能不能
正确代表 LTE 承载。

## 12. 日志与常见故障

默认日志：

```text
电脑 A：/tmp/e200_epc.log、/tmp/e200_enb.log
电脑 B：/tmp/e200_ue.log
```

检查 RF 实时错误：

```bash
grep -Ein 'underflow|overflow|late|timestamp|fatal|error' \
  /tmp/e200_enb.log /tmp/e200_ue.log
```

### UHD 找不到设备

- 先确认本机能 ping 本机连接的 E200；
- 确认 `libIQTaxiUHD.so` 在当前 UHD prefix 的 `lib/uhd/modules/`；
- 用 `ldd` 排除缺少 `libsdr_core.so` 或 `libsdr_driver.so`；
- 排除 `/usr` 与 `/usr/local` 两套 UHD ABI 混用；
- 确认没有另一个 probe、示例程序或 srsRAN 进程占用设备。

### UE 搜不到小区

- 两端必须使用同一个 PRB/profile、EARFCN 3350 和参考模式；
- 检查 eNB TX 到 UE RX 的射频链路、端口和衰减；
- 检查 E200 是否运行包含低采样率 FIR 修复的 server；
- 查看 UE 日志中的 CFO、RSRP 和 timestamp discontinuity。

### 找到小区但无法 attach

- 6 PRB 必须加载 `sib_6prb.conf`；
- E200 UE 必须使用 `time_adv_nsamples=215`；
- 检查 UE TX 到 eNB RX 的反向射频链路；
- 初始 RX gain 使用 40 dB，再根据信号质量调整。增益过大也会降低解调质量。

### attach 后 ping 不通

- 确认 UE 使用 `--gw.netns=ue1`；
- 使用 UE 控制台实际分配的 `172.16.0.x`；
- UE 侧从 `sudo ip netns exec ue1` 发起测试；
- 确认电脑 A 的 EPC 仍在运行且 `srs_spgw_sgi` 地址为 `172.16.0.1`。

## 13. 单电脑双网卡连接两台 E200

如果一台电脑有两个相互独立的千兆网卡，也可以在同一台电脑上同时运行 EPC、eNB
和 UE。这就是此前使用 `192.168.1.10` 和 `192.168.10.122` 两台 E200 的验证方式。
这种拓扑只需在该电脑上执行一次第 5--7 节的软件安装和编译。

### 13.1 拓扑和地址

```text
                         同一台 Ubuntu 电脑

  srsEPC + srsENB                              srsUE（netns: ue1）
          |                                             |
  网卡 1：192.168.1.100/24                    网卡 2：192.168.10.200/24
          |                                             |
  E200 eNB：192.168.1.10                      E200 UE：192.168.10.122
          |                                             |
          +------------- LTE Band 7 空口 ---------------+
```

两个 SDR 必须使用不同子网并分别连接独立物理网卡。不要把两个网卡做 bridge、bond，
也不要让默认路由从 SDR 网口发出。若两块板最初都是 `192.168.1.10`，一次只连接 UE
板，将它改为 `192.168.10.122`：

```bash
cd /home/wcc/vm_box/xilinx_image_builder
python3 scripts/e206_fw_tcp_update.py \
  --host 192.168.1.10 set-ip-addr 192.168.10.122
```

修改后重新上电，再同时连接两块 E200。

### 13.2 配置两个网卡

```bash
ip -br link

sudo ip link set <ENB_NIC> up
sudo ip address replace 192.168.1.100/24 dev <ENB_NIC>

sudo ip link set <UE_NIC> up
sudo ip address replace 192.168.10.200/24 dev <UE_NIC>

ping -c 3 192.168.1.10
ping -c 3 192.168.10.122

ip route get 192.168.1.10
ip route get 192.168.10.122

ethtool <ENB_NIC> | grep -E 'Speed|Duplex|Link detected'
ethtool <UE_NIC> | grep -E 'Speed|Duplex|Link detected'
```

两个 `ip route get` 应分别显示对应网卡，两条链路均应为千兆全双工。分别确认 UHD
能够发现设备：

```bash
uhd_find_devices --args 'addr=192.168.1.10'
uhd_find_devices --args 'addr=192.168.10.122'
```

### 13.3 在三个终端中启动

以 6 PRB / internal 为例。终端 1：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_epc.sh
```

终端 2，运行 eNB：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_enb.sh --profile 6prb
```

终端 3，运行 UE。现有通用 profile 的 UE 默认地址是 `192.168.10.2`，而
`run_ue.sh` 会在执行 srsUE 前先 ping 这个地址。这里直接启动 srsUE，并显式使用
`192.168.10.122`。第一次运行前创建 namespace；如果 `ue1` 已存在，不要重复执行
第一条命令：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ip netns add ue1
sudo env LD_LIBRARY_PATH=/home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G/build/lib/src/phy/rf \
  ./build/srsue/src/srsue ./e200_demo/ue.conf \
  --rf.time_adv_nsamples=215 \
  --rf.device_args=addr=192.168.10.122,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=internal,clock_source=internal \
  --gw.netns=ue1
```

使用公共外部 10 MHz 时，eNB 改为：

```bash
sudo ./e200_demo/run_enb.sh --profile 6prb_external
```

UE 改为：

```bash
sudo env LD_LIBRARY_PATH=/home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G/build/lib/src/phy/rf \
  ./build/srsue/src/srsue ./e200_demo/ue.conf \
  --rf.time_adv_nsamples=215 \
  --rf.device_args=addr=192.168.10.122,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external \
  --gw.netns=ue1
```

### 13.4 选择其他 PRB

两端仍要选择同一个 profile。以 50 PRB / internal 为例：

```bash
# 终端 2：eNB
sudo ./e200_demo/run_enb.sh --profile 50prb

# 终端 3：UE
sudo env LD_LIBRARY_PATH=/home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G/build/lib/src/phy/rf \
  ./build/srsue/src/srsue ./e200_demo/ue.conf \
  --rf.srate=11520000 \
  --rf.time_adv_nsamples=215 \
  --rf.device_args=addr=192.168.10.122,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=internal,clock_source=internal \
  --gw.netns=ue1
```

切换 `15prb`、`25prb`、`75prb` 或 `100prb` 时采用相同方法：eNB 使用所选
profile，UE 直接启动并将 `--rf.srate` 分别设为 `3840000`、`5760000`、
`15360000` 或 `23040000`。E200 UE 始终显式使用已验证的
`time_adv_nsamples=215`。

### 13.5 单电脑数据面验证

UE 必须继续使用 `ue1` network namespace。它可以防止同一台电脑上的 Linux local
route 绕过 LTE 空口，这是单电脑拓扑中的必要设置。

```bash
sudo ip netns exec ue1 ip -br address show tun_srsue
sudo ip netns exec ue1 ping -c 10 172.16.0.1
```

假设 UE 获得 `172.16.0.2`，默认 namespace 中反向测试：

```bash
ping -c 10 172.16.0.2
```

iperf3 的运行方式与第 11 节相同：UE 一侧命令放在 `ue1` 中，EPC 一侧命令在默认
namespace 中执行。

### 13.6 单电脑性能注意事项

一台电脑需要同时处理两条 IQ 数据流、EPC、eNB 和 UE，负载明显高于双电脑方式。
尤其在 75/100 PRB 下，应：

- 确保两个 SDR 各占一个千兆全双工网卡；
- 使用第 4 节的 `rmem` 和 backlog 设置；
- 将 CPU governor 设置为 performance；
- 用 `--log.all_level=warning --log.rf_level=info` 降低实时日志负载；
- 关闭无关的高负载程序，并检查两个网卡的 drop/error；
- 100 PRB 出现 underflow、overflow 或 RRC 重建时，先降低到 75 PRB 建立基线。

## 14. 停止顺序

先用 `Ctrl-C` 停止 UE，再停止 eNB，最后停止 EPC。双电脑时分别在对应电脑操作；
单电脑时按三个终端的相同顺序操作。若异常退出后重新测试，可清理旧 namespace：

```bash
sudo ip netns delete ue1
```

只有确认没有 srsUE 正在使用 `ue1` 时才执行删除。
