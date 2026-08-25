# E200 IQTAXI + srsRAN_4G 从零部署指南

本文面向需要在一台 Ubuntu 主机上使用两块 E200，通过 IQTAXI/UHD 运行
srsRAN_4G LTE eNB、UE 和 EPC 的开发者。目标是完成小区搜索、PRACH、RRC、
EPC attach、默认承载建立以及双向 IP 通信。

## 1. 结论与软件边界

srsRAN_4G 的 tracked 源码不需要修改。E200 适配分为两部分：

1. 在系统 UHD 的模块目录安装 IQTAXI UHD module，以及它依赖的
   `libsdr_core.so`、`libsdr_driver.so`；
2. 在 srsRAN_4G 仓库中增加 `e200_demo/` 配置、PRB profile 和启动脚本。

因此“无需修改 srsRAN 源码”是正确的，但不能理解为“只复制 conf 文件即可”。
没有安装 IQTAXI/UHD module 时，stock srsRAN 无法识别 E200。

本次验证的 srsRAN tracked 源码为：

```text
branch: master
commit: ec29b0c1ff79
tracked source diff: empty
```

## 2. 已验证拓扑

```text
                         同一台 Ubuntu 主机

  srsENB + srsEPC                              srsUE (gw.netns=ue1)
         |                                                |
  NIC 192.168.1.100/24                         NIC 192.168.10.200/24
         |                                                |
  E200 eNB 192.168.1.10                         E200 UE 192.168.10.2
         |                                                |
         +------------- LTE Band 7 空口 ------------------+
```

已完整验证的 6 PRB 参数：

| 项目 | 值 |
| --- | --- |
| LTE band / EARFCN | Band 7 / 3350 |
| 带宽 | 6 PRB / 1.4 MHz |
| 采样率 | 1.92 MSps |
| MIMO | SISO，单端口 |
| eNB TX / RX gain | 89 / 40 dB |
| UE TX / RX gain | 79 / 40 dB |
| TX timestamp | strict，`ignore_tx_timestamps=false` |
| UE timing advance | `time_adv_nsamples=215` |
| 参考源 | internal 和公共 external 10 MHz 均已验证 |

`time_adv_nsamples=215` 是 E200 FPGA/packet pipeline 的固定样点补偿。当前所有
PRB profile 都使用该值，不需要按采样率手工换算。`6prb_adv66` 仅保留为历史
对照，不是成功基线。

## 3. 硬件和射频安全

需要：

- 两块 E200；
- 主机两个独立千兆以太网口；
- 两条安全的射频链路或合规的近距离天线环境；
- 可选：一个公共 10 MHz 参考源和两路参考输出。

Band 7 属于许可频段，只能在屏蔽环境或获得授权的条件下发射。使用射频线
直连时必须使用两条单向链路并加入足够衰减：

```text
eNB TX -> 衰减器 -> UE RX
UE TX  -> 衰减器 -> eNB RX
```

禁止将 TX 不经衰减直接连接 RX。

## 4. 构建 E200 FPGA、下位机和 SD 镜像

### 4.1 工程位置

```bash
git clone https://github.com/black-pigeon/xilinx_image_builder.git
cd xilinx_image_builder
```

本次镜像基于 `dfone_2022.2` 分支的 `c2e0dcb0e034`，并包含尚待提交的
1.92 MSps FIR128 修复。交付给其他人之前，必须先将
`board/e200/init_ad9361_e200/e200_v25_server.c` 的修复提交并推送；否则仅从
当前远端 commit clone 不能得到本文验证的 server。

需要使用包含以下功能的版本：

- FPGA strict timed TX、SOB/EOB、ACK 和 async timestamp；
- IQTAXI/UHD native tick timestamp；
- E200 低采样率 FIR 切换；
- 1.92 MSps 使用 128-tap 对称 RX/TX FIR；
- 3.84/5.76/7.68 MSps 使用 96-tap RX FIR、TX FIR bypass。

1.92 MSps FIR 修复位于：

```text
board/e200/init_ad9361_e200/e200_v25_server.c
```

### 4.2 FPGA 产物

镜像构建读取：

```text
hdl/antsdr_e200/artifacts/e200_iqtaxi/e200_iqtaxi.xsa
hdl/antsdr_e200/artifacts/e200_iqtaxi/e200_iqtaxi.bit
```

如果 FPGA 没有变化，可直接使用仓库中已经验证的 artifact。修改 FPGA 后，
使用 Vivado 2022.2 重新生成并导出：

```bash
source scripts/xilinx-settings.sh
hdl/antsdr_e200/scripts/export_e200_iqtaxi_artifacts.sh --rebuild
```

