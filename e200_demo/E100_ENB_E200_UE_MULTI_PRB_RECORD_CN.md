# E100 eNB + E200 UE 多 PRB 验证记录

验证日期：2026-08-24。

## 硬件与公共参数

- E100 eNB：`192.168.1.10`
- E200 UE：`192.168.10.122`
- 两端使用外部 10 MHz 参考源
- LTE Band 7，EARFCN 3350，单天线
- strict timed TX：`ignore_tx_timestamps=false`
- E100 eNB RX gain：40 dB
- E200 UE TX gain：89，固定上行幅度 0.5
- 未修改 srsRAN 源码

## 实测结果

| PRB | 采样率 | eNB `time_adv` | UE `time_adv` | 首次接入 | 空闲重连与数据面 |
| ---: | ---: | ---: | ---: | --- | --- |
| 6 | 1.92 MSps | 49 | 215 | 成功，TA=9 | 两轮 ping 均 8/8，两次 Service Request 成功 |
| 15 | 3.84 MSps | 98 | 116 | 成功，TA=21 | 两轮 ping 均 8/8，Service Request 成功 |
| 25 | 5.76 MSps | 98 | 66 | 成功，TA=31 | 两轮 ping 均 8/8，Service Request 成功 |
| 50 | 11.52 MSps | 98 | -71 | 成功，TA=38 | 两轮 ping 均 8/8，Service Request 成功 |
| 75 | 15.36 MSps | 98 | 215 | 成功，TA=38 | 两轮 ping 均 8/8，Service Request 成功 |

每档均正确解出 `PCI=1`、配置的 PRB 数和 `PLMN=00101`。首次接入及空闲态
Service Request 中，eNB 检测的 PRACH preamble 均与 UE 输出的随机序列一致。
6 PRB 使用外部 10 MHz 时，UE 启动阶段累计报告 2 次 underrun，之后没有继续增长，
未影响 attach、两次空闲重连或数据面。

## PRACH 校准依据

不能把 6 PRB 的 eNB 侧 49 samples 或 E200 作为 eNB 时的 UE 侧 215 samples
无条件复制到交换角色后的所有采样率。25 PRB 的边界实验给出了可重复证据：

- eNB=49、UE=215：eNB 恒定检测为 `N+1`、offset=45；
- eNB=147、UE=215：eNB 恒定检测为 `N-1`、offset=38；
- eNB=98、UE=215：仍为 `N+1`、offset=29；
- 保持 eNB=98，把 UE 从 215 增到 364（增加约一个 Ncs）后变为 `N+2`；
- 因此把 UE 减少一个 Ncs 到 66 后得到正确的 `N`，并完成 attach。

15/50 PRB 使用同一 Ncs 物理时长换算得到 116/-71 后一次 attach 成功。75 PRB
在 -166 时为 `N-1`，回到 215 后得到正确前导并完成 attach。负的
`time_adv_nsamples` 是 srsRAN 支持的反向补偿；控制台会打印其绝对补偿量。

## 复现

EPC 启动后，对同一个 profile 分别启动 eNB 和 UE：

```bash
sudo ./e200_demo/run_epc.sh
sudo ./e200_demo/run_enb.sh --profile e100_enb_e200_ue_15prb
sudo ./e200_demo/run_ue.sh  --profile e100_enb_e200_ue_15prb
```

可将 profile 替换为：

- `e100_enb_e200_ue_6prb_external`
- `e100_enb_e200_ue_25prb`
- `e100_enb_e200_ue_50prb`
- `e100_enb_e200_ue_75prb`

数据面与空闲重连验证：

```bash
sudo ip netns exec ue1 ping -c 8 -i 0.3 -W 2 172.16.0.1
```

等待 UE 显示 `RRC IDLE` 后再次执行；应看到 `Service Request successful.`。
