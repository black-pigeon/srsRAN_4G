# E200 75 PRB iperf3 吞吐测试（2026-08-15）

## 条件

- LTE：75 PRB，15.36 MSps，Band 7，EARFCN 3350，SISO
- reference：internal
- TX：strict timestamp
- UE：`time_adv_nsamples=215`，地址 `172.16.0.2`
- EPC TUN：`172.16.0.1`
- 工具：iperf3，单 TCP 流，跳过最初 2 秒，统计 20 秒

服务端和客户端都显式绑定 LTE TUN 地址；UE 端命令在 `ue1` network namespace
内执行，因此测试流量经过 LTE bearer，而不是两块 E200 的管理网口。

## 下行：EPC 到 UE

UE 端启动服务端：

```bash
sudo ip netns exec ue1 iperf3 -s -1 -B 172.16.0.2
```

EPC 主机发起客户端：

```bash
iperf3 -c 172.16.0.2 -B 172.16.0.1 -t 20 -O 2 -i 1
```

结果：

```text
sender:   78.8 MiB, 33.0 Mbit/s, 162 retransmissions
receiver: 79.0 MiB, 33.0 Mbit/s
```

## 上行：UE 到 EPC

EPC 主机启动服务端：

```bash
iperf3 -s -1 -B 172.16.0.1
```

UE namespace 发起客户端：

```bash
sudo ip netns exec ue1 \
  iperf3 -c 172.16.0.1 -B 172.16.0.2 -t 20 -O 2 -i 1
```

结果：

```text
sender:   61.5 MiB, 25.8 Mbit/s, 27 retransmissions
receiver: 61.5 MiB, 25.7 Mbit/s
```

## 运行状态

两轮 TCP 均完整结束。两轮切换、上行开始附近（日志时间
`2026-08-15T10:30:18`）UE 出现一次 RF underflow，并触发一次 RRC radio-link
failure；约 0.3 秒内 connection re-establishment 成功，iperf3 随后继续并完成。
TUN 接口未报告 packet error/drop。

因此当前可以把 75 PRB 的单流 TCP 实测能力记录为下行约 33.0 Mbit/s、上行约
25.8 Mbit/s；但这不是“无实时错误的持续稳定吞吐”。后续长测应同时记录
iperf3 吞吐、TCP retransmission、RF underflow/overflow/late 和 RRC 重建次数。
