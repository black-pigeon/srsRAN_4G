# 两台电脑、两台 E206 搭建 srsRAN_4G

本文说明如何在两台 Ubuntu 电脑上分别连接一台 E206，搭建 LTE FDD
srsRAN_4G。电脑 A 运行 EPC 和 eNB，电脑 B 运行 UE。E206 使用 GC080X/MP2021
射频前端，和 E200 的 AD9361 前端不同，因此不能直接照搬 E200 的所有 timing
advance、增益解释和低采样率结论。

当前 E206 上下位机已经支持 srsRAN_4G 所需的六个原生 LTE 采样率。本文给出可直接
执行的部署方式，同时明确哪些结论是采样率/IQ 链路验证，哪些是已有的空口 attach
验证，避免把 E206+E200 混合测试误写成双 E206 全档稳定性结论。

## 1. 拓扑和地址约定

```text
电脑 A（EPC + eNB）                         电脑 B（UE）

srsEPC + srsENB                             srsUE（netns: ue1）
        |                                            |
SDR 网口 192.168.1.100/24                   SDR 网口 192.168.10.200/24
        |                                            |
E206 192.168.1.10                           E206 192.168.10.2
        |                                            |
        +------------ LTE Band 7 空口 ---------------+
```

两台电脑可以另接管理网络用于 SSH。EPC 和 eNB 均在电脑 A，因此
`e200_demo/enb.conf` 里的 S1/MME 回环地址保持不变。虽然目录名仍为
`e200_demo`，其中的 srsRAN 配置和启动包装脚本也可用于 E206；E206 特有参数由本文
命令行在 profile 之后覆盖。

本文使用当前实验室路径：

```text
/home/wcc/vm_box/xilinx_image_builder
/home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
```

两台电脑必须使用同一版本的 E206 rootfs/server、FPGA、IQTAXI、UHD、srsRAN_4G
和配置文件。

## 2. 硬件、外部参考和射频安全

准备以下硬件：

- 两台带独立千兆 SDR 网口的 Ubuntu 电脑；
- 两台已经更新到当前 E206 SD 镜像的设备；
- 两条安全的射频链路和足够衰减，或合规屏蔽环境；
- 推荐：同一个外部 10 MHz 参考源的两路输出。

Band 7 是许可频段，只能在屏蔽环境或获得授权时发射。线缆直连必须使用两条单向
链路：

```text
eNB TX -> 衰减器 -> UE RX
UE TX  -> 衰减器 -> eNB RX
```

禁止 TX 不经衰减直连 RX。使用 external 时，两台 E206 必须接到同一个 10 MHz
参考源；10 MHz 只统一频率，本例 attach 不要求公共 PPS。第一次排除外部参考问题时
也可以使用 internal，但双 E206 正式对测推荐 external。

## 3. 检查 E206 固件和板端服务

E206 的 SSH 用户和密码均为 `root`。每台电脑检查其本机设备：

```bash
ping -c 3 <E206-IP>
ssh root@<E206-IP>
cat /etc/e206-build-info
/etc/init.d/S46init-mp2021 status
sha256sum /usr/sbin/e206_v25_server
tail -n 100 /var/log/e206_v25_server.log
```

当前已固化版本的参考信息：

```text
rootfs build: 22cda948-dirty
e206_v25_server SHA256:
fccf06d0598656bf681c80d565f755b703d8f6a436c63c76a6cbff98eb044246
```

交付镜像重新构建后 build ID 或哈希可能变化，关键是两台板必须来自同一已验证镜像，
服务自动启动且 ready。当前程序已经去掉 halfband 行为，并支持运行时切换：

```text
1.92 / 3.84 / 5.76 / 7.68 / 11.52 /
15.36 / 23.04 / 30.72 / 61.44 / 122.88 MSPS
```

以上十档的“切换和回读”已验证；这不等价于双 E206 在十档下都已经完成 srsRAN
attach。

为直接使用现有启动脚本，建议将电脑 B 的 UE 板持久化为 `192.168.10.2`。只连接
该板时，在工程根目录执行：

```bash
python3 scripts/e206_fw_tcp_update.py \
  --host 192.168.1.10 set-ip-addr 192.168.10.2
```

修改后重新上电。若保留默认 `192.168.1.10`，两台设备位于不同电脑也不会冲突。
此时不能只覆盖 `run_ue.sh` 的 `device_args`，因为脚本会先 ping profile 默认地址；
应像第 16 节一样直接启动 `srsue`，或使用同时修改了 `E200_UE_ADDR` 的自定义
profile。

