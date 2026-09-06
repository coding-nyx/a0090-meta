# microSD (/DATA) benchmark

Measured 2026-09-06 on hub-11, kernel `6.18.49-hub11`, DTB `rk3588-hub11.dtb`
(`&sdmmc` with `sd-uhs-sdr104`, `vqmmc-supply = <&vccio_sd_s0>`). Raw fio
JSON in `docs/benchmarks/sd-2026-09-06/`.

## Card

| field | value |
|---|---|
| model | `SM256` (SanDisk, manfid 0x03, oemid `SD`), 238.4 GiB, SDXC |
| manufactured | 12/2025, fw 0x7, hw 0x8 |
| filesystem | ext4, label `DATA`, UUID `3943a4bd-833e-4182-a71d-435f7b23f0d4` |
| negotiated mode | `sd uhs SDR104`, 1.80 V signalling, 198 MHz actual clock (200 MHz requested) |

The vendor DTB ran the slot at 3.3 V high-speed (50 MHz, roughly 20 MB/s
ceiling); the mainline DTS enables UHS-I.

## Results

`hdparm -t --direct /dev/mmcblk1`, three runs: 88.05 / 88.06 / 88.04 MB/s.

fio, `--direct=1 --ioengine=libaio`, 1 GiB file on /DATA:

| test | pattern | throughput | IOPS | avg latency | p99 latency |
|---|---|---|---|---|---|
| seqread | 1 MiB, qd4 | 88.2 MiB/s | 88 | 45 ms | 51 ms |
| seqwrite | 1 MiB, qd4, end_fsync | 76.4 MiB/s | 76 | 52 ms | 63 ms |
| randread4k | 4 KiB, qd16, 45 s | 13.2 MiB/s | 3391 | 4.7 ms | 5.1 ms |
| randwrite4k | 4 KiB, qd16, 45 s | 3.1 MiB/s | 787 | 20 ms | 71 ms |

Reads sit at the practical SDR104 limit for this card class (interface ceiling
about 104 MB/s). Random 4 KiB writes are the weak spot, as with any consumer
microSD; keep databases, container image layers and swap off the card (swap is
zram on this box).

## Reproduce

```
sudo apt install fio hdparm
sudo hdparm -t --direct /dev/mmcblk1
sudo fio --name=seqwrite --filename=/DATA/bench/fio.1g --size=1G --bs=1M --rw=write  --direct=1 --ioengine=libaio --iodepth=4 --end_fsync=1 --output-format=json
sudo fio --name=seqread  --filename=/DATA/bench/fio.1g --size=1G --bs=1M --rw=read   --direct=1 --ioengine=libaio --iodepth=4 --output-format=json
sudo fio --name=randread4k  --filename=/DATA/bench/fio.1g --size=1G --bs=4k --rw=randread  --direct=1 --ioengine=libaio --iodepth=16 --runtime=45 --time_based --output-format=json
sudo fio --name=randwrite4k --filename=/DATA/bench/fio.1g --size=1G --bs=4k --rw=randwrite --direct=1 --ioengine=libaio --iodepth=16 --runtime=45 --time_based --output-format=json
sudo cat /sys/kernel/debug/mmc1/ios
```

If the card ever shows tuning errors or I/O errors in `dmesg` at SDR104, build
the FIT with `HUB11_DTB=rk3588-hub11-sdhs.dtb` (3.3 V high-speed only) and
re-run this table for comparison.
