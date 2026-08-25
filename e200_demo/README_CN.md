# E100/E200 IQTAXI 单机 LTE 演示

## 当前硬件：第一次请从这里开始

当前实机连接为：

```text
E100  eNB  192.168.1.10
E200  UE   192.168.10.122
两端共用外部 10 MHz
LTE Band 7 / EARFCN 3350 / 6 PRB / 1.92 MSps
```

第一次操作时，不需要先阅读后面的 FPGA 历史分析。依次完成“预检查、启动、识别
成功输出、测试数据面”四步即可。

### 1. 预检查（不运行协议栈时执行）

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
./e200_demo/validate_build.sh --profile e100_enb_e200_ue_6prb_external
```

最后出现下面这行才继续：

```text
Build, RF plugin selection, routing, reference clock, and both SDR RX paths are OK.
```

若协议栈正在运行，应先在 UE、eNB、EPC 三个终端按 `Ctrl-C`，再执行预检查；不要
让 `uhd_usrp_probe` 与 srsENB/srsUE 同时占用设备。

### 2. 按顺序打开三个终端

终端 1，启动 EPC：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_epc.sh
```

终端 2，启动 E100 eNB：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_enb.sh --profile e100_enb_e200_ue_6prb_external
```

必须等终端 2 出现以下内容后，才启动 UE：

```text
Using e100_enb_e200_ue_6prb_external: PRB=6, srate=1920000, time_adv=49
==== eNodeB started ===
```

终端 3，启动 E200 UE：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_ue.sh --profile e100_enb_e200_ue_6prb_external
```

### 3. 看懂成功输出

UE 终端按顺序出现以下四类信息，才表示真正 attach 成功：

```text
Found Cell: Mode=FDD, PCI=1, PRB=6
Found PLMN: Id=00101
RRC Connected
Network attach successful. IP: 172.16.0.x
```

eNB 终端应看到 UE 发出的序列与检测到的前导相同，例如：

```text
UE:  Random Access Transmission: seq=7
eNB: RACH: preamble=7, offset=9
```

`seq == preamble` 是判断初始上行时间补偿正确的关键；仅看到 `Found Cell` 不能说明
已经建立通信。

### 4. 测试 LTE 数据面和空闲重连

终端 4 执行：

```bash
sudo ip netns exec ue1 ip address show tun_srsue
sudo ip netns exec ue1 ping -c 5 -i 0.3 -W 2 172.16.0.1
```

等待 UE 显示 `RRC IDLE` 后再执行一次 ping。UE 应显示：

```text
Service Request with cause mo-Data.
RRC Connected
Service Request successful.
```

本 profile 在 2026-08-24 的 README 命令回归中获得 `172.16.0.9`，两轮 ping 均
为 5/5，连续两次空闲 Service Request 成功。

停止时按相反顺序操作：先 UE，再 eNB，最后 EPC，均使用 `Ctrl-C`。

### 5. 切换 PRB

E100 作为 eNB、E200 作为 UE 时，eNB 和 UE 必须使用同一个 profile：

| PRB | profile |
| ---: | --- |
| 6 | `e100_enb_e200_ue_6prb_external` |
| 15 | `e100_enb_e200_ue_15prb` |
| 25 | `e100_enb_e200_ue_25prb` |
| 50 | `e100_enb_e200_ue_50prb` |
| 75 | `e100_enb_e200_ue_75prb` |

切换时停止 UE 和 eNB，保持 EPC 运行即可；然后用新 profile 先启动 eNB、再启动
UE。不要只改 `enb.conf` 中的 `n_prb`，profile 还同时选择采样率、两端地址、时钟源
和已验证的时间补偿。

6 PRB / 1.92 MSps 的已验证启动步骤、FIR96 回归根因和修复记录见
[`6PRB_ATTACH_RECORD_CN.md`](6PRB_ATTACH_RECORD_CN.md)。

面向新主机、新 SD 卡和两块默认地址 E200 的完整交付流程见
[`DEPLOY_FROM_SCRATCH_CN.md`](DEPLOY_FROM_SCRATCH_CN.md)。