## 4. 配置两台电脑的 SDR 网口

用 `ip -br link` 找到实际接口名。

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

两条链路都必须是 `1000Mb/s`、`Full`。不要清空承载远程 SSH 的网口地址。需要永久
配置时，使用 NetworkManager 或 netplan 保存上述地址。

两台电脑建议设置：

```bash
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.rmem_default=16777216
sudo sysctl -w net.core.netdev_max_backlog=10000
```

## 5. 安装 UHD

电脑 A、电脑 B 都要执行。IQTAXI UHD module 必须与运行时 UHD ABI 一致。当前验证
环境是 UHD `4.9.0.0-11-gcf78e1cf`，prefix 为 `/usr/local`。

检查现有 UHD：

```bash
which uhd_config_info
uhd_config_info --version
uhd_config_info --install-prefix
ldconfig -p | grep libuhd
```

若需要复现 UHD 4.9：

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

如果采用系统包 UHD，也必须用该版本重新编译下一节 IQTAXI 和第 8 节 srsRAN。

## 6. 安装 IQTAXI 驱动

E200 与 E206 共用同一个主机工程，但运行时会根据设备信息选择 E206 实现。两台电脑
都执行：

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

IQTAXI 安装产物：

```text
/usr/local/lib/libsdr_core.so
/usr/local/lib/libsdr_driver.so
```

## 7. 安装并验证 IQTAXI UHD 插件

上一节的同一次 `cmake --install` 已经安装 UHD 动态插件，不需要手工复制：

```text
/usr/local/lib/uhd/modules/libIQTaxiUHD.so
```

如果 UHD prefix 不是 `/usr/local`，实际目录以 CMake 输出的 `UHD root directory`
为准。

正常的驱动版本链接应为：

```text
libsdr_driver.so -> libsdr_driver.so.1
libsdr_driver.so.1 -> libsdr_driver.so.1.0.0
```

检查：

```bash
ls -l /usr/local/lib/libsdr_driver.so*
ls -l /usr/local/lib/libsdr_core.so*
ldd /usr/local/lib/uhd/modules/libIQTaxiUHD.so | grep 'not found' || true
```

如果 `ldconfig` 提示 `libsdr_driver.so 不是符号链接`，不要继续手工复制 `.so`。
先确认无版本名称的文件确实是普通文件，再改名保留并重新安装：

```bash
sudo mv /usr/local/lib/libsdr_driver.so \
  /usr/local/lib/libsdr_driver.so.pre-iqtaxi-install
sudo cmake --install build
sudo ldconfig
```

电脑 A 发现设备：

```bash
uhd_find_devices --args 'addr=192.168.1.10'
uhd_usrp_probe --args 'addr=192.168.1.10'
```

电脑 B：

```bash
uhd_find_devices --args 'addr=192.168.10.2'
uhd_usrp_probe --args 'addr=192.168.10.2'
```

预期信息：

```text
name: ANTSDR-E206
product: E206
type: iqtaxi
```

使用 external 参考时，还应从 probe 输出确认 `ref_locked=true`。不要在 srsRAN 正占用
设备时 probe。接好公共 10 MHz 后，每台电脑可执行：

```bash
uhd_usrp_probe \
  --args 'addr=<本机E206-IP>,clock=external,clock_source=external'
```

可选的 RX IQ 链路测试：

```bash
cd /home/wcc/vm_box/xilinx_image_builder/host_app/e200/MICROPHASE_IQ_TAXI
./build/src/example/e206_iq_example \
  --addr <本机E206-IP> \
  --mode rx \
  --duration 10 \
  --sample-rate 15360000 \
  --rx-lo 2680000000 \
  --rx-gain 20 \
  --rx-request 4096
```

应看到 `PASS`，且没有接收错误、timestamp gap、wire sequence error 或 host drop。

## 8. 构建 srsRAN_4G

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

确认 srsRAN 使用正确 UHD：

```bash
grep -E 'UHD_(INCLUDE_DIRS|LIBRARIES)' build/CMakeCache.txt
ldd build/srsenb/src/srsenb | grep -E 'uhd|srsran_rf' || true
```

两台电脑都必须有完整 `e200_demo/` 配置目录：

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

确保脚本可执行：

```bash
chmod +x e200_demo/run_epc.sh \
         e200_demo/run_enb.sh \
         e200_demo/run_ue.sh \
         e200_demo/load_profile.sh
```

