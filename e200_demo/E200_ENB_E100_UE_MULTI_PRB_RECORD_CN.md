# E200 eNB + E100 UE 多 PRB 验证记录

验证日期：2026-08-24。

## 硬件与公共参数

- E200 eNB：`192.168.10.122`
- E100 UE：`192.168.1.10`
- 两端参考源：外部 10 MHz
- LTE Band 7，EARFCN 3350，单天线
- eNB RX gain：40 dB
- E100 UE TX gain：50 dB
- strict timed TX：`ignore_tx_timestamps=false`
- 未修改 srsRAN 源码

## 实测结果

| PRB | 采样率 | E100 UE `time_adv_nsamples` | 初次 attach | 数据面及空闲重连 |
| --- | ---: | ---: | --- | --- |
| 15 | 3.84 MSps | 215 | 成功，TA=21 | ping 8/8；空闲 Service Request 后 ping 8/8 |
| 25 | 5.76 MSps | 215 | 成功，TA=14 | ping 20/20，0% 丢包 |
| 50 | 11.52 MSps | 264 | 成功 | 新 bit 下连续 3 次 Service Request 成功，ping 24/24 |
| 75 | 15.36 MSps | 264 | 成功 | 新 bit 下连续 3 次 Service Request 成功，ping 24/24；持续业务曾验证 99/100 |

25 PRB 中，`264` 会让 eNB 检出的 PRACH 序列与 UE 发送序列不一致；改为
`215` 后首次 PRACH 正确并完成 attach。因此 E100 当前不能把同一个手工补偿值直接用于
全部采样率。

## E100 TX reburst 修复及上板结果

旧 bit 在 50/75 PRB 下均表现为首次 PRACH 可以 attach，但 RRC 空闲释放后再次
Service Request 时只剩 `preamble = UE seq + 1`、`offset = 45` 的错误检测结果，
重新连接失败。根因是 E100 LVDS TX CDC FIFO 只在复位后的首次 burst 做预填充；FIFO
排空后 `tx_fifo_active` 未恢复，下一次 burst 会跳过预填充并在指针跨时钟域期间插入
零样点。

新 bit 在 FIFO 排空后重新进入预填充状态。2026-08-24 上板回归结果：

- 50 PRB：3 次 `RRC IDLE -> ping -> Service Request` 全部成功；每次正确检测
  `preamble = UE seq`，正确峰 offset 为 0；ping 合计 24/24。
- 75 PRB：3 次相同流程全部成功；ping 合计 24/24。一次进程重启后的正确峰 offset
  为 43，eNB 下发 TA=43 后 attach 和再次 Service Request 均成功。
- eNB 在部分 50/75 PRB PRACH 上仍会同时报告较弱的 `seq+1/offset=45` 次峰，但正确
  峰现在持续存在并被成功调度，不再影响接入和空闲重连。

因此，原“E100 空闲后第二个 timed burst 失效”的问题已通过新 FPGA bit 完成实机验证。

配置文件：

- `profiles/e200_enb_e100_ue_25prb.conf`
- `profiles/e200_enb_e100_ue_15prb.conf`
- `profiles/e200_enb_e100_ue_50prb.conf`
- `profiles/e200_enb_e100_ue_75prb.conf`

启动方式（EPC 已先启动）：

```bash
sudo ./run_enb.sh --profile e200_enb_e100_ue_25prb
sudo ./run_ue.sh  --profile e200_enb_e100_ue_25prb
```

将 profile 名称替换为 `e200_enb_e100_ue_50prb` 或
`e200_enb_e100_ue_75prb` 即可切换带宽。
