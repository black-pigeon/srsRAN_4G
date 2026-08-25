# E200 eNB + E100 UE：6 PRB 反向角色验证记录

验证日期：2026-08-24

## 验证结论

交换 E100/E200 的 eNB 和 UE 角色后，通信同样成功：

- eNB：E200，`192.168.10.122`
- UE：E100，`192.168.1.10`
- 6 PRB，1.92 MSps，EARFCN 3350
- 两端使用内部参考时钟
- E100 UE 完成小区搜索、PLMN、PRACH、RRC 和 EPC attach
- UE 地址：`172.16.0.6/24`
- `ue1` 内 ping `172.16.0.1`：3 发 3 收，0% 丢包
- RRC IDLE 后重新触发 Service Request 成功

## 关键参数

配置文件为 `profiles/e200_enb_e100_ue_6prb.conf`：

```text
E200_ENB_TIME_ADV_NSAMPLES=0
E200_ENB_RX_GAIN=40
E200_TIME_ADV_NSAMPLES=264
E200_UE_TX_GAIN=50
```

使用 215 时，E200 eNB 检出的 PRACH preamble 稳定为 E100 UE 发送序号减 1，
无法接入。将 E100 UE 的补偿增加 49 个 1.92 MSps 样点，即设置为 264 后，首次
PRACH 即完成接入。该 264 是 E100 UE 当前 TX pipeline 的校准值，不应套用到
E200 UE。

## 复现命令

```bash
cd /home/wcc/wcc_demo/sdr_opensource/srs_system/srsRAN_4G
sudo ./e200_demo/run_epc.sh
sudo ./e200_demo/run_enb.sh --profile e200_enb_e100_ue_6prb
sudo ./e200_demo/run_ue.sh --profile e200_enb_e100_ue_6prb
```

数据面验证：

```bash
sudo ip netns exec ue1 ping -c 3 172.16.0.1
```

本次没有修改 srsRAN 源码。E100 自动使用 IQTAXI UHD 插件中的逐 timed-send
SOB/EOB burst 行为。
