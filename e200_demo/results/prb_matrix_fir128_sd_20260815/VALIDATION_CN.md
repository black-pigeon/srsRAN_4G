# E200 SD 固件多 PRB 验证记录（2026-08-15）

## 测试条件

- eNB：`192.168.1.10`
- UE：`192.168.10.2`
- LTE Band 7，EARFCN 3350，SISO
- internal reference，strict timed TX
- UE `time_adv_nsamples=215`
- 两端 RX gain 40 dB
- SD firmware：`e200-sd.frm`
  `fec1cf13d2fd261018f10140cf9c2433f9a803c8bdf1baef2421b966221e7ee8`
- FPGA bit：
  `c8d44d13bbbe28f262c0394295ac4418fe0a223ea755196d1adaa2794dd83744`

每档重新启动 eNB 和 UE，以成功 attach、UE namespace 到 EPC 以及 EPC 到 UE
的双向 ping 为功能通过判据。

## 结果

| Profile | 采样率 | Attach | 双向 ping | RF 现象 | 结论 |
| --- | ---: | --- | --- | --- | --- |
| `15prb` | 3.84 MSps | 成功，UE `172.16.0.2` | 两向均 5/5 | eNB 启动阶段 1 次 `Late`，业务阶段无持续错误 | 通过 |
| `25prb` | 5.76 MSps | 成功，UE `172.16.0.3` | 两向均 5/5 | 未检出 underflow/overflow/late/TS mismatch | 通过 |
| `50prb` | 11.52 MSps | 成功，UE `172.16.0.4` | 两向均 5/5 | ping 完成后出现短暂 UE underflow 和一次 RLF，自动重建成功 | 功能通过，稳定性待长测 |
| `75prb` | 15.36 MSps | 成功，UE `172.16.0.5` | 两向均 10/10 | 本轮 attach/ping 阶段未检出流错误 | 通过 |

原始 eNB/UE 日志分别保存在各 profile 子目录。100 PRB 不列入已成功档位：
此前可完成小区、PLMN 和 PRACH，但持续全双工受当前主机 RX overflow 限制，
尚未完成 attach。

## 结论

同一个 `time_adv_nsamples=215` 已覆盖 15、25、50、75 PRB，无需为不同 PRB
维护不同的 time advance 配置。50 PRB 的短暂重建说明“能 attach/ping”和“持续
满载稳定”仍需分别验证；后续建议对 50/75 PRB 运行至少 10 分钟双向业务并统计
RF async event 和 RRC 重建次数。