电脑 B 的 `ue.conf` soft-USIM 参数必须与电脑 A 的 `user_db.csv` 一致。当前
`e200_demo` 已经匹配，不要分别从不同版本复制。

## 9. E206 的 PRB、采样率与 timing advance

srsRAN_4G 原生 LTE 映射如下：

| profile | LTE 带宽 | PRB | 原生采样率 | E206 支持 |
| --- | ---: | ---: | ---: | --- |
| `6prb` / `6prb_external` | 1.4 MHz | 6 | 1.92 MSPS | 支持；eNB 需特殊补偿 |
| `15prb` | 3 MHz | 15 | 3.84 MSPS | 支持 |
| `25prb` | 5 MHz | 25 | 5.76 MSPS | 支持 |
| `50prb` | 10 MHz | 50 | 11.52 MSPS | 支持 |
| `75prb` | 15 MHz | 75 | 15.36 MSPS | 支持 |
| `100prb` | 20 MHz | 100 | 23.04 MSPS | 支持；主机实时性要求最高 |

当前已验证的 E206 角色参数：

- E206 作为 UE，在 1.92/3.84/5.76/11.52 MSPS 下使用
  `rf.time_adv_nsamples=255` 已分别完成 attach；
- E206 作为 eNB，在 3.84/5.76/11.52 MSPS 下使用
  `rf.time_adv_nsamples=0` 已分别完成 attach；
- E206 作为 eNB、1.92 MSPS 时，实测专用补偿为
  `rf.time_adv_nsamples=49`；
- 6 PRB 强制使用 15.36 MSPS 是已验证过的兼容回退方向；
- 上述角色验证多数由 E206 与已验证 E200 对测完成。双 E206 应按本文顺序重新完成
  每档 attach、ping 和吞吐验收，不能只凭采样率回读认定全部业务稳定。

现有 `e206_enb_15prb`、`e206_enb_25prb`、`e206_enb_50prb` profile 是专门给
“E206 eNB + E200 UE（UE 采用 2 倍采样率）”的混合测试配置，双 E206 不要选择它们。
双 E206 应使用上表的通用 profile，并按下文覆盖 E206 timing advance。

6 PRB 必须保留 `profiles/sib_6prb.conf`。`run_enb.sh --profile 6prb...` 会自动选择
该 SIB。

## 10. 推荐首次验收：15 PRB / 3.84 MSPS / external

推荐先从 15 PRB 原生采样率开始，因为 E206 的 eNB 和 UE 两种角色都已有独立 attach
记录。先确认两台 E206 已连接同一个 10 MHz 源并锁定。

按 EPC、eNB、UE 的顺序启动。

电脑 A 终端 1：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_epc.sh
```

电脑 A 终端 2：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_enb.sh --profile 15prb \
  --rf.srate=3840000 \
  --rf.time_adv_nsamples=0 \
  --rf.device_args=addr=192.168.1.10,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external
```

电脑 B：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_ue.sh --profile 15prb \
  --rf.srate=3840000 \
  --rf.time_adv_nsamples=255 \
  --rf.device_args=addr=192.168.10.2,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external
```

命令末尾的 E206 参数会覆盖通用 profile 中的 E200 默认 timing advance。不要省略
UE 的 `255`，也不要直接采用 profile 内的 E200 `215`。

成功标志：

```text
Found Cell
Found PLMN
Random Access Complete
RRC Connected
Network attach successful. IP: 172.16.0.x
```

## 11. 验证 6 PRB

### 11.1 原生 1.92 MSPS

电脑 A 保持 EPC 运行，启动 E206 eNB：

```bash
sudo ./e200_demo/run_enb.sh --profile 6prb_external \
  --rf.srate=1920000 \
  --rf.time_adv_nsamples=49
```

电脑 B：

```bash
sudo ./e200_demo/run_ue.sh --profile 6prb_external \
  --rf.srate=1920000 \
  --rf.time_adv_nsamples=255
```

`49` 是 E206 eNB 在 1.92 MSPS 下校准得到的 TX/RX 相对时延补偿；它不是 E206 UE
补偿，也不能写回所有 PRB 共用的 `enb.conf`。

### 11.2 15.36 MSPS 回退方案

若只要求先稳定调通 6 PRB，可让 LTE 带宽仍为 6 PRB，但两端硬件采样率都强制为
15.36 MSPS：

电脑 A：

```bash
sudo ./e200_demo/run_enb.sh --profile 6prb_external \
  --rf.srate=15360000 \
  --rf.time_adv_nsamples=0
