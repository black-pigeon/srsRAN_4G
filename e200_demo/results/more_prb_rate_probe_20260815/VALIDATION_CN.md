# E200 更大 LTE 带宽验证

测试均使用 strict TX timestamps、外部 10 MHz、RX gain 40 dB 和
`time_adv_nsamples=215`，未修改 srsRAN 源码。

| PRB | Sample rate | 结果 |
| ---: | ---: | --- |
| 50 | 11.52 MSps | 一次 PRACH，offset=0，完成 RRC/EPC attach |
| 75 | 15.36 MSps | 一次 PRACH，offset=0，完成 RRC/EPC attach |
| 100 | 23.04 MSps | 小区、PLMN、正确 PRACH offset=0；持续全双工 RX overflow，未 attach |

独立 RX 速率测试中，11.52、15.36、23.04 MSps 均准确回读，2000 个包的
时间戳连续且零错误。100 PRB 的失败只在 srsENB/srsUE 持续双向负载下出现，
表现为 RX timestamp 跳 360/720 samples、RF overflow 以及主机网卡
`rx_missed_errors/rx_fifo_errors` 增长。下一步应优先降低每秒 UDP 包数或优化
NIC ring、IRQ affinity、NAPI/backlog 和接收批处理，而不是调整 time advance。

当前系统已恢复并保持运行在 75 PRB，UE attach 地址为 `172.16.0.7`。
