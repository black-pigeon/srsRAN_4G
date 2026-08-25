# E100 eNB + E200 UE：6 PRB 通信验证记录

验证日期：2026-08-24

## 1. 验证结论

在不修改 srsRAN_4G 源码的前提下，以下组合已完成 LTE 小区搜索、PLMN、PRACH、
RRC、EPC attach、空闲态 Service Request 和数据面 ping：

- eNB：E100，`192.168.1.10`
- UE：E200，`192.168.10.122`
- LTE Band 7，EARFCN 3350
- 6 PRB，1.92 MSps，单天线
- 两端使用内部参考时钟
- UE 获得地址 `172.16.0.5/24`
- `ue1` 内 ping `172.16.0.1`：3 发 3 收，0% 丢包

本次只修改了 IQTAXI/UHD 插件和 `e200_demo` 配置，没有修改 srsRAN tracked
源码。

## 2. 关键参数

参数集中在 `profiles/e100_enb_e200_ue_6prb.conf`：

```text
E200_N_PRB=6
E200_TIME_ADV_NSAMPLES=215
E200_ENB_TIME_ADV_NSAMPLES=49
E200_ENB_RX_GAIN=40
E200_UE_TX_GAIN=89
E200_UE_FORCE_UL_AMPLITUDE=0.5
E200_CLOCK_SOURCE=internal
```

6 PRB 必须继续使用 `profiles/sib_6prb.conf`，其
`prach_freq_offset=0`。

## 3. E100 TX 故障与修复

故障并不是 deepfifo 持续交换样点时必然损坏 LTE 波形。E100 eNB 刚启动时，E200
录制到的下行约为 `-40.35 dBFS`，使用 5 ms（9600 点）同步窗口可以连续检出
`PCI=1`；运行一段时间后只剩约 `-64 dBFS` 的噪声。

原因是 srsRAN 的连续 protocol-v1 burst 遇到一次包内 underrun 后，FPGA 进入
`TX_DROP_BURST`。正常运行期间 srsRAN 不发送 EOB，因此该 burst 无法恢复，表现为
eNB 进程仍在但射频输出消失。

IQTAXI UHD 插件现在对 E100 默认把每个带时间戳的 `send()` 变成独立 SOB/EOB
burst，使每个片段重新按时间戳调度并具备恢复边界。E200/E206 保持原行为。
诊断时仍可用下面的环境变量显式覆盖：

```bash
IQTAXI_TIMED_SEND_PER_BURST=0   # 禁用 E100 默认行为，仅用于对照
IQTAXI_TIMED_SEND_PER_BURST=1   # 显式启用
```

启用后等待 25 秒再次录制，下行仍约为 `-40.41 dBFS`，PSS 每 5 ms 连续出现。

## 4. 上行校准

E100 eNB 的 `time_adv_nsamples=0` 时，检测到的 PRACH preamble 恒为 UE 发送值减
1。设置为 49 后，preamble 序号一致并可完成 RRC；设置为 55 已越过循环移位
窗口，变为发送值加 1。因此本组合固定使用 eNB 侧 49。

E200 UE 使用 `time_adv_nsamples=215`。为保证 E100 解调 PUSCH，UE 使用 TX gain
89 和固定上行幅度 0.5。成功轮次首次 PRACH offset 为 9；空闲态 Service Request
的 PRACH offset 为 0，随后 Service Request 成功。

## 5. 从已构建环境复现

先安装包含 E100 自动 burst 边界修复的 IQTAXI UHD 插件：

```bash
cd /home/wcc/mp_demo/custom_api/MICROPHASE_IQ_TAXI
cmake --build build -j"$(nproc)"
sudo cmake --install build
```

然后在三个终端依次运行：

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_epc.sh
```

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_enb.sh --profile e100_enb_e200_ue_6prb
```

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_ue.sh --profile e100_enb_e200_ue_6prb
```

成功标志：

```text
Found Cell: Mode=FDD, PCI=1, PRB=6
Found PLMN: Id=00101
RRC Connected
Network attach successful. IP: 172.16.0.x
```

数据面验证：

```bash
sudo ip netns exec ue1 ping -c 3 172.16.0.1
```

本次结果为 3/3 成功。若 UE 已进入 RRC IDLE，ping 会触发一次正常的 Service
Request，终端应显示 `Service Request successful.`。

## 6. 同步文件分析注意事项

1.92 MSps 下 PSS 周期为 5 ms，`synch_file` 应使用 9600 点窗口：

```bash
./build/lib/examples/synch_file \
  -i /tmp/capture.cf32 -l 9600 -s 128 -n 200 -t 3
```

不要使用 19200 点窗口判断“没有 PSS”；该工具按单个 PSS 周期工作，错误窗口会
造成假阴性。