```

电脑 B：

```bash
sudo ./e200_demo/run_ue.sh --profile 6prb_external \
  --rf.srate=15360000 \
  --rf.time_adv_nsamples=255
```

这是 6 PRB 的兼容方案，不代表 LTE 带宽变成 75 PRB。srsRAN 会在 15.36 MSPS
硬件流上处理 6 PRB 基带。两端必须设置同一个强制采样率。

## 12. 验证其他 PRB

每次切换前先停止 UE，再停止 eNB；EPC 可以继续运行。通用命令模式如下。

电脑 A：

```bash
sudo ./e200_demo/run_enb.sh --profile <PROFILE> \
  --rf.srate=<SAMPLE_RATE_HZ> \
  --rf.time_adv_nsamples=0 \
  --rf.device_args=addr=192.168.1.10,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external
```

电脑 B：

```bash
sudo ./e200_demo/run_ue.sh --profile <PROFILE> \
  --rf.srate=<SAMPLE_RATE_HZ> \
  --rf.time_adv_nsamples=255 \
  --rf.device_args=addr=192.168.10.2,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external
```

替换表：

| `<PROFILE>` | `<SAMPLE_RATE_HZ>` |
| --- | ---: |
| `15prb` | `3840000` |
| `25prb` | `5760000` |
| `50prb` | `11520000` |
| `75prb` | `15360000` |
| `100prb` | `23040000` |

建议验证顺序：

```text
15prb -> 25prb -> 50prb -> 75prb -> 100prb
```

每一档都记录 Found Cell、CFO、PRACH offset、attach、ping、上下行吞吐以及
underflow/overflow。不要跨过中间档直接把“设备能切到 23.04 MSPS”当成 100 PRB
空口已验收。

100 PRB 时建议两台电脑执行：

```bash
sudo cpupower frequency-set -g performance
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.rmem_default=16777216
sudo sysctl -w net.core.netdev_max_backlog=10000
```

并在 srsRAN 命令末尾增加：

```text
--log.all_level=warning --log.rf_level=info
```

23.04 MSPS 的单向 SC16 IQ payload 约 737 Mbit/s，必须使用独占千兆全双工 SDR
链路。E206 的 23.04 MSPS 切换和 IQ 流已具备，但双 E206 100 PRB 的持续满载稳定性
仍应作为单独验收项。

## 13. 数据面验证

UE attach 后，在电脑 B：

```bash
sudo ip netns exec ue1 ip -br address show tun_srsue
sudo ip netns exec ue1 ip route show dev tun_srsue
sudo ip netns exec ue1 ping -c 10 172.16.0.1
```

假设 UE 实际获得 `172.16.0.2`，电脑 A 反向 ping：

```bash
ping -c 10 172.16.0.2
```

下行 iperf3，电脑 B：

```bash
sudo ip netns exec ue1 iperf3 -s -1 -B 172.16.0.2
```

电脑 A：

```bash
iperf3 -c 172.16.0.2 -B 172.16.0.1 -t 20 -O 2
```

上行 iperf3，电脑 A：

```bash
iperf3 -s -1 -B 172.16.0.1
```

电脑 B：

```bash
sudo ip netns exec ue1 \
  iperf3 -c 172.16.0.1 -B 172.16.0.2 -t 20 -O 2
```

UE 地址以控制台实际输出为准。UE 一侧必须在 `ue1` namespace 中测试。

## 14. 增益调整

当前配置以 eNB `tx_gain=89`、`rx_gain=40`，UE `tx_gain=79`、`rx_gain=40` 作为
起点。E206 射频前端和 E200 不同，不要把 E200 的 AD9361 attenuation 公式直接套到
E206。

若 eNB 上行 SNR 低，不要只增加 eNB RX gain。输入过强会压缩或饱和，反而降低 SNR
和 PUSCH 解调质量。建议一次只改 2--3 dB，在固定衰减和距离下同时记录：

- eNB 控制台 UL SNR、PUSCH BLER；
- UE 控制台 DL SNR、RSRP；
- attach 是否重建以及 underflow/overflow；
- 上、下行 iperf3 吞吐。

优先通过衰减器建立足够但不过载的链路余量，再分别微调 RX gain 和 TX gain。

## 15. 日志与故障定位

默认日志位置：

```text
电脑 A：/tmp/e200_epc.log、/tmp/e200_enb.log
电脑 B：/tmp/e200_ue.log
```

虽然文件名保留 `e200`，运行设备可通过日志开头的 UHD product 确认是 E206。检查：

```bash
grep -Ein 'underflow|overflow|late|timestamp|fatal|error' \
  /tmp/e200_enb.log /tmp/e200_ue.log