### 4.3 生成 SD 文件和更新包

第一次构建需要 Vivado/Vitis 2022.2、Buildroot 工具链及仓库要求的上游源码。
查看配置并构建：

```bash
make show-config BOARD=e200
make firmware-sd-frm BOARD=e200
```

如果只修改了 `e200_v25_server`，但 Make 没有触发本地包重建，删除下面这个
Buildroot 生成的空 stamp 后再构建：

```text
buildroot-xilinx/output/e200/.local-package-e200-init-ad9361.stamp
```

输出为：

```text
build/e200/sd/BOOT.BIN
build/e200/sd/zImage
build/e200/sd/devicetree.dtb
build/e200/sd/rootfs.cpio.gz
build/e200/sd/uEnv.txt
build/e200/sd/e200_iqtaxi.bit
build/e200/sd/e200-firmware.manifest
build/e200/firmware/e200-sd.frm
```

本次构建产物：

| 产物 | SHA256 |
| --- | --- |
| rootfs 内 `/usr/sbin/e200_v25_server` | `436172dce148924d6bbe67a915b98c9b4e53da80baf94f582d792dbabd94e80e` |
| `e200_iqtaxi.bit` | `c8d44d13bbbe28f262c0394295ac4418fe0a223ea755196d1adaa2794dd83744` |
| `rootfs.cpio.gz` | `a530a0c2481a250ac20906158739e22089d8e4ed85f56dc4802bc650d8183bf8` |
| `e200-sd.frm` | `fec1cf13d2fd261018f10140cf9c2433f9a803c8bdf1baef2421b966221e7ee8` |

firmware manifest 包含 Git dirty 状态和生成时间；提交源码后重新构建会改变
manifest 和 `.frm` 的哈希，这是正常现象。

## 5. 部署 SD 镜像

### 5.1 直接写入现有 SD BOOT 分区

先备份 SD 卡，然后将 `build/e200/sd/` 中的文件复制到 FAT BOOT 分区并
安全卸载：

```bash
sudo cp build/e200/sd/* /media/$USER/<BOOT分区>/
sync
sudo umount /media/$USER/<BOOT分区>
```

确认拨码选择 SD 启动，再给 E200 重新上电。

### 5.2 已有更新服务时在线更新

```bash
python3 scripts/e206_fw_tcp_update.py \
  --host 192.168.1.10 \
  update --mode sd build/e200/firmware/e200-sd.frm --reboot
```

对 UE 板使用它当前的管理地址重复执行。E200 只更新 SD，不要使用 QSPI
firmware update。

### 5.3 为两块默认同地址设备分配不同 IP

两块新设备默认都是 `192.168.1.10`，必须一次只连接一块。先给 UE 设置不同
的持久化 MAC 和 IP：

```bash
python3 scripts/e206_fw_tcp_update.py \
  --host 192.168.1.10 set-mac-addr E0:78:A3:00:00:22

python3 scripts/e206_fw_tcp_update.py \
  --host 192.168.1.10 set-ip-addr 192.168.10.2
```

重新上电后，server 会把持久化配置同时应用到 Linux `eth0` 和 FPGA UOE。
检查：

```bash
python3 scripts/e206_fw_tcp_update.py --host 192.168.10.2 uoe-netcfg
```

### 5.4 板端校验

Buildroot 默认 SSH 用户和密码均为 `root`。两块板分别检查：

```bash
ssh root@<E200-IP>
/etc/init.d/S46init-ad9361 status
sha256sum /usr/sbin/e200_v25_server
cat /var/log/e200_v25_server.log
```

server 应自动运行，哈希应与所部署 rootfs 中的产物一致。

## 6. 构建并安装 IQTAXI/UHD 上位机

### 6.1 UHD ABI 要求

IQTAXI 是 UHD 动态 module，编译时和运行时必须使用同一套 UHD ABI。当前
验证环境为：

```text
UHD 4.9.0.0-11-gcf78e1cf
install prefix: /usr/local
```

可用 `uhd_config_info --version` 和 `uhd_config_info --install-prefix` 检查。
如果系统同时存在 `/usr` 和 `/usr/local` 两套 UHD，先解决 CMake、动态库和
命令行工具混用问题。

要复现当前 UHD 主版本，可从官方 tag 构建到 `/usr/local`：

```bash
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

也可以使用发行版的 `libuhd-dev`/`uhd-host`，但 IQTAXI module 与 srsRAN
必须全部针对该版本重新构建，不能复用另一 UHD ABI 的 `.so`。

### 6.2 依赖与构建

Ubuntu 22.04 示例依赖：

```bash
sudo apt update
sudo apt install -y \
  build-essential cmake pkg-config \
  libboost-all-dev libsoapysdr-dev \
  libgl1-mesa-dev libglfw3-dev libglew-dev
