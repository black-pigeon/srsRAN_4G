# 6 PRB FIR128 SD 镜像冷启动验证

验证日期：2026-08-15

## 固件

- 两块 E200 均通过 `e200-sd.frm` 在线更新并重启；
- 两板均由 `/usr/sbin/e200_v25_server` 自动启动；
- server SHA256：`436172dce148924d6bbe67a915b98c9b4e53da80baf94f582d792dbabd94e80e`；
- FPGA bit SHA256：`c8d44d13bbbe28f262c0394295ac4418fe0a223ea755196d1adaa2794dd83744`；
- 未运行 `/tmp/e200_v25_server.fir128` 或其他临时下位机。

## LTE 配置

- srsRAN_4G tracked 源码无修改，commit `ec29b0c1ff79`；
- Band 7 / EARFCN 3350；
- 6 PRB / 1.92 MSps；
- internal reference；
- strict timed TX；
- `time_adv_nsamples=215`；
- RX gain 40 dB。

## 结果

- UE 找到 PCI 1、6 PRB 小区，初始 CFO 3.0 kHz；
- UE 完成 PLMN、PRACH、RRC、authentication、security mode 和 attach；
- UE 地址：`172.16.0.4/24`；
- eNB 首次 PRACH：preamble 9、offset 27；
- 后续 service request PRACH：preamble 3、offset 29；
- UE→EPC：10/10，0% loss；
- EPC→UE：10/10，0% loss。

UE 启动初期记录了一次 RX timestamp jump/overflow，PHY 自动重同步后完成
attach；没有持续 overflow。会话结束导致 eNB/UE 日志末尾各记录了一次
underflow，它发生在已完成上述验证之后，不属于 attach 过程中的持续故障。