```

### UHD 找不到 E206

- 确认本机能 ping 本机 E206；
- `uhd_find_devices` 应显示 `product: E206`，不是 E200；
- 确认 UHD module 和运行时 UHD ABI 一致；
- 用 `ldd` 排除 IQTAXI 依赖缺失；
- 确认没有其他程序占用设备。

### external 参考未锁定

- 确认两板确实接入同一个 10 MHz 源且电平合适；
- 用 `uhd_usrp_probe` 检查 `reference_valid`、`reference_is_10mhz` 和
  `ref_locked`；
- 未锁定前不要启动 eNB/UE；
- 可先把两端都改为 internal，区分参考链路与空口配置问题。

### UE 找不到小区

- 两端 PRB、采样率、EARFCN 3350 和 clock source 必须一致；
- 检查 eNB TX 到 UE RX 的端口、线缆和衰减；
- 单独运行 `e206_iq_example --mode rx`，排除 IQ 接收链路错误；
- 查看 UE CFO、RSRP 和 timestamp gap。

### 能找到小区但 PRACH/attach 失败

- E206 UE 应显式使用 `time_adv_nsamples=255`；
- E206 eNB 在 1.92 MSPS 使用 `49`，其他本文档位先使用 `0`；
- 6 PRB 必须使用 `sib_6prb.conf`；
- 检查 UE TX 到 eNB RX 的反向射频链路；
- 在不同 RX gain 下比较 SNR/BLER，避免输入过载。

### 1.92 MSPS 仍不稳定

- 先确认板上运行的是当前固化 server，而不是 `/tmp` 中的临时旧程序；
- 确认没有 halfband 旧逻辑；
- 确认 eNB 使用 `49`、UE 使用 `255`；
- 对比 6 PRB / 15.36 MSPS 回退方案；
- 分别做单向 TX/RX IQ 测试，区分 E206 发送链路、接收链路和 srsRAN 时序问题。

### attach 后 ping 不通

- 确认电脑 A 的 EPC 仍在运行；
- 确认电脑 B 使用 `--gw.netns=ue1`；
- 使用实际分配的 UE 地址；
- UE 侧从 `sudo ip netns exec ue1` 发起测试。

## 16. 单电脑双网卡连接两台 E206

一台电脑有两个独立千兆网卡时，也可以让两个网卡分别连接一台 E206，在同一台电脑
运行 EPC、eNB 和 UE。地址沿用此前双 SDR 验证方式。这种拓扑只需在该电脑上执行
一次第 5--8 节的软件安装和编译：

```text
                         同一台 Ubuntu 电脑

  srsEPC + srsENB                              srsUE（netns: ue1）
          |                                             |
  网卡 1：192.168.1.100/24                    网卡 2：192.168.10.200/24
          |                                             |
  E206 eNB：192.168.1.10                      E206 UE：192.168.10.122
          |                                             |
          +------------- LTE Band 7 空口 ---------------+
```

两个 SDR 必须位于不同子网，分别使用独立物理网卡。不要 bridge 或 bond 两个 SDR
网口。若两台 E206 初始地址相同，一次只连接 UE 板并设置持久地址：

```bash
cd /home/wcc/vm_box/xilinx_image_builder
python3 scripts/e206_fw_tcp_update.py \
  --host 192.168.1.10 set-ip-addr 192.168.10.122
```

修改后重新上电，再连接两台设备。

### 16.1 配置和检查双网卡

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

uhd_find_devices --args 'addr=192.168.1.10'
uhd_find_devices --args 'addr=192.168.10.122'
```

路由必须分别指向两个正确网卡，两条链路都应为千兆全双工，UHD 应将两台设备都识别
为 `product: E206`。

### 16.2 推荐起点：15 PRB / 3.84 MSPS / external

确认两台 E206 连接同一个 10 MHz 源并锁定。打开三个终端，严格按顺序启动。

终端 1：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_epc.sh
```

终端 2，E206 eNB：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_enb.sh --profile 15prb \
  --rf.srate=3840000 \
  --rf.time_adv_nsamples=0 \
  --rf.device_args=addr=192.168.1.10,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external
```

终端 3，E206 UE。第一次启动前创建 `ue1`；如果 namespace 已存在，不要重复执行
第一条命令：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ip netns add ue1
sudo env LD_LIBRARY_PATH=/home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G/build/lib/src/phy/rf \
  ./build/srsue/src/srsue ./e200_demo/ue.conf \
  --rf.srate=3840000 \
  --rf.time_adv_nsamples=255 \
  --rf.device_args=addr=192.168.10.122,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external \
  --gw.netns=ue1