```

构建并安装：

```bash
cd xilinx_image_builder/host_app/e200/MICROPHASE_IQ_TAXI

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_GNURADIO_IQTAXI=OFF

cmake --build build -j"$(nproc)"
sudo cmake --install build
sudo ldconfig
```

关键安装文件：

```text
<UHD-prefix>/lib/uhd/modules/libIQTaxiUHD.so
/usr/local/lib/libsdr_core.so
/usr/local/lib/libsdr_driver.so
```

检查依赖和设备发现：

```bash
ldd /usr/local/lib/uhd/modules/libIQTaxiUHD.so | grep 'not found'
uhd_find_devices --args 'addr=192.168.1.10'
uhd_usrp_probe --args 'addr=192.168.1.10'
uhd_usrp_probe --args 'addr=192.168.10.2'
```

预期设备类型为 `ANTSDR-E200`。不要在 srsENB/srsUE 正占用设备时运行 probe。

## 7. 构建原版 srsRAN_4G

安装依赖：

```bash
sudo apt install -y \
  build-essential cmake \
  libfftw3-dev libmbedtls-dev libpcsclite-dev \
  libboost-program-options-dev libconfig++-dev libsctp-dev
```

构建 stock srsRAN_4G：

```bash
cd srsRAN_4G
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DENABLE_UHD=ON
cmake --build build -j"$(nproc)"
```

确认 CMake 使用了安装 IQTAXI module 的那套 UHD：

```bash
grep -E 'UHD_(INCLUDE_DIRS|LIBRARIES)' build/CMakeCache.txt
```

本部署直接运行 `build/` 中的程序，不要求 `sudo make install`。

## 8. 安装 E200 配置包

将完整的 `e200_demo/` 目录放到 srsRAN_4G 仓库根目录。至少需要：

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

执行权限：

```bash
chmod +x e200_demo/run_epc.sh \
         e200_demo/run_enb.sh \
         e200_demo/run_ue.sh \
         e200_demo/load_profile.sh
```

`user_db.csv` 的 IMSI、K、OPc 必须与 `ue.conf` 的 soft USIM 完全一致。

## 9. 配置主机双网口

先用 `ip -br link` 确认实际接口名。下面用 `<ENB_NIC>` 和 `<UE_NIC>` 表示：

```bash
sudo ip link set <ENB_NIC> up
sudo ip address add 192.168.1.100/24 dev <ENB_NIC>

sudo ip link set <UE_NIC> up
sudo ip address add 192.168.10.200/24 dev <UE_NIC>
```

不要在远程 SSH 所依赖的接口上执行 `ip addr flush`。检查：

```bash
ping -c 3 192.168.1.10
ping -c 3 192.168.10.2
ethtool <ENB_NIC> | grep -E 'Speed|Duplex|Link detected'
ethtool <UE_NIC>  | grep -E 'Speed|Duplex|Link detected'
```

两条链路应为 1000 Mb/s、full duplex。建议：

```bash
sudo sysctl -w net.core.rmem_max=33554432
sudo sysctl -w net.core.wmem_max=33554432
```

## 10. 选择 6 PRB profile

推荐先使用最少外部依赖的 internal 档：

```text
e200_demo/profiles/6prb.conf
```

两板连接同一个外部 10 MHz 时使用：

```text
e200_demo/profiles/6prb_external.conf
```

外部 10 MHz 通常需要约 17--18 秒锁定。公共 PPS 不是 LTE attach 的必要
条件；10 MHz 只用于统一频率参考。

6 PRB 必须使用 `profiles/sib_6prb.conf`，其中 `prach_freq_offset=0`。默认的
offset 4 在 6 PRB 网格中越界。

## 11. 启动 LTE

打开三个终端，在仓库根目录严格按以下顺序启动。

终端 1：

```bash
sudo ./e200_demo/run_epc.sh
```

终端 2：

```bash
sudo ./e200_demo/run_enb.sh --profile 6prb
```

终端 3：

```bash
sudo ./e200_demo/run_ue.sh --profile 6prb
```

使用外部参考时，将后两个命令的 profile 改为 `6prb_external`。

启动脚本会：

- 强制 6 PRB 和对应 SIB；
- 保持 strict timestamp；
- 设置 `time_adv_nsamples=215`；
- 创建 `ue1` network namespace；
- 通过 `--gw.netns=ue1` 在 namespace 中创建 `tun_srsue`。

## 12. 成功判据和 IP 验证

UE 应依次输出：

```text
Found Cell
Found PLMN
Random Access Complete
RRC Connected
Network attach successful. IP: 172.16.0.x
```

检查 UE TUN：

```bash
sudo ip netns exec ue1 ip -br address show tun_srsue
```

UE 到 EPC：

```bash
sudo ip netns exec ue1 ping -c 10 172.16.0.1
```

EPC 到 UE，地址以 UE 控制台实际输出为准：

```bash
ping -c 10 172.16.0.x
```

### 12.1 iperf3 吞吐验证

以 UE 实际地址为 `172.16.0.2` 为例，下行测试：

```bash
sudo ip netns exec ue1 iperf3 -s -1 -B 172.16.0.2
iperf3 -c 172.16.0.2 -B 172.16.0.1 -t 20 -O 2
```

上行测试：

```bash
iperf3 -s -1 -B 172.16.0.1
sudo ip netns exec ue1 \
  iperf3 -c 172.16.0.1 -B 172.16.0.2 -t 20 -O 2
