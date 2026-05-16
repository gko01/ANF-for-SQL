# Azure VM Discovery and Performance Report

Generated: 2026-04-10  
Subscriptions:  
- RioTinto-CA-Production (fc78d23e-3972-40bc-a96e-80841a2d101c)  
- RioTinto-CA-Non-Production (393a132a-f2bb-44e5-936e-bd25f7a6e05a)

## Table of Contents

- [Executive Summary](#executive-summary)
- [Inventory and Capabilities](#inventory-and-capabilities)
- [Compute Analysis by VM (7/30/90 Days) — Production](#compute-analysis-by-vm-73090-days--production)
- [Disk Analysis by VM (7/30/90 Days) — Production](#disk-analysis-by-vm-73090-days--production)
- [Cross-VM Comparison — Production](#cross-vm-comparison--production)
- [Compute Analysis by VM (7/30/90 Days) — Non-Production](#compute-analysis-by-vm-73090-days--non-production)
- [Disk Analysis by VM (7/30/90 Days) — Non-Production](#disk-analysis-by-vm-73090-days--non-production)
- [Cross-VM Comparison — Non-Production](#cross-vm-comparison--non-production)
- [Configuration and SLA Reference](#configuration-and-sla-reference)
- [Structure Notes for Future Updates](#structure-notes-for-future-updates)

## Executive Summary

### Production (RioTinto-CA-Production)
- 4 VMs found: CATORHYPSQL1, CATORSQL17, CATORSQL5, CATORSQL6.
- CPU utilization is stable and generally low to moderate across all VMs.
- Memory is the primary risk area on CATORHYPSQL1 and CATORSQL6, with peaks around 95%.
- CATORSQL5 remains the healthiest overall VM with stable CPU and good memory headroom.
- Disk usage is stable across 90 days; hotspots are concentrated on a single primary data disk per VM.
- Highest-priority follow-up remains memory pressure monitoring and capacity planning on CATORSQL6 and CATORHYPSQL1.

### Non-Production (RioTinto-CA-Non-Production)
- 4 VMs found: CATORHYPSQLC1, CATORHYPSQLD1, CATORSQLD2, CATORSQLD5.
- CPU is low across all NPE VMs except CATORSQLD5 (16% avg on a 2-vCPU VM, peaks near 50%).
- Memory is elevated on CATORHYPSQLC1, CATORHYPSQLD1, and CATORSQLD5 (all >80% avg); CATORSQLD5 peaks at 91.44% on only 8 GiB.
- CATORSQLD2 is the healthiest NPE VM with comfortable CPU and memory headroom.
- Disk I/O is stable and low across all NPE VMs; LUN 0 is the burst hotspot on CATORHYPSQLC1 and CATORHYPSQLD1, LUN 4 is the hotspot on CATORSQLD5.
- **Disk space alert:** CATORHYPSQLC1 J: (SQL-BACKUP) peaks at 97.34% used with only 6.81 GiB free at minimum — mirrors the same backup drive pressure seen on Production CATORHYPSQL1.
- CATORHYPSQLD1 all drives healthy (<49% peak). CATORSQLD2 has the healthiest disk space profile. CATORSQLD5 disk space pending.

## Inventory and Capabilities

### Requested VMs

#### Found — Production
- CATORHYPSQL1
- CATORSQL17
- CATORSQL5
- CATORSQL6

#### Found — Non-Production
- CATORHYPSQLC1
- CATORHYPSQLD1
- CATORSQLD2
- CATORSQLD5

### VM SKU Capability Table — Production

| VM Name | VM SKU | CPU (vCPU) | Memory (GiB) | Max IOPS | Max Throughput |
|---|---|---:|---:|---:|---:|
| CATORHYPSQL1 | Standard_D8s_v3 | 8 | 32 | 12,800 | 192 MB/s |
| CATORSQL17 | Standard_B8ms | 8 | 32 | 4,320 | 50 MB/s |
| CATORSQL5 | Standard_D4s_v3 | 4 | 16 | 6,400 | 96 MB/s |
| CATORSQL6 | Standard_D4s_v3 | 4 | 16 | 6,400 | 96 MB/s |

### VM SKU Capability Table — Non-Production

| VM Name | VM SKU | CPU (vCPU) | Memory (GiB) | Max IOPS | Max Throughput |
|---|---|---:|---:|---:|---:|
| CATORHYPSQLC1 | Standard_D8s_v3 | 8 | 32 | 12,800 | 192 MB/s |
| CATORHYPSQLD1 | Standard_D8s_v3 | 8 | 32 | 12,800 | 192 MB/s |
| CATORSQLD2 | Standard_D4s_v3 | 4 | 16 | 6,400 | 96 MB/s |
| CATORSQLD5 | Standard_D2s_v3 | 2 | 8 | 3,200 | 48 MB/s |

### Disk SKU Capability Table

| Disk SKU | Max IOPS | Max Throughput |
|---|---:|---:|
| Premium_LRS | 20,000 | 900 MB/s |
| StandardSSD_LRS | 6,000 | 750 MB/s |

### Disk Size Impact on Performance

Important: IOPS and throughput are provisioned based on disk size. The tables below show only the disk sizes currently in use in this environment.

#### Premium_LRS - Performance by Disk Size (In Use)
| Disk Size | Base IOPS | Base Throughput |
|---|---:|---:|
| 64 GiB | 240 | 50 MB/s |
| 127 GiB | ~500 | ~100 MB/s |
| 128 GiB | 500 | 100 MB/s |
| 256 GiB | 1,100 | 125 MB/s |

#### StandardSSD_LRS - Performance by Disk Size (In Use)
| Disk Size | Base IOPS | Base Throughput |
|---|---:|---:|
| 60 GiB | Up to 500 | Up to 100 MB/s |
| 64 GiB | Up to 500 | Up to 100 MB/s |
| 127 GiB | Up to 500 | Up to 100 MB/s |
| 128 GiB | Up to 500 | Up to 100 MB/s |
| 256 GiB | Up to 500 | Up to 100 MB/s |

Note: None of the current disk sizes exceed thresholds for expanded/performance-plus IOPS.

## Compute Analysis by VM (7/30/90 Days) — Production

### CATORHYPSQL1

#### CPU Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average CPU Utilization | 2.90% | 3.54% | 3.66% | Slight increase, still very low |
| Maximum CPU Utilization | 6.42% | 11.18% | 11.91% | Stable low peaks |

#### Memory Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average Memory Utilization | 85.15% | 81.58% | 81.72% | Stable elevated |
| Maximum Memory Utilization | 93.56% | 94.86% | 94.38% | Stable high peaks |

Summary: Compute is not constrained by CPU; memory remains the key risk.

### CATORSQL17

#### CPU Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average CPU Utilization | 6.40% | 6.51% | 6.51% | Stable |
| Maximum CPU Utilization | 24.22% | 32.11% | 33.97% | Slight increase |

#### Memory Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average Memory Utilization | 80.81% | 79.75% | 79.78% | Stable elevated |
| Maximum Memory Utilization | 82.62% | 84.50% | 84.31% | Stable |

Summary: CPU is healthy; memory is consistently elevated and should be watched.

### CATORSQL5

#### CPU Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average CPU Utilization | 8.89% | 8.70% | 8.69% | Stable |
| Maximum CPU Utilization | 26.69% | 28.36% | 34.09% | Slight increase |

#### Memory Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average Memory Utilization | 65.69% | 63.62% | 63.62% | Stable healthy |
| Maximum Memory Utilization | 66.75% | 66.75% | 66.69% | Stable |

Summary: Best-balanced VM with consistent compute headroom.

### CATORSQL6

#### CPU Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average CPU Utilization | 12.82% | 13.02% | 13.00% | Stable highest in group |
| Maximum CPU Utilization | 32.43% | 32.43% | 33.47% | Stable |

#### Memory Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average Memory Utilization | 72.94% | 70.56% | 70.62% | Stable elevated |
| Maximum Memory Utilization | 94.94% | 94.94% | 94.88% | Stable critical peaks |

Summary: Highest sustained CPU and critical memory peaks; priority for capacity planning.

## Disk Analysis by VM (7/30/90 Days) — Production

Method used for all VMs:
- IOPS = Read Operations/Sec + Write Operations/Sec
- Throughput = Read Bytes/sec + Write Bytes/sec
- Per-disk split = OS disk metrics + data disk metrics split by LUN
- Aggregation = Hourly averages across each window, then average and maximum

### CATORHYPSQL1

#### Aggregate Disk IOPS and Throughput
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average IOPS | 3.20 | 3.00 | 2.98 | Stable low |
| Maximum IOPS | 82.88 | 82.88 | 82.88 | Stable burst ceiling |
| Average Throughput | 1.21 MB/s | 1.19 MB/s | 1.19 MB/s | Stable low |
| Maximum Throughput | 11.85 MB/s | 13.02 MB/s | 13.02 MB/s | Slightly higher long-window peaks |

#### Per-Disk Breakdown

##### 7-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 14.57 | 53.98 | 0.75 | 2.74 |
| CATORHYPSQL1-disk01 | 0 | 0.28 | 45.25 | 0.02 | 2.78 |
| CATORHYPSQL1-disk02 | 1 | 1.70 | 36.31 | 1.44 | 34.05 |
| CATORHYPSQL1-disk03 | 2 | 0.45 | 9.76 | 0.03 | 1.07 |
| CATORHYPSQL1-disk04 | 3 | 0.00 | 0.04 | 0.00 | 0.01 |
| CATORHYPSQL1-disk05 | 4 | 3.36 | 306.44 | 0.82 | 17.02 |

##### 30-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 14.29 | 110.22 | 0.73 | 5.19 |
| CATORHYPSQL1-disk01 | 0 | 0.28 | 45.58 | 0.03 | 9.14 |
| CATORHYPSQL1-disk02 | 1 | 1.70 | 38.11 | 1.44 | 36.34 |
| CATORHYPSQL1-disk03 | 2 | 0.31 | 63.68 | 0.02 | 6.84 |
| CATORHYPSQL1-disk04 | 3 | 0.00 | 0.04 | 0.00 | 0.01 |
| CATORHYPSQL1-disk05 | 4 | 3.07 | 306.44 | 0.82 | 18.16 |

##### 90-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 14.24 | 110.22 | 0.73 | 5.19 |
| CATORHYPSQL1-disk01 | 0 | 0.27 | 45.58 | 0.03 | 9.14 |
| CATORHYPSQL1-disk02 | 1 | 1.70 | 38.11 | 1.44 | 36.34 |
| CATORHYPSQL1-disk03 | 2 | 0.31 | 63.68 | 0.02 | 6.84 |
| CATORHYPSQL1-disk04 | 3 | 0.00 | 0.04 | 0.00 | 0.01 |
| CATORHYPSQL1-disk05 | 4 | 3.00 | 306.44 | 0.82 | 18.16 |

#### Disk Space Utilization (7-Day Guest Metrics)
| Drive | Size GiB | Avg Used GiB | Max Used GiB | Avg Free GiB | Min Free GiB | Avg Used % | Max Used % | Risk |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| C: | 126.51 | 67.05 | 67.23 | 59.46 | 59.28 | 53.00% | 53.15% | Medium |
| F: | 127.98 | 67.76 | 67.78 | 60.22 | 60.20 | 52.95% | 52.96% | Medium |
| J: | 255.98 | 132.16 | 245.90 | 123.82 | 10.08 | 51.63% | 96.06% | High |
| G: | 127.98 | 33.12 | 33.12 | 94.86 | 94.86 | 25.88% | 25.88% | Low |
| D: | 64.00 | 5.86 | 6.01 | 58.14 | 57.99 | 9.15% | 9.39% | Low |
| H: | 127.98 | 5.47 | 5.47 | 122.51 | 122.51 | 4.27% | 4.27% | Low |
| I: | 59.98 | 0.14 | 0.14 | 59.84 | 59.84 | 0.23% | 0.23% | Low |

Findings:
- OS disk carries steady baseline IOPS.
- LUN 1 carries highest sustained throughput.
- LUN 4 is the burst hotspot by max IOPS.
- J: is the only filesystem capacity concern, with minimum free space dropping to 10.08 GiB and peak utilization reaching 96.06% over the last 7 days.
- C: and F: are both around 67 GiB used with roughly 60 GiB free, indicating moderate but stable utilization.
- D:, G:, H:, and I: have substantial free capacity and low utilization risk.

### CATORSQL17

#### Aggregate Disk IOPS and Throughput
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average IOPS | 9.40 | 9.46 | 9.41 | Stable |
| Maximum IOPS | 159.44 | 166.23 | 166.23 | Stable |
| Average Throughput | 1.56 MB/s | 1.55 MB/s | 1.54 MB/s | Stable |
| Maximum Throughput | 24.52 MB/s | 25.27 MB/s | 25.27 MB/s | Stable |

#### Per-Disk Breakdown

##### 7-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 18.67 | 33.28 | 0.83 | 1.72 |
| CATORSQL17-datadisk01 | 0 | 0.01 | 0.16 | 0.00 | 0.01 |
| CATORSQL17-datadisk02 | 1 | 14.85 | 178.71 | 0.33 | 5.23 |
| CATORSQL17-datdisk03 | 2 | 2.46 | 51.81 | 1.25 | 25.46 |
| CATORSQL17-datadisk04 | 3 | 26.07 | 504.98 | 1.91 | 55.50 |
| CATORSQL17-datdisk05 | 4 | 3.38 | 51.56 | 0.18 | 3.03 |

##### 30-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 18.34 | 120.18 | 0.81 | 5.06 |
| CATORSQL17-datadisk01 | 0 | 0.02 | 3.48 | 0.00 | 0.66 |
| CATORSQL17-datadisk02 | 1 | 15.29 | 186.54 | 0.35 | 9.81 |
| CATORSQL17-datdisk03 | 2 | 2.47 | 52.69 | 1.25 | 25.82 |
| CATORSQL17-datadisk04 | 3 | 26.54 | 599.60 | 1.90 | 61.30 |
| CATORSQL17-datdisk05 | 4 | 3.19 | 51.92 | 0.17 | 3.14 |

##### 90-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 18.31 | 120.18 | 0.81 | 5.06 |
| CATORSQL17-datadisk01 | 0 | 0.02 | 3.48 | 0.00 | 0.66 |
| CATORSQL17-datadisk02 | 1 | 15.31 | 186.54 | 0.35 | 9.81 |
| CATORSQL17-datdisk03 | 2 | 2.47 | 52.69 | 1.25 | 25.82 |
| CATORSQL17-datadisk04 | 3 | 26.25 | 599.60 | 1.88 | 61.30 |
| CATORSQL17-datdisk05 | 4 | 3.16 | 51.92 | 0.16 | 3.14 |

Findings:
- LUN 3 is the primary hotspot disk.
- LUN 1 contributes moderate sustained IOPS.
- 30-day and 90-day behavior is stable.

#### Disk Space Utilization (7-Day Guest Metrics)
| Drive | Size GiB | Avg Used GiB | Max Used GiB | Avg Free GiB | Min Free GiB | Avg Used % | Max Used % | Risk |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| H: | 63.98 | 42.51 | 42.51 | 21.47 | 21.47 | 66.44% | 66.44% | Medium |
| J: | 255.98 | 166.05 | 182.60 | 89.93 | 73.38 | 64.87% | 71.33% | Medium |
| F: | 255.98 | 157.51 | 157.53 | 98.47 | 98.45 | 61.53% | 61.54% | Medium |
| G: | 127.98 | 75.35 | 75.37 | 52.63 | 52.61 | 58.87% | 58.89% | Medium |
| C: | 126.45 | 64.67 | 64.78 | 61.78 | 61.67 | 51.14% | 51.23% | Medium |
| E: | 127.98 | 17.89 | 17.89 | 110.09 | 110.09 | 13.98% | 13.98% | Low |
| D: | 64.00 | 4.91 | 5.07 | 59.09 | 58.93 | 7.66% | 7.92% | Low |

Disk Space Findings:
- All drives show stable utilization with no critical peaks.
- H: is the most utilized at 66.44%, with 21.47 GiB free — the smallest free headroom in the group.
- J: and F: are both large 256 GiB drives at ~62-65% utilized with healthy absolute free space.
- G: and C: are moderate at ~51-59% with comfortable headroom.
- E: and D: are lightly utilized and low risk.

### CATORSQL5

#### Aggregate Disk IOPS and Throughput
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average IOPS | 15.85 | 15.83 | 15.75 | Stable |
| Maximum IOPS | 86.73 | 96.77 | 96.77 | Stable |
| Average Throughput | 2.34 MB/s | 2.33 MB/s | 2.31 MB/s | Stable |
| Maximum Throughput | 9.91 MB/s | 13.74 MB/s | 13.74 MB/s | Stable |

#### Per-Disk Breakdown

##### 7-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 18.52 | 38.12 | 0.86 | 1.88 |
| CATORSQL5-disk02 | 1 | 0.87 | 18.52 | 0.49 | 10.88 |
| CATORSQL5-disk03 | 2 | 58.72 | 310.83 | 3.87 | 19.45 |
| CATORSQL5-disk04 | 3 | 1.04 | 37.42 | 0.06 | 1.04 |

##### 30-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 16.55 | 92.88 | 0.81 | 4.66 |
| CATORSQL5-disk02 | 1 | 0.88 | 18.59 | 0.51 | 12.05 |
| CATORSQL5-disk03 | 2 | 59.98 | 502.84 | 3.97 | 30.37 |
| CATORSQL5-disk04 | 3 | 1.56 | 184.44 | 0.08 | 5.56 |

##### 90-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 16.38 | 92.88 | 0.80 | 4.66 |
| CATORSQL5-disk02 | 1 | 0.88 | 18.59 | 0.51 | 12.05 |
| CATORSQL5-disk03 | 2 | 59.76 | 502.84 | 3.95 | 30.37 |
| CATORSQL5-disk04 | 3 | 1.53 | 184.44 | 0.08 | 5.56 |

Findings:
- LUN 2 is the dominant workload disk.
- LUN 3 has burst events but low sustained utilization.
- Long-window trends are stable.

### CATORSQL6

#### Aggregate Disk IOPS and Throughput
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average IOPS | 4.16 | 3.93 | 3.89 | Stable low |
| Maximum IOPS | 132.12 | 132.12 | 132.12 | Stable |
| Average Throughput | 1.42 MB/s | 1.38 MB/s | 1.38 MB/s | Stable |
| Maximum Throughput | 13.57 MB/s | 13.57 MB/s | 13.57 MB/s | Stable |

#### Per-Disk Breakdown

##### 7-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 18.25 | 68.44 | 0.91 | 3.06 |
| CATORSQL6-disk01 | 0 | 0.00 | 0.03 | 0.00 | 0.00 |
| CATORSQL6-disk02 | 1 | 6.71 | 451.28 | 1.82 | 37.41 |
| CATORSQL6-disk03 | 2 | 0.88 | 18.29 | 0.74 | 17.61 |
| CATORSQL6-disk04 | 3 | 0.29 | 10.30 | 0.01 | 0.11 |
| CATORSQL6-disk05 | 4 | 0.00 | 0.31 | 0.00 | 0.02 |

##### 30-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 17.65 | 127.38 | 0.87 | 6.39 |
| CATORSQL6-disk01 | 0 | 0.00 | 0.05 | 0.00 | 0.00 |
| CATORSQL6-disk02 | 1 | 6.34 | 451.28 | 1.81 | 41.55 |
| CATORSQL6-disk03 | 2 | 0.88 | 20.19 | 0.74 | 19.75 |
| CATORSQL6-disk04 | 3 | 0.27 | 10.53 | 0.01 | 0.12 |
| CATORSQL6-disk05 | 4 | 0.01 | 1.78 | 0.00 | 0.63 |

##### 90-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 17.56 | 127.38 | 0.87 | 6.39 |
| CATORSQL6-disk01 | 0 | 0.00 | 0.05 | 0.00 | 0.00 |
| CATORSQL6-disk02 | 1 | 6.19 | 451.28 | 1.80 | 41.55 |
| CATORSQL6-disk03 | 2 | 0.88 | 20.19 | 0.74 | 19.75 |
| CATORSQL6-disk04 | 3 | 0.26 | 10.53 | 0.01 | 0.12 |
| CATORSQL6-disk05 | 4 | 0.01 | 1.78 | 0.00 | 0.63 |

Findings:
- LUN 1 is the recurring disk hotspot.
- LUN 0 and LUN 4 are near-idle.
- Disk behavior remains stable across 30 and 90 days.

#### Disk Space Utilization (7-Day Guest Metrics)
| Drive | Size GiB | Avg Used GiB | Max Used GiB | Avg Free GiB | Min Free GiB | Avg Used % | Max Used % | Risk |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| I: | 255.98 | 170.46 | 231.82 | 85.52 | 24.16 | 66.59% | 90.56% | High |
| F: | 255.98 | 143.32 | 143.32 | 112.66 | 112.66 | 55.99% | 55.99% | Medium |
| C: | 126.51 | 53.80 | 53.94 | 72.71 | 72.57 | 42.53% | 42.64% | Low |
| D: | 32.00 | 4.15 | 4.29 | 27.85 | 27.71 | 12.97% | 13.40% | Low |
| H: | 127.98 | 7.71 | 7.71 | 120.27 | 120.27 | 6.03% | 6.03% | Low |
| G: | 127.98 | 1.54 | 1.54 | 126.44 | 126.44 | 1.20% | 1.20% | Low |

Disk Space Findings:
- I: is the clear high-risk drive — average used 66.59% with peaks reaching 90.56%, leaving only 24.16 GiB free at worst. Requires immediate monitoring.
- F: is moderately used at 55.99% with 112.66 GiB free — stable and not at risk.
- C: is healthy at 42.53% with 72.57 GiB minimum free.
- D:, H:, and G: are lightly used with substantial free capacity.

## Cross-VM Comparison — Production

### CPU Utilization Trends
| VM | 7-Day Avg | 30-Day Avg | 90-Day Avg | 90-Day Trend |
|---|---:|---:|---:|---|
| CATORHYPSQL1 | 2.90% | 3.54% | 3.66% | Slight increase but stable |
| CATORSQL17 | 6.40% | 6.51% | 6.51% | Completely stable |
| CATORSQL5 | 8.89% | 8.70% | 8.69% | Completely stable |
| CATORSQL6 | 12.82% | 13.02% | 13.00% | Completely stable |

### Memory Utilization Trends
| VM | 7-Day Avg | 30-Day Avg | 90-Day Avg | 90-Day Trend | Risk Level |
|---|---:|---:|---:|---|---|
| CATORHYPSQL1 | 85.15% | 81.58% | 81.72% | Stable, consistently high | Medium-High |
| CATORSQL17 | 80.81% | 79.75% | 79.78% | Stable, consistently high | Medium |
| CATORSQL5 | 65.69% | 63.62% | 63.62% | Stable, healthy | Low |
| CATORSQL6 | 72.94% | 70.56% | 70.62% | Stable, elevated | Medium-High |

### Peak Performance Analysis (90-Day Max)
| VM | CPU Peak | Memory Peak | Constraint Risk |
|---|---:|---:|---|
| CATORHYPSQL1 | 11.91% | 94.38% | High (memory spikes) |
| CATORSQL17 | 33.97% | 84.31% | Medium |
| CATORSQL5 | 34.09% | 66.69% | Low |
| CATORSQL6 | 33.47% | 94.88% | High (memory spikes) |

### 30-Day Baseline Snapshot
| VM | Avg CPU | Max CPU | Avg Mem | Max Mem | Health Status |
|---|---:|---:|---:|---:|---|
| CATORHYPSQL1 | 3.54% | 11.18% | 81.58% | 94.86% | Good - Monitor memory |
| CATORSQL17 | 6.51% | 32.11% | 79.75% | 84.50% | Good - Memory elevated |
| CATORSQL5 | 8.70% | 28.36% | 63.62% | 66.75% | Excellent - Well balanced |
| CATORSQL6 | 13.02% | 32.43% | 70.56% | 94.94% | Fair - Watch CPU and memory |

## Compute Analysis by VM (7/30/90 Days) — Non-Production

### CATORHYPSQLC1

#### CPU Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average CPU Utilization | 3.02% | 3.01% | 3.01% | Stable very low |
| Maximum CPU Utilization | 6.61% | 9.43% | 9.43% | Stable low peaks |

#### Memory Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average Memory Utilization | 84.81% | 82.38% | 82.45% | Stable elevated |
| Maximum Memory Utilization | 92.16% | 93.59% | 93.59% | Stable high peaks |

Summary: Very similar profile to Production CATORHYPSQL1. CPU is idle; memory is the constraint with peaks over 93%.

### CATORHYPSQLD1

#### CPU Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average CPU Utilization | 2.13% | 2.15% | 2.15% | Stable very low |
| Maximum CPU Utilization | 3.75% | 8.52% | 8.52% | Stable low peaks |

#### Memory Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average Memory Utilization | 85.21% | 82.73% | 82.79% | Stable elevated |
| Maximum Memory Utilization | 93.44% | 93.74% | 93.74% | Stable high peaks |

Summary: Lowest CPU in the group; memory mirrors CATORHYPSQLC1 with peaks near 94%.

### CATORSQLD2

#### CPU Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average CPU Utilization | 7.72% | 7.76% | 7.75% | Stable |
| Maximum CPU Utilization | 15.51% | 24.58% | 24.58% | Moderate peaks |

#### Memory Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average Memory Utilization | 55.53% | 52.59% | 52.69% | Stable healthy |
| Maximum Memory Utilization | 57.19% | 57.38% | 57.38% | Stable |

Summary: Healthiest NPE VM with substantial compute headroom on both CPU and memory.

### CATORSQLD5

#### CPU Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average CPU Utilization | 16.39% | 16.04% | 16.06% | Stable highest in NPE |
| Maximum CPU Utilization | 45.41% | 49.54% | 49.54% | Moderate-high peaks |

#### Memory Utilization
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average Memory Utilization | 82.39% | 81.22% | 81.27% | Stable elevated |
| Maximum Memory Utilization | 88.59% | 91.44% | 91.44% | High peaks |

Summary: Smallest VM (2 vCPU, 8 GiB) running the heaviest workload. CPU peaks near 50% and memory peaks over 91%. Priority for rightsizing assessment.

## Disk Analysis by VM (7/30/90 Days) — Non-Production

Method used for all VMs:
- IOPS = Read Operations/Sec + Write Operations/Sec
- Throughput = Read Bytes/sec + Write Bytes/sec
- Per-disk split = OS disk metrics + data disk metrics split by LUN
- Aggregation = Hourly averages across each window, then average and maximum

### CATORHYPSQLC1

#### Aggregate Disk IOPS and Throughput
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average IOPS | 2.83 | 2.70 | 2.67 | Stable low |
| Maximum IOPS | 60.48 | 65.11 | 67.32 | Stable |
| Average Throughput | 2.76 MB/s | 2.74 MB/s | 2.74 MB/s | Stable low |
| Maximum Throughput | 44.22 MB/s | 44.79 MB/s | 44.79 MB/s | Stable |

#### Per-Disk Breakdown

##### 7-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 13.27 | 63.54 | 0.77 | 3.85 |
| CATORHYPSQLC1-SQL-DATA-F | 0 | 2.39 | 259.28 | 0.68 | 14.23 |
| CATORHYPSQLC1-SQL-LOGS-G | 1 | 0.31 | 0.59 | 0.00 | 0.01 |
| CATORHYPSQLC1-SQL-TEMP-H | 2 | 0.23 | 37.31 | 0.01 | 2.32 |
| CATORHYPSQLC1-SQL-INDEX-I | 3 | 0.00 | 0.04 | 0.00 | 0.01 |
| CATORHYPSQLC1-SQL-BACKUP-J | 4 | 1.44 | 30.79 | 1.19 | 28.47 |

##### 30-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 13.00 | 90.50 | 0.75 | 4.51 |
| CATORHYPSQLC1-SQL-DATA-F | 0 | 2.30 | 259.62 | 0.67 | 14.70 |
| CATORHYPSQLC1-SQL-LOGS-G | 1 | 0.31 | 0.92 | 0.00 | 0.02 |
| CATORHYPSQLC1-SQL-TEMP-H | 2 | 0.22 | 38.05 | 0.02 | 3.81 |
| CATORHYPSQLC1-SQL-INDEX-I | 3 | 0.00 | 0.17 | 0.00 | 0.01 |
| CATORHYPSQLC1-SQL-BACKUP-J | 4 | 1.44 | 31.95 | 1.19 | 29.41 |

##### 90-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 12.92 | 90.47 | 0.75 | 4.51 |
| CATORHYPSQLC1-SQL-DATA-F | 0 | 2.25 | 259.62 | 0.67 | 14.70 |
| CATORHYPSQLC1-SQL-LOGS-G | 1 | 0.31 | 0.92 | 0.00 | 0.02 |
| CATORHYPSQLC1-SQL-TEMP-H | 2 | 0.21 | 38.05 | 0.02 | 3.81 |
| CATORHYPSQLC1-SQL-INDEX-I | 3 | 0.00 | 0.17 | 0.00 | 0.01 |
| CATORHYPSQLC1-SQL-BACKUP-J | 4 | 1.44 | 31.95 | 1.19 | 29.41 |

Findings:
- LUN 0 (SQL-DATA-F) is the burst IOPS hotspot with peaks over 259.
- LUN 4 (SQL-BACKUP-J) carries the highest sustained throughput at 1.19 MB/s.
- LUN 1 (SQL-LOGS-G) and LUN 3 (SQL-INDEX-I) are near-idle.
- All trends are stable across 90 days.

#### Disk Space Utilization (7-Day Guest Metrics)
| Drive | Size GiB | Avg Used GiB | Max Used GiB | Avg Free GiB | Min Free GiB | Avg Used % | Max Used % | Risk |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| J: | 255.98 | 157.53 | 249.17 | 98.45 | 6.81 | 61.54% | 97.34% | High |
| C: | 126.51 | 63.09 | 63.20 | 63.42 | 63.31 | 49.87% | 49.96% | Medium |
| F: | 127.98 | 54.31 | 54.33 | 73.67 | 73.65 | 42.44% | 42.46% | Low |
| G: | 127.98 | 34.31 | 34.31 | 93.67 | 93.67 | 26.81% | 26.81% | Low |
| D: | 64.00 | 5.73 | 5.88 | 58.27 | 58.12 | 8.95% | 9.19% | Low |
| H: | 127.98 | 5.55 | 5.55 | 122.43 | 122.43 | 4.34% | 4.34% | Low |
| I: | 63.98 | 0.09 | 0.09 | 63.89 | 63.89 | 0.15% | 0.15% | Low |

Disk Space Findings:
- J: (SQL-BACKUP) is a critical concern — average 61.54% used but peaks at 97.34% with only 6.81 GiB free at minimum. Backup cycles are consuming nearly all capacity.
- C: (OS disk) is moderately utilized at ~50% with stable headroom.
- F: (SQL-DATA) and G: (SQL-LOGS) have comfortable free space.
- D:, H: (SQL-TEMP), and I: (SQL-INDEX) are lightly utilized.

### CATORHYPSQLD1

#### Aggregate Disk IOPS and Throughput
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average IOPS | 2.22 | 2.10 | 2.08 | Stable low |
| Maximum IOPS | 47.57 | 48.13 | 48.13 | Stable |
| Average Throughput | 1.94 MB/s | 1.92 MB/s | 1.92 MB/s | Stable low |
| Maximum Throughput | 28.13 MB/s | 28.21 MB/s | 28.21 MB/s | Stable |

#### Per-Disk Breakdown

##### 7-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 11.49 | 38.76 | 0.68 | 2.07 |
| CATORHYPSQLD1-datadisk-0 | 0 | 1.67 | 160.48 | 0.43 | 8.94 |
| CATORHYPSQLD1-datadisk-1 | 1 | 0.02 | 1.37 | 0.00 | 0.02 |
| CATORHYPSQLD1-datadisk-2 | 2 | 0.12 | 1.87 | 0.00 | 0.02 |
| CATORHYPSQLD1-datadisk-3 | 3 | 0.00 | 0.05 | 0.00 | 0.01 |
| CATORHYPSQLD1-datadisk-4 | 4 | 0.92 | 19.33 | 0.75 | 17.88 |

##### 30-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 10.99 | 87.59 | 0.66 | 4.43 |
| CATORHYPSQLD1-datadisk-0 | 0 | 1.67 | 163.13 | 0.43 | 9.92 |
| CATORHYPSQLD1-datadisk-1 | 1 | 0.01 | 1.37 | 0.00 | 0.58 |
| CATORHYPSQLD1-datadisk-2 | 2 | 0.12 | 6.29 | 0.00 | 0.35 |
| CATORHYPSQLD1-datadisk-3 | 3 | 0.00 | 0.18 | 0.00 | 0.01 |
| CATORHYPSQLD1-datadisk-4 | 4 | 0.92 | 21.32 | 0.75 | 19.85 |

##### 90-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 10.91 | 87.59 | 0.65 | 4.43 |
| CATORHYPSQLD1-datadisk-0 | 0 | 1.63 | 163.13 | 0.43 | 9.92 |
| CATORHYPSQLD1-datadisk-1 | 1 | 0.01 | 1.37 | 0.00 | 0.58 |
| CATORHYPSQLD1-datadisk-2 | 2 | 0.12 | 6.29 | 0.00 | 0.35 |
| CATORHYPSQLD1-datadisk-3 | 3 | 0.00 | 0.18 | 0.00 | 0.01 |
| CATORHYPSQLD1-datadisk-4 | 4 | 0.92 | 21.32 | 0.75 | 19.85 |

Findings:
- LUN 0 is the burst IOPS hotspot with peaks over 163.
- LUN 4 carries highest sustained throughput at 0.75 MB/s.
- LUN 1, LUN 2, and LUN 3 are near-idle.
- Disk behavior is stable across 90 days.

#### Disk Space Utilization (7-Day Guest Metrics)
| Drive | Size GiB | Avg Used GiB | Max Used GiB | Avg Free GiB | Min Free GiB | Avg Used % | Max Used % | Risk |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| J: | 255.98 | 92.77 | 123.83 | 163.21 | 132.15 | 36.24% | 48.37% | Low |
| C: | 126.51 | 45.39 | 45.54 | 81.12 | 80.97 | 35.88% | 36.00% | Low |
| F: | 127.98 | 34.74 | 34.76 | 93.24 | 93.22 | 27.14% | 27.16% | Low |
| G: | 127.98 | 33.69 | 33.69 | 94.29 | 94.29 | 26.33% | 26.33% | Low |
| D: | 64.00 | 8.27 | 8.43 | 55.73 | 55.57 | 12.92% | 13.18% | Low |
| H: | 127.98 | 2.25 | 2.25 | 125.73 | 125.73 | 1.76% | 1.76% | Low |
| I: | 63.98 | 0.09 | 0.09 | 63.89 | 63.89 | 0.15% | 0.15% | Low |

Disk Space Findings:
- All drives are healthy with no capacity concerns.
- J: (backup) is the most utilized at 36.24% avg but peaks at only 48.37% — much healthier than its counterpart CATORHYPSQLC1.
- C: (OS disk) is comfortably at ~36% with over 80 GiB free.
- All data disks have substantial free capacity.

### CATORSQLD2

#### Aggregate Disk IOPS and Throughput
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average IOPS | 1.88 | 1.82 | 1.81 | Stable low |
| Maximum IOPS | 8.06 | 21.99 | 21.07 | Stable |
| Average Throughput | 0.91 MB/s | 0.89 MB/s | 0.89 MB/s | Stable low |
| Maximum Throughput | 3.68 MB/s | 7.05 MB/s | 6.88 MB/s | Stable |

#### Per-Disk Breakdown

##### 7-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 11.69 | 44.85 | 0.67 | 2.49 |
| CATORSQLD2-disk01-New | 0 | 0.00 | 0.05 | 0.00 | 0.00 |
| catorsqld2-disk02-New | 1 | 0.26 | 0.61 | 0.01 | 0.03 |
| catorsqld2-disk03-New | 2 | 0.13 | 0.64 | 0.01 | 0.23 |
| catorsqld2-disk04-New | 3 | 0.01 | 0.07 | 0.00 | 0.02 |
| catorsqld2-disk05-New | 4 | 0.32 | 6.44 | 0.01 | 0.26 |

##### 30-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 11.25 | 114.99 | 0.65 | 5.96 |
| CATORSQLD2-disk01-New | 0 | 0.00 | 0.05 | 0.00 | 0.00 |
| catorsqld2-disk02-New | 1 | 0.26 | 0.90 | 0.01 | 0.04 |
| catorsqld2-disk03-New | 2 | 0.14 | 2.32 | 0.01 | 0.74 |
| catorsqld2-disk04-New | 3 | 0.01 | 0.52 | 0.00 | 0.08 |
| catorsqld2-disk05-New | 4 | 0.33 | 6.50 | 0.02 | 0.36 |

##### 90-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 11.20 | 114.79 | 0.65 | 5.96 |
| CATORSQLD2-disk01-New | 0 | 0.00 | 0.05 | 0.00 | 0.00 |
| catorsqld2-disk02-New | 1 | 0.26 | 0.90 | 0.01 | 0.04 |
| catorsqld2-disk03-New | 2 | 0.14 | 2.32 | 0.01 | 0.74 |
| catorsqld2-disk04-New | 3 | 0.01 | 0.52 | 0.00 | 0.08 |
| catorsqld2-disk05-New | 4 | 0.33 | 6.50 | 0.02 | 0.36 |

Findings:
- OS disk dominates I/O activity; all data disks are near-idle.
- LUN 0 is completely inactive.
- LUN 4 has minor burst IOPS but negligible throughput.
- This is the lightest-loaded VM for disk I/O.

#### Disk Space Utilization (7-Day Guest Metrics)
| Drive | Size GiB | Avg Used GiB | Max Used GiB | Avg Free GiB | Min Free GiB | Avg Used % | Max Used % | Risk |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| C: | 126.51 | 73.61 | 74.87 | 52.90 | 51.64 | 58.18% | 59.18% | Medium |
| D: | 255.98 | 35.50 | 35.52 | 220.48 | 220.46 | 13.87% | 13.88% | Low |
| E: | 255.98 | 28.90 | 28.90 | 227.08 | 227.08 | 11.29% | 11.29% | Low |
| F: | 255.98 | 5.72 | 5.79 | 250.26 | 250.19 | 2.24% | 2.26% | Low |
| H: | 32.00 | 0.11 | 0.25 | 31.89 | 31.75 | 0.35% | 0.78% | Low |
| G: | 127.98 | 0.21 | 0.21 | 127.77 | 127.77 | 0.17% | 0.17% | Low |

Disk Space Findings:
- C: (OS disk) is the only moderate concern at 58.18% avg used, though absolute free space (52.90 GiB) is adequate.
- D: and E: are large 256 GiB drives with only 11-14% utilization — substantial headroom.
- F:, G:, and H: are essentially empty.
- This VM has the healthiest disk space profile in the NPE group.

### CATORSQLD5

#### Aggregate Disk IOPS and Throughput
| Metric | 7-Day | 30-Day | 90-Day | Trend |
|---|---:|---:|---:|---|
| Average IOPS | 6.05 | 5.98 | 5.97 | Stable |
| Maximum IOPS | 60.65 | 62.67 | 61.30 | Stable |
| Average Throughput | 3.11 MB/s | 3.11 MB/s | 3.10 MB/s | Stable |
| Maximum Throughput | 31.35 MB/s | 31.45 MB/s | 31.45 MB/s | Stable |

#### Per-Disk Breakdown

##### 7-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 14.74 | 52.32 | 0.89 | 3.45 |
| CATORSQLD5-disk02 | 1 | 0.73 | 11.26 | 0.05 | 1.23 |
| CATORSQLD5-disk03 | 2 | 0.64 | 11.81 | 0.89 | 20.21 |
| CATORSQLD5-disk05 | 4 | 12.38 | 223.52 | 1.20 | 14.42 |

##### 30-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 14.73 | 128.35 | 0.88 | 6.64 |
| CATORSQLD5-disk02 | 1 | 0.73 | 11.26 | 0.05 | 1.23 |
| CATORSQLD5-disk03 | 2 | 0.64 | 11.98 | 0.89 | 20.22 |
| CATORSQLD5-disk05 | 4 | 12.13 | 223.52 | 1.20 | 16.58 |

##### 90-Day
| Disk | LUN | Avg IOPS | Max IOPS | Avg MB/s | Max MB/s |
|---|---:|---:|---:|---:|---:|
| OS Disk | - | 14.68 | 128.36 | 0.88 | 6.64 |
| CATORSQLD5-disk02 | 1 | 0.73 | 11.24 | 0.05 | 1.22 |
| CATORSQLD5-disk03 | 2 | 0.64 | 11.82 | 0.89 | 20.16 |
| CATORSQLD5-disk05 | 4 | 12.09 | 218.44 | 1.19 | 15.97 |

Findings:
- LUN 4 is the dominant workload disk with 12+ avg IOPS and burst peaks over 223.
- LUN 2 carries moderate sustained throughput at 0.89 MB/s.
- LUN 1 has light activity.
- This VM has the highest disk utilization in the NPE group.

## Cross-VM Comparison — Non-Production

### CPU Utilization Trends
| VM | 7-Day Avg | 30-Day Avg | 90-Day Avg | 90-Day Trend |
|---|---:|---:|---:|---|
| CATORHYPSQLC1 | 3.02% | 3.01% | 3.01% | Completely stable |
| CATORHYPSQLD1 | 2.13% | 2.15% | 2.15% | Completely stable |
| CATORSQLD2 | 7.72% | 7.76% | 7.75% | Completely stable |
| CATORSQLD5 | 16.39% | 16.04% | 16.06% | Completely stable |

### Memory Utilization Trends
| VM | 7-Day Avg | 30-Day Avg | 90-Day Avg | 90-Day Trend | Risk Level |
|---|---:|---:|---:|---|---|
| CATORHYPSQLC1 | 84.81% | 82.38% | 82.45% | Stable, consistently high | Medium-High |
| CATORHYPSQLD1 | 85.21% | 82.73% | 82.79% | Stable, consistently high | Medium-High |
| CATORSQLD2 | 55.53% | 52.59% | 52.69% | Stable, healthy | Low |
| CATORSQLD5 | 82.39% | 81.22% | 81.27% | Stable, elevated | High (only 8 GiB) |

### Peak Performance Analysis (90-Day Max)
| VM | CPU Peak | Memory Peak | Constraint Risk |
|---|---:|---:|---|
| CATORHYPSQLC1 | 9.43% | 93.59% | High (memory spikes) |
| CATORHYPSQLD1 | 8.52% | 93.74% | High (memory spikes) |
| CATORSQLD2 | 24.58% | 57.38% | Low |
| CATORSQLD5 | 49.54% | 91.44% | High (CPU + memory) |

### 30-Day Baseline Snapshot
| VM | Avg CPU | Max CPU | Avg Mem | Max Mem | Health Status |
|---|---:|---:|---:|---:|---|
| CATORHYPSQLC1 | 3.01% | 9.43% | 82.38% | 93.59% | Good - Monitor memory |
| CATORHYPSQLD1 | 2.15% | 8.52% | 82.73% | 93.74% | Good - Monitor memory |
| CATORSQLD2 | 7.76% | 24.58% | 52.59% | 57.38% | Excellent - Well balanced |
| CATORSQLD5 | 16.04% | 49.54% | 81.22% | 91.44% | Fair - Watch CPU and memory |

## Configuration and SLA Reference

### CATORHYPSQL1
- VM SKU: Standard_D8s_v3 (8 vCPU, 32 GiB Memory)
- VM Max IOPS: 12,800 | VM Max Throughput: 192 MB/s
- OS Disk: StandardSSD_LRS, 127 GB -> 500 IOPS | 100 MB/s
- Data Disks:
  - LUN 0: CATORHYPSQL1-disk01, StandardSSD_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 1: CATORHYPSQL1-disk02, StandardSSD_LRS, 256 GB -> 500 IOPS | 100 MB/s
  - LUN 2: CATORHYPSQL1-disk03, StandardSSD_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 3: CATORHYPSQL1-disk04, StandardSSD_LRS, 60 GB -> 500 IOPS | 100 MB/s
  - LUN 4: CATORHYPSQL1-disk05, StandardSSD_LRS, 128 GB -> 500 IOPS | 100 MB/s
- SLA: 99.0% (single VM with Standard SSD disks)
- Max Downtime/Year: ~87.6 hours

### CATORSQL17
- Resource Group: RT-CA-PRD-ARG-CATORAP17
- VM SKU: Standard_B8ms (8 vCPU, 32 GiB Memory)
- VM Max IOPS: 4,320 | VM Max Throughput: 50 MB/s
- OS Disk: Premium_LRS, 127 GB -> ~500 IOPS | ~100 MB/s
- Data Disks:
  - LUN 0: CATORSQL17-datadisk01, Premium_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 1: CATORSQL17-datadisk02, Premium_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 2: CATORSQL17-datdisk03, Premium_LRS, 256 GB -> 1,100 IOPS | 125 MB/s
  - LUN 3: CATORSQL17-datadisk04, Premium_LRS, 256 GB -> 1,100 IOPS | 125 MB/s
  - LUN 4: CATORSQL17-datdisk05, Premium_LRS, 64 GB -> 240 IOPS | 50 MB/s
- SLA: 99.9% (single VM with Premium SSD disks)
- Max Downtime/Year: ~8.76 hours

### CATORSQL5
- Resource Group: RT-CA-PRD-ARG-CATORSQL5
- VM SKU: Standard_D4s_v3 (4 vCPU, 16 GiB Memory)
- VM Max IOPS: 6,400 | VM Max Throughput: 96 MB/s
- OS Disk: StandardSSD_LRS, 127 GB -> 500 IOPS | 100 MB/s
- Data Disks:
  - LUN 1: CATORSQL5-disk02, StandardSSD_LRS, 256 GB -> 500 IOPS | 100 MB/s
  - LUN 2: CATORSQL5-disk03, StandardSSD_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 3: CATORSQL5-disk04, StandardSSD_LRS, 128 GB -> 500 IOPS | 100 MB/s
- SLA: 99.0% (single VM with Standard SSD disks)
- Max Downtime/Year: ~87.6 hours

### CATORSQL6
- Resource Group: RT-CA-PRD-ARG-CATORSQL6
- VM SKU: Standard_D4s_v3 (4 vCPU, 16 GiB Memory)
- VM Max IOPS: 6,400 | VM Max Throughput: 96 MB/s
- OS Disk: Premium_LRS, 127 GB -> ~500 IOPS | ~100 MB/s
- Data Disks:
  - LUN 0: CATORSQL6-disk01, StandardSSD_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 1: CATORSQL6-disk02, Premium_LRS, 256 GB -> 1,100 IOPS | 125 MB/s
  - LUN 2: CATORSQL6-disk03, Premium_LRS, 256 GB -> 1,100 IOPS | 125 MB/s
  - LUN 3: CATORSQL6-disk04, Premium_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 4: CATORSQL6-disk05, Premium_LRS, 128 GB -> 500 IOPS | 100 MB/s
- SLA: 99.0% (single VM with mixed disk types; Standard SSD portion limits SLA)
- Max Downtime/Year: ~87.6 hours

### CATORHYPSQLC1
- Resource Group: RT-CA-NPE-ARG-CATORHYPSQLC1
- Subscription: RioTinto-CA-Non-Production
- VM SKU: Standard_D8s_v3 (8 vCPU, 32 GiB Memory)
- VM Max IOPS: 12,800 | VM Max Throughput: 192 MB/s
- OS Disk: StandardSSD_LRS
- Data Disks:
  - LUN 0: CATORHYPSQLC1-SQL-DATA-F, StandardSSD_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 1: CATORHYPSQLC1-SQL-LOGS-G, StandardSSD_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 2: CATORHYPSQLC1-SQL-TEMP-H, StandardSSD_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 3: CATORHYPSQLC1-SQL-INDEX-I, StandardSSD_LRS, 64 GB -> 500 IOPS | 100 MB/s
  - LUN 4: CATORHYPSQLC1-SQL-BACKUP-J, StandardSSD_LRS, 256 GB -> 500 IOPS | 100 MB/s
- SLA: 99.0% (single VM with Standard SSD disks)
- Max Downtime/Year: ~87.6 hours

### CATORHYPSQLD1
- Resource Group: RT-CA-NPE-ARG-CATORHYPSQLD1
- Subscription: RioTinto-CA-Non-Production
- VM SKU: Standard_D8s_v3 (8 vCPU, 32 GiB Memory)
- VM Max IOPS: 12,800 | VM Max Throughput: 192 MB/s
- OS Disk: StandardSSD_LRS
- Data Disks:
  - LUN 0: CATORHYPSQLD1-datadisk-0, StandardSSD_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 1: CATORHYPSQLD1-datadisk-1, StandardSSD_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 2: CATORHYPSQLD1-datadisk-2, StandardSSD_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 3: CATORHYPSQLD1-datadisk-3, StandardSSD_LRS, 64 GB -> 500 IOPS | 100 MB/s
  - LUN 4: CATORHYPSQLD1-datadisk-4, StandardSSD_LRS, 256 GB -> 500 IOPS | 100 MB/s
- SLA: 99.0% (single VM with Standard SSD disks)
- Max Downtime/Year: ~87.6 hours

### CATORSQLD2
- Resource Group: RT-TOR-NPE-ARG-CRYSTALUPGRADE
- Subscription: RioTinto-CA-Non-Production
- VM SKU: Standard_D4s_v3 (4 vCPU, 16 GiB Memory)
- VM Max IOPS: 6,400 | VM Max Throughput: 96 MB/s
- OS Disk: StandardSSD_LRS
- Data Disks:
  - LUN 0: CATORSQLD2-disk01-New, StandardSSD_LRS, 512 GB -> 500 IOPS | 100 MB/s
  - LUN 1: catorsqld2-disk02-New, StandardSSD_LRS, 256 GB -> 500 IOPS | 100 MB/s
  - LUN 2: catorsqld2-disk03-New, StandardSSD_LRS, 256 GB -> 500 IOPS | 100 MB/s
  - LUN 3: catorsqld2-disk04-New, StandardSSD_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 4: catorsqld2-disk05-New, StandardSSD_LRS, 256 GB -> 500 IOPS | 100 MB/s
- SLA: 99.0% (single VM with Standard SSD disks)
- Max Downtime/Year: ~87.6 hours

### CATORSQLD5
- Resource Group: RT-CA-NPE-ARG-CATORSQLD5
- Subscription: RioTinto-CA-Non-Production
- VM SKU: Standard_D2s_v3 (2 vCPU, 8 GiB Memory)
- VM Max IOPS: 3,200 | VM Max Throughput: 48 MB/s
- OS Disk: StandardSSD_LRS
- Data Disks:
  - LUN 1: CATORSQLD5-disk02, Premium_LRS, 128 GB -> 500 IOPS | 100 MB/s
  - LUN 2: CATORSQLD5-disk03, StandardSSD_LRS, 256 GB -> 500 IOPS | 100 MB/s
  - LUN 4: CATORSQLD5-disk05, Premium_LRS, 128 GB -> 500 IOPS | 100 MB/s
- SLA: 99.0% (single VM with mixed disk types; Standard SSD portion limits SLA)
- Max Downtime/Year: ~87.6 hours

## Structure Notes for Future Updates

- Keep the same section order to make month-over-month comparisons easier.
- Add one new reporting date block at the top for each refresh, and append only changed metric tables.
- If this report grows further, split into separate files for inventory, compute, and disk, with this file as the summary index.