```

现有 profile 的 UE 地址是 `192.168.10.2`、timing advance 是 E200 的 `215`，而
包装脚本还会预先 ping profile 地址；因此单电脑 E206 UE 使用上述直接启动方式，
`192.168.10.122` 和 `255` 都不能省略。

### 16.3 单电脑验证 6 PRB

原生 1.92 MSPS，E206 eNB 使用 `49`，E206 UE 使用 `255`：

```bash
# 终端 2：eNB
sudo ./e200_demo/run_enb.sh --profile 6prb_external \
  --rf.srate=1920000 \
  --rf.time_adv_nsamples=49 \
  --rf.device_args=addr=192.168.1.10,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external

# 终端 3：UE
sudo env LD_LIBRARY_PATH=/home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G/build/lib/src/phy/rf \
  ./build/srsue/src/srsue ./e200_demo/ue.conf \
  --rf.srate=1920000 \
  --rf.time_adv_nsamples=255 \
  --rf.device_args=addr=192.168.10.122,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external \
  --gw.netns=ue1
```

若 1.92 MSPS 仍不稳定，可将两端 `--rf.srate` 同时改为 `15360000`，并将 eNB
`--rf.time_adv_nsamples` 改为 `0`，使用第 11.2 节的 6 PRB 回退方案。

### 16.4 切换其他 PRB

沿用第 12 节的 profile 和采样率表。每次都显式指定：

```text
eNB addr=192.168.1.10，time_adv_nsamples=0
UE  addr=192.168.10.122，time_adv_nsamples=255
```

例如 50 PRB：

```bash
# 终端 2：eNB
sudo ./e200_demo/run_enb.sh --profile 50prb \
  --rf.srate=11520000 \
  --rf.time_adv_nsamples=0 \
  --rf.device_args=addr=192.168.1.10,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external

# 终端 3：UE
sudo env LD_LIBRARY_PATH=/home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G/build/lib/src/phy/rf \
  ./build/srsue/src/srsue ./e200_demo/ue.conf \
  --rf.srate=11520000 \
  --rf.time_adv_nsamples=255 \
  --rf.device_args=addr=192.168.10.122,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external \
  --gw.netns=ue1
```

### 16.5 namespace 和数据面

同一电脑运行 EPC 和 UE 时，`ue1` namespace 是必要的，否则 Linux local route
可能绕过 LTE 承载。attach 后执行：

```bash
sudo ip netns exec ue1 ip -br address show tun_srsue
sudo ip netns exec ue1 ping -c 10 172.16.0.1
```

假设 UE 获得 `172.16.0.2`，默认 namespace 反向测试：

```bash
ping -c 10 172.16.0.2
```

iperf3 仍按第 13 节执行：UE 一侧命令放在 `ue1`，EPC 一侧命令放在默认
namespace。

### 16.6 单电脑负载限制

同一电脑同时承担两个高速 IQ 流、EPC、eNB 和 UE。75/100 PRB 时比双电脑拓扑更
容易出现调度延迟：

- 两台 E206 必须各自独占一个千兆全双工网卡；
- 使用第 4、12 节的 rmem、backlog、performance governor 和低日志设置；
- 检查两个网卡的 RX/TX drop、内核 `RcvbufErrors` 和 srsRAN RF 错误；
- 100 PRB / 23.04 MSPS 出现 underflow、overflow 或 RRC 重建时，先退回 75 PRB；
- 单电脑能完成 attach 不代表满载实时性一定优于双电脑，最终吞吐应单独记录。

## 17. 停止顺序和验收记录

先停止 UE，再停止 eNB，最后停止 EPC。双电脑时分别在两台电脑操作；单电脑时按
三个终端的相同顺序操作。异常退出且确定没有 UE 进程后，可以清理 namespace：

```bash
sudo ip netns delete ue1
```

建议每个 PRB 至少保存以下验收结果：

```text
设备 build-info 和 server SHA256
UHD 版本、IQTAXI module SHA256
PRB、实际采样率、clock source、ref_locked
eNB/UE timing advance、TX/RX gain
attach 成功时间、UE IP
上下行 ping 丢包率、iperf3 吞吐
underflow、overflow、timestamp gap 计数
```

这样可以把“采样率可切换”“单角色已 attach”和“双 E206 业务稳定”三个层次清楚地区分。
