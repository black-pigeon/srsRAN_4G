# E200 25 PRB strict timestamp 验证结果

- 日期：2026-08-15
- LTE：Band 7，EARFCN 3350，25 PRB，5.76 MSps，单天线
- eNB E200：192.168.1.10
- UE E200：192.168.10.2
- 两板参考源：external 10 MHz
- strict TX timestamps：启用（`ignore_tx_timestamps=false`）
- eNB/UE RX gain：40 dB
- UE `time_adv_nsamples`：215

## 结果

- 速率切换 1.92→5.76→1.92→5.76 MSps 全部准确回读。
- 每次重配期间设备 sample time 仅前进约 0.4 ms，无倒退、无 2.5 s 空洞。
- UE 完成小区搜索、SIB/PLMN 解码、一次 PRACH 接入和 EPC attach。
- 首次成功 PRACH：UE preamble=48，eNB preamble=48，offset=0。
- 五次空闲态 Service Request 均一次 PRACH 成功，offset=0。
- 控制台未出现 TX underflow、late、RX overflow 或 time-going-backwards。
- 上行抓包：5/5 ICMP 请求从 `tun_srsue` 经空口到达 `srs_spgw_sgi`。
- 下行抓包：10/10 ICMP 请求从 `srs_spgw_sgi` 经空口到达 `tun_srsue`。

## 验证版本

```text
e200_v25_server  7d456f03b044f7a450a40dffbb6b9ff1dd7dd4294f065abfeb513a0a3226657c
libIQTaxiUHD.so  bfceb49dd1d32b6b6f25d7d5baeff7242241a27e741793ae2106e638b23160fc
```

两板当前根挂载类型为 `rootfs`，不是直接挂载的 SD ext 文件系统。因此把
`e200_v25_server` 安装到运行中的 `/usr/sbin` 只保证当前启动周期；若启动镜像
尚未固化该版本，板子重启后必须重新部署，或把该二进制写入持久化启动镜像。
