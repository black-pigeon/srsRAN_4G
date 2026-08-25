# E200 IQTAXI：6 PRB / 1.92 MSps attach 成功记录

## 验证结果

2026-08-15 在同一台主机上使用两块 E200 完成了未经修改的
srsRAN_4G LTE eNB/UE 通信：

- eNB E200：`192.168.1.10`，主机接口 `192.168.1.100/24`
- UE E200：`192.168.10.2`，主机接口 `192.168.10.200/24`
- LTE Band 7，EARFCN 3350，6 PRB，1.92 MSps
- 已分别验证两板共用外部 10 MHz 和两板各自使用 internal 参考源
- strict timed TX：`ignore_tx_timestamps=false`
- eNB RX/UE RX gain：40 dB
- eNB TX gain：89（AD9361 attenuation 0 dB）
- UE TX gain：79（AD9361 attenuation 10 dB）
- UE `time_adv_nsamples=215`
- UE 完成小区搜索、PLMN、PRACH、RRC、鉴权、attach 和默认承载建立
- 外部参考测试的 UE 地址为 `172.16.0.2/24`
- internal 参考测试的 UE 地址为 `172.16.0.3/24`
- 两种参考源下，UE 到 EPC、EPC 到 UE 各 10 次 ICMP 均为 0% 丢包

本次 eNB 的 PRACH 输出为：

```text
RACH: tti=5461, cc=0, pci=1, preamble=18, offset=29, temp_crnti=0x46
```

UE 对应输出为：

```text
Found Cell: Mode=FDD, PCI=1, PRB=6, Ports=1, CP=Normal, CFO=7.2 KHz
Random Access Complete. c-rnti=0x46, ta=29
Network attach successful. IP: 172.16.0.2
```

将唯一变量切换为 internal 参考后同样完成 attach：

```text
Found Cell: Mode=FDD, PCI=1, PRB=6, Ports=1, CP=Normal, CFO=2.8 KHz
Random Access Complete. c-rnti=0x46, ta=29
Network attach successful. IP: 172.16.0.3
```

这说明公共 10 MHz 能降低并稳定两板频差，但不是本次近距离 6 PRB attach 的
必要条件。此前 internal 模式搜不到小区同样是 FIR96 造成的无 TX，不是自由
运行参考时钟本身造成的。

因此当前 6 PRB 成功基线是 `time_adv_nsamples=215`，不是 66。66 保留为
`6prb_adv66` 对照档，但不应覆盖已经验证的成功档。

## 本次回归的根因

历史成功 attach 发生在 14:08。随后为解决较大带宽问题，14:52 构建并在
14:53 测试了 FIR96 版本，相关修改最终在 15:51 提交为 `05c021a`。该修改把
1.92 MSps 原来使用的 128-tap 对称 RX/TX FIR 也裁剪成了 96 taps，导致设备
重启并加载新 rootfs server 后，1.92 MSps TX 射频输出消失。

以下 A/B 测试将问题定位到了 AD9361 低速率 TX FIR，而不是 srsRAN、UHD、
UDP、FPGA 时间戳或天线：

1. eNB 运行时与停止后的 UE 原始 IQ 功率相同，均只有噪声。
2. IQTAXI 独立单音发送在 1.92 MSps 下也收不到，排除了 srsRAN。
3. FPGA 内部 DDS 在 20 MSps 下可正常接收，在 1.92 MSps 下消失，排除了
   UDP、UHD、时间戳和 host IQ unpack。
4. 仅恢复 1.92 MSps 的历史 128-tap 对称 RX/TX FIR 后，UE 接收 RMS 从约
   `1.28e-4` 上升到 `1.30e-2`，DDS 峰高出噪声底约 67 dB。
5. 使用同一修复 server 重新启动 srsRAN 后立即完成 attach 和双向 ping。

修复位于：

```text
board/e200/init_ad9361_e200/e200_v25_server.c
```

修复策略：

- 1.92 MSps：128-tap、RX decimation x4、TX interpolation x4；
- 3.84/5.76/7.68 MSps：保留 96-tap RX FIR，TX FIR bypass；
- 更高速率：保持原来的 FIR bypass 路径。

本次诊断构建的 server SHA256 为：

```text
6079f636d145236d8bb20b02db90f92bf7b26435b75a688a2549df48db9b5d9f
```

当前两板运行的是 `/tmp/e200_v25_server.fir128`。这是运行时验证部署，重启
后会恢复 SD 镜像中的旧 server；在生成并部署包含该修复的新 SD 镜像前，
不能把本次临时部署视为持久化发布。

## 复现步骤

### 1. 检查主机网络

```bash
ip -br address show eth1 eth2
ping -c 1 192.168.1.10
ping -c 1 192.168.10.2
```

预期主机地址分别为 `192.168.1.100/24` 和 `192.168.10.200/24`。

### 2. 选择参考源

当前已验证、最少依赖的配置是 internal：

```bash
sudo ./e200_demo/run_enb.sh --profile 6prb
sudo ./e200_demo/run_ue.sh --profile 6prb
```

需要使用公共外部 10 MHz 时，在协议栈尚未占用设备时先执行：

```bash
./e200_demo/e200_ref_probe 192.168.1.10 external
./e200_demo/e200_ref_probe 192.168.10.2 external
```

本次两板分别约在 17 秒和 18 秒后出现 `ref_locked=true`。

### 3. 启动 6 PRB 协议栈

使用三个终端，严格按 EPC、eNB、UE 的顺序启动：

```bash
sudo ./e200_demo/run_epc.sh
sudo ./e200_demo/run_enb.sh --profile 6prb
sudo ./e200_demo/run_ue.sh --profile 6prb
```

若两板已连接并锁定公共 10 MHz，将两个 `6prb` 都替换为
`6prb_external`。

该档位固定以下选项：

```text
n_prb=6
sample_rate=1.92 MSps
time_adv_nsamples=215
clock_source=internal（6prb）或 external（6prb_external）
UE network namespace=ue1
prach_freq_offset=0
```

### 4. 验证空口承载

不要在 UE 与 EPC 相同的默认 network namespace 中用本地路由代替空口。
上行必须从 `ue1` 发出：

```bash
sudo ip netns exec ue1 ping -c 10 172.16.0.1
```

从 EPC 到 UE 使用 attach 后实际分配的地址：

```bash
ping -c 10 172.16.0.2
```

UE 地址可能在不同启动中变化，应以 `Network attach successful` 输出为准。

## 成功判据

- UE 输出 `Found Cell`、`RRC Connected` 和 `Network attach successful`；
- EPC 完成 authentication、security mode、create/modify bearer；
- eNB 输出正确的 PRACH preamble 并显示用户连接；
- `tun_srsue` 位于 `ue1` namespace；
- 双向 ping 均为 0% 丢包；
- 日志中没有持续的 late、underflow 或 overflow。