2026-08-15 的 15/25/50/75 PRB 回归结果见
[`results/prb_matrix_fir128_sd_20260815/VALIDATION_CN.md`](results/prb_matrix_fir128_sd_20260815/VALIDATION_CN.md)，
75 PRB 双向 TCP 吞吐测试见
[`75PRB_IPERF_RECORD_CN.md`](75PRB_IPERF_RECORD_CN.md)。

E100 作为 eNB、E200 作为 UE 的 6 PRB 混合设备验证见
[`E100_ENB_E200_UE_6PRB_RECORD_CN.md`](E100_ENB_E200_UE_6PRB_RECORD_CN.md)。
新 bit 下该角色的 15/25/50/75 PRB attach、空闲重连和数据面实测见
[`E100_ENB_E200_UE_MULTI_PRB_RECORD_CN.md`](E100_ENB_E200_UE_MULTI_PRB_RECORD_CN.md)。

交换角色、由 E200 作为 eNB、E100 作为 UE 的验证见
[`E200_ENB_E100_UE_6PRB_RECORD_CN.md`](E200_ENB_E100_UE_6PRB_RECORD_CN.md) 和
[`E200_ENB_E100_UE_MULTI_PRB_RECORD_CN.md`](E200_ENB_E100_UE_MULTI_PRB_RECORD_CN.md)。

设备地址和角色由 profile 决定，不再假设 UE 固定为旧地址 `192.168.10.2`。当前混合
设备 profile 使用 E100 `192.168.1.10` 和 E200 `192.168.10.122`。已验证空口配置为
LTE Band 7、EARFCN 3350、单天线；核心网和 S1 接口都在本机运行。当前已完成 attach
的档位包括 1.4 MHz（6 PRB、1.92 MSps）、3 MHz（15 PRB、3.84 MSps）、5 MHz
（25 PRB、5.76 MSps）、10 MHz（50 PRB、11.52 MSps）和 15 MHz（75 PRB、
15.36 MSps）。

## 射频连接与安全

Band 7 是许可频段，只有在屏蔽环境或获得授权时才能发射。若使用射频线直连，必须使用两条单向链路并加足够的衰减器：`eNB TX -> 衰减器 -> UE RX`，以及 `UE TX -> 衰减器 -> eNB RX`。不要把 TX 直接接到 RX。UHD/srsRAN 的 `tx_gain` 数值越大，发射越强；E200 插件会将它换算为 `AD9361 attenuation = 89 - tx_gain`。例如 `tx_gain=79` 表示 10 dB 硬件衰减。

若使用天线进行合规的近距离测试，当前实测配置为 eNB TX 89 dB、UE TX 79 dB，接收增益均为 40 dB。根据信号质量和距离向下调整发射增益。

推荐第一次验证使用 `6prb` internal profile，不依赖外部参考。需要统一频率
参考时，两台 E200 的外部参考输入应连接到同一个 10 MHz 参考源。配置中的
`clock=external` 会让 UHD 选择 FPGA 的 10 MHz VCXO 驯服环路，并等待
`ref_locked`；当前硬件通常需要约 17 秒捕获。10 MHz 只统一频率，若要
统一绝对时间 epoch 还需要公共 PPS；本例的 LTE attach 不要求两板 epoch 相同。

## 原 E200 双机启动方式

以下命令只适用于原 E200 双机 profile。当前 E100+E200 硬件应使用本文开头的步骤。
先执行只读检查：

```bash
./e200_demo/validate_build.sh --profile 6prb
```

打开三个终端，严格按顺序启动：

```bash
sudo ./e200_demo/run_epc.sh
sudo ./e200_demo/run_enb.sh --profile 6prb
sudo ./e200_demo/run_ue.sh --profile 6prb
```

两板已锁定公共 10 MHz 时，将后两个 profile 改为 `6prb_external`。

看到 UE 获得 `172.16.0.x` 地址后，在第四个终端确认 TUN 和路由：

```bash
sudo ip netns exec ue1 ip address show tun_srsue
sudo ip netns exec ue1 ip route show dev tun_srsue
```

本地承载验证必须从 namespace 发起：