```

必须在 UE namespace 内运行 UE 一侧的 iperf3，并显式绑定 TUN 地址。75 PRB
本机实测单 TCP 流下行约 33.0 Mbit/s、上行约 25.8 Mbit/s；详细条件和实时流
异常见 `75PRB_IPERF_RECORD_CN.md`。

不要在默认 namespace 中使用 `ping -I tun_srsue` 判断空口是否工作。同机
运行 EPC 和 UE 时，Linux local route 可能绕过 LTE；`ue1` 用于避免该问题。

日志：

```text
/tmp/e200_epc.log
/tmp/e200_enb.log
/tmp/e200_ue.log
```

检查 RF 错误：

```bash
grep -Ein 'underflow|overflow|late|fatal|error' \
  /tmp/e200_enb.log /tmp/e200_ue.log
```

## 13. 常见故障定位

### UHD 找不到 E200

- 确认两板能 ping；
- 确认 `libIQTaxiUHD.so` 位于当前 UHD 的 module 路径；
- 用 `ldd` 排除缺失的 `libsdr_core.so`、`libsdr_driver.so`；
- 排除 `/usr` 与 `/usr/local` UHD ABI 混用。

### UE 一直搜不到小区

- 确认板端 server 是包含 1.92 MSps 128-tap 修复的新版本；
- 确认 eNB 主机持续向 UDP `49202` 发送 IQ；
- 用 IQTAXI `e200_iq_example` 单音测试区分 srsRAN 与板端 TX；
- 检查天线/衰减器连接和 eNB TX 端口；
- 注意 `time_adv` 只影响 UE uplink，不会导致 PSS 搜索失败。

### 能搜小区但 PRACH/attach 失败

- 确认 UE `time_adv_nsamples=215`；
- 确认 6 PRB 使用 `prach_freq_offset=0`；
- 检查 UE TX 到 eNB RX 的反向射频链路；
- RX gain 先使用 40 dB。

### attach 成功但 ping 不通

- 确认使用 `--gw.netns=ue1`；
- 从 `sudo ip netns exec ue1` 发起上行 ping；
- 使用 UE 实际分配的 `172.16.0.x`，不要假定固定地址。

### external 参考启动时报告暂未锁定

E200 捕获外部参考通常比 UHD 的首次检查更慢。应在启动协议栈前确认两板最终
出现 `ref_locked=true`；也可先用 internal profile 完成功能验证。

## 14. 当前验证范围

当前已完成 attach 的档位包括：

- 6 PRB / 1.92 MSps；
- 15 PRB / 3.84 MSps；
- 25 PRB / 5.76 MSps；
- 50 PRB / 11.52 MSps；
- 75 PRB / 15.36 MSps。

100 PRB / 23.04 MSps 可完成小区和 PRACH 检测，但持续全双工对主机网卡 RX
容量要求较高，不应作为第一次部署的验收档。

6 PRB 的历史成功日志、FIR96 回归根因和本次修复证据见
`e200_demo/6PRB_ATTACH_RECORD_CN.md`。

本次生成的 `e200-sd.frm` 已在线部署到两块板。两板重启后均由
`/usr/sbin/e200_v25_server` 自动启动，server 哈希为 `436172dc...`；在不使用
任何 `/tmp` 临时程序的条件下，6 PRB/internal 冷启动完成 attach，UE 获得
`172.16.0.4`，上下行各 10 次 ping 均为 0% 丢包。UE 启动初期出现过一次
RX timestamp jump/overflow，随后自动重同步且没有持续出现，不影响 attach 和
承载通信。
