# ANTSDR E200 + E316 本地 UHD / srsRAN 4G

从零部署请阅读 [DEPLOY_CN.md](DEPLOY_CN.md)，英文请阅读
[README_EN.md](README_EN.md) 和 [DEPLOY_EN.md](DEPLOY_EN.md)。

当前固定角色：**E200 做 eNB，E316 做 UE**。

| 项目 | 当前值 |
|---|---|
| E200 eNB | SDR `192.168.1.10`，PC 网卡 `eth2` |
| E316 UE | SDR `192.168.10.122`，PC 网卡 `eth0` |
| LTE | Band 7，EARFCN 2900，DL `2635 MHz`，UL `2515 MHz` |
| srsRAN | `black-pigeon/srsRAN_4G` 的 `release_25_10` 分支，验证基线 commit `6bcbd9e5b` |
| UHD | `/opt/antsdr-uhd`，`UHD_4.1.0.0-0-45cabfde` |
| UHD 源码 | MicroPhase `antsdr_uhd`，commit `b5ebd04a5f405ac3102a772e5d1e8f1be21a7dc3` |
| 固件 | `firmware/build_sdimg_e200.zip` 和 `firmware/build_sdimg_e316.zip` |

固件 bitstream 分别为 `antsdr_e200`、`antsdr_e310v2`，Vivado 版本为 `2019.1`；
当前设备报告 FPGA version `16.0`。E200 和 E316 不能交叉使用固件。以太网只传输 IQ，
RF 必须通过屏蔽箱内天线或两条带衰减的射频链路连接。

## 启动

```bash
cd /home/wcc/mp_demo/SDR-APP/srsRAN_4G
antsdr_demo/run_epc.sh
antsdr_demo/run_enb.sh --profile 25prb
antsdr_demo/run_ue.sh --profile 25prb
```

启动脚本通过 `antsdr_demo/env.sh` 隔离系统 UHD 4.9，使用本地 UHD 的
`PATH`、`LD_LIBRARY_PATH` 和 `UHD_IMAGES_DIR`。启动 banner 应出现
`UHD_4.1.0.0-0-45cabfde`。

## 已验证档位

| Profile | 主机 IQ 采样率 | eNB / UE `time_adv_nsamples` | 结果 |
|---|---:|---:|---|
| `6prb` | 1.92 MSPS | `49 / 67` | attach，ping 10/10 |
| `15prb` | 3.84 MSPS | `25 / 83` | attach，ping 10/10 |
| `25prb` | 5.76 MSPS | `0 / 100` | attach，ping 10/10 |

切换档位时停止 UE 和 eNB，EPC 可以保持运行：

```bash
antsdr_demo/run_enb.sh --profile 15prb
antsdr_demo/run_ue.sh --profile 15prb
```

UE attach 成功后必须在 `ue1` namespace 内验证用户面：

```bash
sudo ip netns exec ue1 ip addr show tun_srsue
sudo ip netns exec ue1 ping -c 10 -i 0.3 -W 2 172.16.0.1
```

50 PRB（11.52 MSPS）在当前主机上尚未完成小区搜索，因此不标记为已验证配置。
高采样率问题需要继续检查主机实时性、UHD 缓冲和以太网传输，不能只修改时间补偿。

## 直接 UHD 测试

```bash
source antsdr_demo/env.sh
/opt/antsdr-uhd/lib/uhd/examples/benchmark_rate \
  --args "type=ant,addr=192.168.1.10" --duration 8 \
  --rx_rate 5.76e6 --tx_rate 5.76e6 --rx_spp 360 --tx_spp 360 \
  --rx_channels 0 --tx_channels 0
```

同一块 ANTSDR 不要同时运行多个 UHD handle；测试结束后再启动 srsRAN。
