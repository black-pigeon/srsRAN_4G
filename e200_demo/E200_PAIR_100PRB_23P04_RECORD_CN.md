# 双 E200 100 PRB / 23.04 MSPS 验证记录

验证日期：2026-08-17

## 结论

两台 E200 已在 23.04 MSPS、100 PRB 下完成以下功能验证：

- 100 PRB 小区搜索和 MIB/SIB 解码；
- PRACH、RRC 连接和 EPC attach；
- LTE 隧道 ping 10/10；
- 下行、上行 TCP iperf3 均完整结束。

设备和管理网络：

```text
eNB E200: 192.168.1.10，经 eth2
UE  E200: 192.168.10.122，经 eth0
eth0/eth2: 1000 Mbit/s, full duplex
LTE: 100 PRB, 23.04 MSPS, SISO, internal reference
UE time_adv_nsamples: 215
```

因此 23.04 MSPS 的基本收发、时间戳、srsRAN attach 和数据面功能可以认定为通过。
持续满负载下仍有少量 TX Underflow/RRC 重建，不能认定为“无实时错误的稳定版本”。

## 是否为千兆网带宽不足

不是千兆链路线速本身不足。

23.04 MSPS、SC16 的单向 IQ payload 为：

```text
23.04e6 complex samples/s * 4 bytes = 92.16 MB/s = 737.28 Mbit/s
```

加 UDP/Ethernet 开销后，实测约 767 Mbit/s、64 kpacket/s。每台 E200 使用独立千兆网口，
每个方向仍未超过 1 Gbit/s。单板连续接收 1.152 亿样点时，两块网卡分别都没有产生
NIC drop/error 或 UDP `RcvbufErrors`。

旧 100 PRB 测试中的 `RX TS mismatch` 和 Overflow 更接近主机 UDP socket 缓冲不足及
高频日志造成的调度压力，而不是物理链路超出 1 Gbit/s。

## 主机 UDP 接收缓冲

系统原值只有：

```text
net.core.rmem_max = 212992
net.core.rmem_default = 212992
net.core.netdev_max_backlog = 1000
```

虽然当前驱动请求 64 MiB 接收缓冲，但它会被内核上限截断。未调整时，100 PRB 数据测试
出现了 41 个新增 `RcvbufErrors` 和一次 `RX TS mismatch`。

本轮使用的运行时参数为：

```bash
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.rmem_default=16777216
sudo sysctl -w net.core.netdev_max_backlog=10000
```

`ss -u -a -m -n` 确认 E200 流 socket 的 `rb=134217728`。调整后再次运行 23.04 MSPS
双板全双工及双向 iperf3：

```text
RcvbufErrors increment: 0
RX TS mismatch:          0
NIC error/drop:          0
```

这些 sysctl 设置当前只在运行时生效，主机重启后需要重新设置或另行写入 sysctl.d。

另外测试过把 `wmem_max`/`wmem_default` 提高到 16 MiB/4 MiB。发送 socket 缓冲确实
增大，但吞吐和 TX Underflow 没有改善，因此已恢复原值 212992；不把增大 wmem 作为
当前推荐配置。

## 日志级别影响

`enb.conf` 和 `ue.conf` 默认 `all_level=info`，会在每个 TTI 写入大量 PHY/MAC 日志。
在同一台主机同时运行 100 PRB eNB 和 UE 时，这会明显增加实时调度压力。

功能/吞吐测试使用：

```text
--log.all_level=warning --log.rf_level=info
```

保留 RF 错误统计的同时，避免每 TTI info 日志。对照测试中，关闭高频 info 日志后
TX Underflow 从 21 次降至 0（该轮仍有 41 个内核接收缓冲丢包）；随后增大 rmem 的一轮
实现了 `RcvbufErrors=0` 和 `RX TS mismatch=0`。

## 数据面结果

未增大 rmem、但降低日志量的一轮：

```text
ping:       10/10, 0% loss
downlink:   55.9 Mbit/s receiver
uplink:     18.0 Mbit/s receiver
RRC rebuild: 0
```

增大 rmem 后的确认轮：

```text
ping:       10/10, 0% loss
downlink:   48.3 Mbit/s receiver
uplink:     16.7 Mbit/s receiver
RcvbufErrors increment: 0
RX TS mismatch: 0
```

确认轮出现两次 UE TX Underflow/RRC 重建；日志同时显示 UE SNR 下降到约 2.6--2.9 dB，
因此剩余稳定性问题应继续从射频链路余量、参考时钟和实时 TX 调度排查，不能再归因于
千兆链路吞吐不足。

## 关键日志

当前驱动的首次 100 PRB attach 基线：

```text
/tmp/e200_pair_100prb_current_enb.log
/tmp/e200_pair_100prb_current_enb.console
/tmp/e200_pair_100prb_current_ue.log
/tmp/e200_pair_100prb_current_ue.console
```

低日志量吞吐测试：

```text
/tmp/e200_pair_100prb_warn_enb.log
/tmp/e200_pair_100prb_warn_ue.log
/tmp/e200_pair_100prb_warn_ping.log
/tmp/e200_pair_100prb_warn_dl_client.log
/tmp/e200_pair_100prb_warn_ul_client.log
```

增大 rmem 后的确认测试：

```text
/tmp/e200_pair_100prb_rmem_enb.log
/tmp/e200_pair_100prb_rmem_ue.log
/tmp/e200_pair_100prb_rmem_ping.log
/tmp/e200_pair_100prb_rmem_dl_client.log
/tmp/e200_pair_100prb_rmem_ul_client.log
/tmp/e200_pair_100prb_rmem_socket_state.log
```
