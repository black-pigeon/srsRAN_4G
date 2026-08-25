# E206 eNB 6 PRB / 1.92 MSPS 验证记录

验证日期：2026-08-17

## 结论

E206 作为 eNB、E200 作为 UE、6 PRB、1.92 MSPS 时，原先无法接入的直接原因是
E206 eNB 的 TX/RX 相对时延未补偿。`enb.conf` 中的默认值为 0；本组合的实测校准值为：

```text
rf.time_adv_nsamples=49
```

使用 49 个样点后：

- UE 发送的 PRACH 序号与 E206 检测序号一致；
- PRACH `offset=0.0 us`，RAR 的 `ta=0`（另一轮受启动量化影响为 1）；
- UE 完成 `RRC Connected`、`Random Access Complete` 和 `Network attach successful`；
- `ue1` 到 EPC `172.16.0.1` 的数据面 ping 已验证可通。

49 是 E206 eNB 在 1.92 MSPS 下的专用值。不要直接写入通用 `enb.conf`，否则可能影响
已经验证正常的 E200 eNB 或 E206 15.36 MSPS 流程。

## 测试条件

```text
E206 eNB: 192.168.1.10
E200 UE:  192.168.10.122
LTE:      FDD, 6 PRB, 1.92 MSPS
参考源:   两侧 external 10 MHz，UHD ref_locked=true
E200 UE:  time_adv_nsamples=215, tx_gain=79
```

外部参考将 UE 观测到的 CFO 降至约 0.1--0.2 kHz，但在 eNB 补偿为 0 时，故障仍然存在，
因此载频偏差不是本次无法接入的根因。

## 实测校准过程

| E206 eNB time advance | PRACH 结果 | PHY offset | 接入结果 |
|---:|---|---:|---|
| 0 | `preamble = UE seq - 1` | 1.0 us | 失败，Msg3 无法正确解调 |
| 30 | 序号一致 | 10.5 us | attach 成功 |
| 39 | 序号一致 | 5.7 us | attach 成功，数据面 ping 可通 |
| 49 | 序号一致 | 0.0 us | attach 成功，最佳时延点 |
| 58 | `preamble = UE seq + 1` | 21.0 us | 失败，已经越过正确窗口 |

这个结果也解释了原先稳定出现的 `seq N -> preamble N-1`：相对时延跨过了一个 PRACH
循环移位区间，而不是 srsRAN 的 PRACH 序号计算错误。不要在 srsRAN 中对检测序号强制加 1。

## 复现命令

先启动 EPC，再从 `e200_demo` 目录启动 eNB。关键参数是 eNB 的 49 样点补偿：

```bash
sudo ./run_enb.sh --profile 6prb_external \
  --rf.srate=1920000 \
  --rf.time_adv_nsamples=49 \
  --log.filename=/tmp/e206_enb_192_ext10_enbadv49_enb.log
```

本次 E200 UE 地址为 `192.168.10.122`，使用下面的参数：

```bash
sudo env LD_LIBRARY_PATH=/home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G/build/lib/src/phy/rf \
  ../build/srsue/src/srsue ./ue.conf \
  --rf.srate=1920000 \
  --rf.time_adv_nsamples=215 \
  --rf.tx_gain=79 \
  --rf.device_args=addr=192.168.10.122,recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=external,clock_source=external \
  --gw.netns=ue1
```

## 日志证据

最佳时延点：

```text
/tmp/e206_enb_192_ext10_enbadv49_enb.log
/tmp/e206_enb_192_ext10_enbadv49_enb.console
/tmp/e206_enb_192_ext10_enbadv49_ue.log
/tmp/e206_enb_192_ext10_enbadv49_ue.console
```

39 样点长测与数据面：

```text
/tmp/e206_enb_192_ext10_enbadv39_stable_enb.log
/tmp/e206_enb_192_ext10_enbadv39_stable_ue.log
/tmp/e206_enb_192_ext10_enbadv39_ping1.log
/tmp/e206_enb_192_ext10_enbadv39_ping2.log
```

## 尚未关闭的问题

49 样点已经解决无法接入和 PRACH 序号错误，但 1.92 MSPS 上行 PUSCH 的短测 BLER 仍约
50%。功率对照中，E200 UE 的 `tx_gain=69/79/84` 分别约为 80%/50%/89%，79 是三点中
最好，说明剩余问题不是简单的输入过载或发射功率不足。后续应单独检查 E206 1.92 MSPS
接收滤波、宽带调制信号质量或 PUSCH 解调，不应撤销 49 样点时延校准。