```bash
sudo ip netns exec ue1 ping -c 10 172.16.0.1
ping -c 10 <UE实际获得的172.16.0.x地址>
```

需要访问外网时，再开启 IPv4 转发并为 `172.16.0.0/24` 配置 NAT。本演示的空口、注册和承载建立不依赖 NAT；`ue1` 用于避免同机 EPC/UE 的 local route 绕过 LTE 承载。

## 成功标志与排错

- EPC 日志出现 `S1 Setup Request` 和 UE attach/认证成功。
- eNB 控制台出现一个 UE，状态中可看到 RNTI、CQI、MCS。
- UE 出现 `Network attach successful`，并创建 `tun_srsue`。
- 日志位于 `/tmp/e200_epc.log`、`/tmp/e200_enb.log`、`/tmp/e200_ue.log`。

若 UE 一直搜不到小区，先检查两端是否都为 EARFCN 3350，再查看 `/tmp/e200_ue.log` 中的 CFO/RSRP。若有 `overflow`、`underflow` 或 `late`，先关闭 CPU 节能、减少后台负载，并增大系统 UDP 缓冲区。

如果 eNB 出现 `control response timeout` 后退出，不能只根据 ping 判断 E100 已恢复。
按下面顺序处理：

1. 停止 UE 和 eNB；
2. 确认两块板能 ping；
3. 单独运行 `uhd_usrp_probe --args 'addr=192.168.1.10,clock_source=external'`；
4. 用 `--sensor /mboards/0/sensors/ref_locked` 确认输出为 `true`；
5. 重新先启动 eNB、再启动 UE；
6. 若仍持续搜不到小区，重启 E100 板卡后再试。

不要在主机 SSH 提示远端 host key 改变时直接关闭校验；先确认板卡确实已被更换或
重刷，再更新对应的 `known_hosts` 记录。

当前验证时 CPU governor 为 `performance`，两条 SDR 链路均为 1000 Mb/s 全双工。`ue.conf` 中的 `time_adv_nsamples=215` 已在 25、50、75 和 100 PRB strict timestamp 模式下得到正确 PRACH，eNB 报告正确前导的 offset 均为 0；25、50、75 PRB 均完成 attach。此前在 25 PRB 使用 66 samples 时，PRACH 会稳定地被识别为 `N-1`；ZCZC=5 对应的一个 Ncs 区间加实测残差折算为 149 samples，因此校准值为 `66+149=215`。当前证据表明 215 是 E200 FPGA/packet 管线的固定样点补偿，不需要随 PRB 重填不同数值。

上一段结论适用于原 E200 双机链路；混合设备交换角色后必须使用对应的
`e100_enb_e200_ue_*` profile。E100 的 RX/基带链路常数不同；外部 10 MHz 下实测
6 PRB 使用 eNB/UE 补偿 49/215，15/25/50/75 PRB 使用 eNB 补偿 98、UE 补偿分别为
116/66/-71/215，不能统一写成 215。

25 PRB 还依赖 E200 板端的 5.76 MSps FIR 配置：RX 使用 FIR x4，TX bypass；主机 IQTAXI/UHD 插件在采样率切换期间冻结 SDR sample time，并按新采样率重编码 FPGA tick。验证版本如下：

```text
rootfs e200_v25_server SHA256 436172dce148924d6bbe67a915b98c9b4e53da80baf94f582d792dbabd94e80e
libIQTaxiUHD.so  SHA256 bfceb49dd1d32b6b6f25d7d5baeff7242241a27e741793ae2106e638b23160fc
```

两块板 SD 启动分区中的 FPGA 与本地 Vivado 工程最新产物逐字节一致：

```text
e200_iqtaxi.bit  SHA256 c8d44d13bbbe28f262c0394295ac4418fe0a223ea755196d1adaa2794dd83744
Vivado 2022.2，generated_at=2026-08-15T13:31:23+0800
```

该 bit 是本次 SD 镜像和两块实机冷启动验证所使用的 FPGA artifact。

```bash
sudo cpupower frequency-set -g performance
sudo sysctl -w net.core.rmem_max=33554432
sudo sysctl -w net.core.wmem_max=33554432
```
