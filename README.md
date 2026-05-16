# ANF Migration & Evaluation: CATORHYPSQL1
**Azure NetApp Files — SQL Server on Azure VM Technical Assessment**

Prepared: May 16, 2026  
Reference VM: CATORHYPSQL1 (Production, RioTinto-CA-Production)  
Scope: Architecture · Migration · Disaster Recovery · Operations · Technical Validation

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Comparison](#2-architecture-comparison)
3. [Migration Plan: Disk to ANF](#3-migration-plan-disk-to-anf)
4. [Disaster Recovery](#4-disaster-recovery)
5. [Daily Operations & Troubleshooting](#5-daily-operations--troubleshooting)
6. [Technical Validation Test Plan](#6-technical-validation-test-plan)

---

## 1. Executive Summary

### Current State

CATORHYPSQL1 runs SQL Server on a Standard_D8s_v3 VM with five Standard SSD (StandardSSD_LRS) data disks totaling ~700 GB. Key findings from the 90-day discovery:

| Concern | Detail |
|---|---|
| **Backup drive crisis** | J: (256 GB) peaks at 96% used, minimum 10 GB free — backup failures imminent |
| **Memory pressure** | 94% peak utilization on 32 GiB — SQL buffer pool under pressure |
| **Storage SLA** | 99.0% only (Standard SSD) — ~87.6 hr/year allowable downtime |
| **Throughput ceiling** | Each StandardSSD disk capped at 500 IOPS / 100 MB/s regardless of VM capacity (12,800 IOPS / 192 MB/s available) |
| **No native data management** | Snapshots, replication, and clone require third-party or Azure Backup agents |

### Migration Drivers for ANF

| Driver | ANF Benefit |
|---|---|
| Backup drive at capacity | ANF volumes are thin-provisioned; capacity pool can be extended without disk resize or downtime |
| Per-disk IOPS ceiling | ANF Manual QoS pool assigns throughput per volume independently — no tier lock-in, rebalance anytime without resizing |
| DR complexity | ANF cross-zone replication (CZR) + snapshots replace multi-disk Azure Backup coordination |
| Data management | Space-efficient snapshots, instant clones for test environments |
| SLA improvement | ANF delivers 99.99% availability SLA on volumes |

---

## 2. Architecture Comparison

### 2.1 Current Architecture: Direct-Attached Azure Disk

```mermaid
flowchart TB
    subgraph vm["CATORHYPSQL1  ·  Standard_D8s_v3  ·  VM max: 12,800 IOPS / 192 MB/s"]
        sql(["SQL Server Engine"])
        c["C: OS Disk — StdSSD 127 GB — 500 IOPS / 100 MB/s"]
        f["F: disk01 — SQL Data — StdSSD 128 GB — 500 IOPS / 100 MB/s"]
        j["J: disk02 — SQL Backup ⚠️ 96% capacity used — StdSSD 256 GB — 500 IOPS / 100 MB/s"]
        g["G: disk03 — SQL Logs — StdSSD 128 GB — 500 IOPS / 100 MB/s"]
        idx["I: disk04 — SQL Index — StdSSD 60 GB — 500 IOPS / 100 MB/s"]
        h["H: disk05 — SQL TempDB — StdSSD 128 GB — 500 IOPS / 100 MB/s"]
        sql --- c & f & j & g & idx & h
    end
    bkp(["Azure Backup Agent — Recovery Services Vault"])
    sql -.->|"VSS backup"| bkp
```

**Key constraints of the current design:**

- **IOPS is disk-count-bound.** Each StandardSSD disk provides up to 500 IOPS regardless of VM capacity. Five disks → max 2,500 IOPS total, while the VM supports 12,800 IOPS. The storage is the bottleneck, not the compute.
- **Throughput is disk-count-bound.** 5 × 100 MB/s = 500 MB/s theoretical, but VM NIC allows only 192 MB/s for data disks on D8s_v3 — the VM cap is the real ceiling.
- **Disks are independently managed.** Resizing J: from 256 GB to 512 GB requires a disk resize operation (offline for StandardSSD or hot-resize with OS support), followed by partition extension inside the OS.
- **Crash-consistent snapshots require coordination.** Azure Backup uses VSS to quiesce SQL, but all five disks must be snapshotted in sequence, creating a multi-disk orchestration dependency.
- **Capacity is pre-provisioned.** You pay for 256 GB on J: even when only 50 GB is used. There is no thin provisioning.

### 2.2 Target Architecture: Azure NetApp Files (SMB3)

```mermaid
flowchart TB
    subgraph vm["CATORHYPSQL1  ·  Standard_D8s_v3"]
        sql(["SQL Server Engine"])
        c["C: OS Disk — StdSSD 127 GB — kept as-is"]
        sql --- c
    end
    subgraph anfpool["Azure NetApp Files  ·  Delegated Subnet (same VNet)"]
        pool["Capacity Pool — Flexible Service Level — 4 TiB Manual QoS"]
        budget["Pool throughput: min 128 MiB/s  ·  max 2,560 MiB/s  ·  currently allocated 120 MiB/s"]
        v1["sql-data — 512 GiB — 32 MiB/s — F: SQL Data"]
        v2["sql-logs — 256 GiB — 32 MiB/s — G: Transaction Logs"]
        v3["sql-tempdb — 128 GiB — 32 MiB/s — H: TempDB"]
        v4["sql-index — 128 GiB — 8 MiB/s — I: Index files"]
        v5["sql-backup — 1 TiB — 16 MiB/s — J: Backup (boost to 80+ MiB/s during backup window)"]
        pool --- budget
        pool --> v1 & v2 & v3 & v4 & v5
    end
    snap(["ANF Snapshot Policy — hourly / daily / weekly"])
    czr(["Cross-Zone Replication — standby zone"])
    sql -->|"SMB3 Continuously Available"| pool
    pool -.-> snap & czr
```

**Key capabilities of the ANF design:**

- **SMB3 with continuously available (CA) shares** — SQL Server files are stored on ANF volumes mounted as UNC shares. SQL Server supports this natively (since SQL Server 2012 with ANF SMB3 CA).
- **Flexible service level — throughput is decoupled from volume size.** With a Flexible service level capacity pool (Manual QoS), each volume receives an explicit MiB/s allocation regardless of its quota. sql-logs can be assigned 32 MiB/s on a 256 GiB quota; sql-backup can be assigned 16 MiB/s on a 1 TiB quota. Throughput is rebalanced online at any time by updating the volume's `--throughput-mibps` — no quota change, no VM restart, no service disruption. See [ANF Flexible service level](https://learn.microsoft.com/en-us/azure/azure-netapp-files/azure-netapp-files-service-levels#flexible-examples).
- **Single pool, no tier proliferation.** One Flexible capacity pool replaces the need for separate Standard, Premium, and Ultra pools. A 4 TiB Flexible pool guarantees a minimum of 128 MiB/s and supports a maximum of 2,560 MiB/s (5 × 128 MiB/s × 4 TiB) — far exceeding the D8s_v3 VM NIC cap of 192 MB/s. This eliminates the operational overhead of managing multiple pools at different service levels.
- **Thin provisioning.** The sql-backup volume shows 1 TiB quota but ANF only charges for consumed data. Resolve the J: backup capacity crisis without pre-paying for 1 TiB.
- **Snapshot policy is application-consistent for SQL.** ANF snapshots are volume-level and near-instantaneous (metadata operation). Combined with SQL VSS writer or SQL frozen I/O, they are application-consistent.
- **IOPS scales with throughput.** A volume assigned 32 MiB/s with 8 KiB random I/O can sustain ~4,000 IOPS. Increase `--throughput-mibps` to instantly raise the IOPS ceiling without any disk reconfiguration.

### 2.3 Architecture Differences Summary

| Dimension | Direct-Attached Disk | Azure NetApp Files |
|---|---|---|
| **Protocol** | Block (page blob via VHD) | File (SMB3 on Windows) |
| **IOPS scaling** | Add more disks (striping) | Increase `--throughput-mibps` on the volume (Manual QoS) — instant, no downtime |
| **Throughput scaling** | Add more disks | Increase manual throughput allocation; rebalance from idle volumes in the same pool |
| **Capacity model** | Pre-provisioned, pay full size | Thin-provisioned within quota |
| **Snapshot** | Azure Backup coordinated (VSS agent) | ANF native, near-instant, per-volume |
| **Clone for test/dev** | Full disk copy (slow, costs full GiB) | ANF volume clone from snapshot (instant) |
| **Cross-region/zone DR** | Azure Site Recovery or Backup restore | ANF Cross-Zone Replication (CZR) built-in |
| **Resize** | Disk resize + OS partition extend | Change volume quota, no downtime |
| **SLA** | 99.0% (Standard SSD) | 99.99% |
| **Max downtime/year** | ~87.6 hours | ~52 minutes |
| **Management plane** | Azure Disk Manager (per disk) | Single ANF Account, one Flexible capacity pool — all throughput managed in one place |
| **Multi-VM sharing** | Not supported (block) | Supported (same SMB3 share) — useful for AG |
| **Latency profile** | Sub-millisecond (local NVMe path) | ~1 ms average (network SMB, same AZ) |

### 2.4 Performance Sizing: Current vs ANF Target for CATORHYPSQL1

**Observed peak workloads (90-day):**

| Volume Role | Current Disk | Observed Avg IOPS | Observed Max IOPS | Observed Max MB/s |
|---|---|---:|---:|---:|
| SQL Data (F:) | disk01, 128 GB Std SSD | 0.28 | 45.58 | 9.14 |
| SQL Backup (J:) | disk02, 256 GB Std SSD | 1.70 | 38.11 | 36.34 |
| SQL Logs (G:) | disk03, 128 GB Std SSD | 0.31 | 63.68 | 6.84 |
| SQL Misc (H:) | disk05, 128 GB Std SSD | 3.00 | 306.44 | 18.16 |
| SQL Index (I:) | disk04, 60 GB Std SSD | ~0.00 | 0.04 | 0.01 |

**ANF volume sizing recommendation — Flexible service level pool:**

| ANF Volume | Quota | Manual Throughput | Headroom vs Observed Peak | Notes |
|---|---:|---:|---|---|
| sql-data | 512 GiB | 32 MiB/s | 3.5× above 9.14 MB/s peak | Increase to 64 MiB/s if OLAP queries grow |
| sql-logs | 256 GiB | 32 MiB/s | 4.7× above 6.84 MB/s peak | Latency-sensitive; keep throughput headroom |
| sql-tempdb | 128 GiB | 32 MiB/s | Burst-ready for sort/hash spills | Can borrow from large Flexible pool budget |
| sql-index | 128 GiB | 8 MiB/s | Near-idle; right-sized | Increase transiently during index rebuild |
| sql-backup | 1,024 GiB | 16 MiB/s | Resolves 96% capacity crisis | Boost to 150 MiB/s during backup window (VM NIC is the cap) |
| **Pool total** | **4 TiB** | **120 MiB/s assigned** | Max budget: 2,560 MiB/s · VM NIC cap: 192 MB/s | |

**Flexible service level throughput management:** The Flexible service level (Manual QoS) provides a minimum guaranteed throughput of 128 MiB/s for the pool and a maximum of `5 × 128 MiB/s × pool_TiB`. For a 4 TiB pool, the max is **2,560 MiB/s** — far exceeding the D8s_v3 VM NIC cap of 192 MB/s. The VM NIC, not the pool, is the practical per-VM ceiling. Example: boost sql-backup to 150 MiB/s during nightly backup window (02:00–05:00), then return to 16 MiB/s for the day — no pool resize, no volume resize, no SQL restart. When the 4 TiB pool is shared across multiple VMs, each VM can simultaneously receive up to its NIC cap, so the large pool budget supports all four production VMs at full speed. Automate with Azure Automation or a scheduled script calling `az netappfiles volume update --throughput-mibps`.

**Note:** All volumes reside in a single 4 TiB Flexible capacity pool. The backup volume quota of 1 TiB is thin-provisioned — billing is based on consumed GiB only. Remaining pool capacity is shared with other production VMs (CATORSQL17, CATORSQL5, CATORSQL6).

---

## 3. Migration Plan: Disk to ANF

### 3.1 Pre-Migration Assessment (Week 1)

#### Step 1: Validate ANF prerequisites

| Check | Action |
|---|---|
| ANF delegated subnet | Create or verify a `/28` subnet in the same VNet as CATORHYPSQL1, delegated to `Microsoft.NetApp/volumes` |
| Active Directory integration | ANF SMB3 requires AD join for Kerberos/NTLM auth — register ANF account with the same AD domain as CATORHYPSQL1 |
| SMB CA file share support | Verify SQL Server version ≥ 2012 with latest CU; confirm OS is Windows Server 2016+ |
| Network latency baseline | Run `ping` and `psping` from CATORHYPSQL1 to ANF endpoint; target < 2 ms |
| SQL Server data/log file locations | Run `SELECT name, physical_name FROM sys.master_files` to map all databases to current drive letters |

#### Step 2: Baseline current performance (use as comparison baseline for test plan)

```sql
-- Capture wait stats baseline
SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_type IN ('PAGEIOLATCH_SH','PAGEIOLATCH_EX','WRITELOG','IO_COMPLETION','BACKUPIO')
ORDER BY wait_time_ms DESC;

-- Capture I/O stall baseline
SELECT DB_NAME(vfs.database_id) AS DatabaseName,
       mf.physical_name,
       vfs.io_stall_read_ms,
       vfs.io_stall_write_ms,
       vfs.num_of_reads,
       vfs.num_of_writes
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id;
```

Save output to `baseline_io_prestats_YYYYMMDD.txt`.

#### Step 3: Disk-to-volume role mapping

Based on drive letter analysis and ANF target design:

| Current Drive | Size | Used (Peak) | Mapped ANF Volume | Manual Throughput |
|---|---|---|---|---|
| F: (disk01) | 128 GB | ~68 GB | sql-data | 32 MiB/s |
| J: (disk02) | 256 GB | 245 GB peak | sql-backup | 16 MiB/s (boost to 80 MiB/s during backup) |
| G: (disk03) | 128 GB | ~33 GB | sql-logs | 32 MiB/s |
| H: (disk05) | 128 GB | ~5.5 GB | sql-tempdb | 32 MiB/s |
| I: (disk04) | 60 GB | ~0.14 GB | sql-index | 8 MiB/s |

### 3.2 ANF Infrastructure Setup (Week 1–2)

```bash
# Azure CLI — Create ANF account
az netappfiles account create \
  --resource-group RT-CA-PRD-ANF-RG \
  --location canadacentral \
  --name anfacct-catorhyp

# Create capacity pool — Flexible service level, Manual QoS (single pool for all SQL volumes)
az netappfiles pool create \
  --resource-group RT-CA-PRD-ANF-RG \
  --location canadacentral \
  --account-name anfacct-catorhyp \
  --pool-name sql-pool-prd \
  --size 4 \
  --service-level Flexible \
  --qos-type Manual
# Pool budget: 4 TiB Flexible — min 128 MiB/s guaranteed, max 5 × 128 × 4 = 2,560 MiB/s
# In practice the D8s_v3 VM NIC (192 MB/s) is the per-VM throughput ceiling

# Create SMB volumes — set --throughput-mibps per volume (service-level inherited from pool)
# sql-data: SQL data files, 32 MiB/s
az netappfiles volume create \
  --resource-group RT-CA-PRD-ANF-RG \
  --location canadacentral \
  --account-name anfacct-catorhyp \
  --pool-name sql-pool-prd \
  --name sql-data \
  --usage-threshold 512 \
  --throughput-mibps 32 \
  --protocol-types CIFS \
  --subnet-id /subscriptions/<sub-id>/resourceGroups/RT-CA-PRD-ANF-RG/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/anf-delegated

# sql-logs: Transaction logs, 32 MiB/s (latency-sensitive)
az netappfiles volume create ... --name sql-logs --usage-threshold 256 --throughput-mibps 32

# sql-tempdb: TempDB, 32 MiB/s (can boost further from large Flexible pool budget)
az netappfiles volume create ... --name sql-tempdb --usage-threshold 128 --throughput-mibps 32

# sql-index: Index/misc, 8 MiB/s (near-idle; expandable for index rebuilds)
az netappfiles volume create ... --name sql-index --usage-threshold 128 --throughput-mibps 8

# sql-backup: Backup files, 16 MiB/s default (boost to 150 MiB/s during backup window — VM NIC limited)
az netappfiles volume create ... --name sql-backup --usage-threshold 1024 --throughput-mibps 16

# Total allocated: 120 MiB/s of 2,560 MiB/s Flexible pool max budget
```

**AD connector registration (required before SMB volume creation):**

```bash
az netappfiles account ad add \
  --resource-group RT-CA-PRD-ANF-RG \
  --account-name anfacct-catorhyp \
  --username <svc-account> \
  --password <password> \
  --domain <domain.local> \
  --dns <DC-IP> \
  --smb-server-name ANFSMB01
```

### 3.3 Migration Execution (Week 2–3)

Migration approach: **Online data copy with SQL offline cutover window.** This minimizes downtime to the final move of transaction logs and SQL data files.

#### Phase A: Copy bulk data (with SQL running)

Use `robocopy` to pre-stage data to ANF while SQL continues serving traffic:

```powershell
# Pre-stage SQL data files (databases in READ_WRITE, SQL still running)
# Note: cannot copy open .mdf/.ldf directly. Use backup/restore approach.

# Step 1: Take full backup of all databases to ANF sql-backup volume
$databases = Invoke-Sqlcmd -Query "SELECT name FROM sys.databases WHERE state = 0 AND name NOT IN ('tempdb')" -ServerInstance "CATORHYPSQL1"
foreach ($db in $databases) {
    $backupPath = "\\ANFSMB01\sql-backup\migration\$($db.name)_FULL_$(Get-Date -Format yyyyMMdd).bak"
    Invoke-Sqlcmd -Query "BACKUP DATABASE [$($db.name)] TO DISK = '$backupPath' WITH COMPRESSION, STATS = 10" -ServerInstance "CATORHYPSQL1"
}
```

#### Phase B: Cutover window (planned maintenance)

Estimated downtime: **30–60 minutes** (depending on log catch-up size)

```sql
-- Step 1: Set all user databases to SINGLE_USER to quiesce
-- (Schedule maintenance window, notify users)

-- Step 2: Final transaction log backup to ANF
BACKUP LOG [DatabaseName]
TO DISK = '\\ANFSMB01\sql-backup\migration\DatabaseName_LOG_final.trn'
WITH NORECOVERY;

-- Step 3: Restore databases to ANF volumes with MOVE
RESTORE DATABASE [DatabaseName]
FROM DISK = '\\ANFSMB01\sql-backup\migration\DatabaseName_FULL_YYYYMMDD.bak'
WITH NORECOVERY,
     MOVE 'DatabaseName_data' TO '\\ANFSMB01\sql-data\DatabaseName.mdf',
     MOVE 'DatabaseName_log'  TO '\\ANFSMB01\sql-logs\DatabaseName_log.ldf';

-- Step 4: Apply log backup
RESTORE LOG [DatabaseName]
FROM DISK = '\\ANFSMB01\sql-backup\migration\DatabaseName_LOG_final.trn'
WITH RECOVERY;

-- Step 5: Verify
SELECT name, state_desc, physical_name FROM sys.master_files WHERE database_id = DB_ID('DatabaseName');
```

#### Phase C: Move system/config files

- **TempDB:** Update `tempdb` file locations in SQL Server Configuration Manager or via `ALTER DATABASE tempdb MODIFY FILE`, then restart SQL Server service. New path: `\\ANFSMB01\sql-tempdb\`.
- **SQL Server Error Log and Agent:** Update paths in SQL Server Properties → Advanced.
- **SQL Server Startup parameters:** Update `-eErrorLog` path if redirected.

#### Phase D: Decommission old disks

After 7-day validation period (SQL running on ANF, all tests passed):

1. Remove old data disks from VM (Portal → VM → Disks → Detach)
2. Snapshot old disks before deletion as final safety copy
3. Delete old disks to stop billing

### 3.4 Rollback Plan

| Rollback Trigger | Action |
|---|---|
| SMB mount failures post-cutover | Remount SQL file paths to original drive letters; restart SQL Server |
| Performance degradation > 20% vs baseline | Revert SQL file paths to original disks (still attached during 7-day validation) |
| Data integrity failure | Restore from last good Azure Backup on original disks |

**Key safety rule:** Do NOT detach original disks for at least 7 days after cutover. Keep them attached (not mounted in OS) as instant rollback option.

---

## 4. Disaster Recovery

### 4.1 Current DR State

CATORHYPSQL1 currently relies on:

| Component | Current Implementation | Limitation |
|---|---|---|
| **Backup** | Azure Backup (MARS or VM-level snapshot) | Multi-disk consistency requires VSS coordination; J: at 96% may cause backup failures |
| **RPO** | Typically 24h (daily backup policy) | Point-in-time restore is limited to recovery point frequency |
| **RTO** | Full VM restore from Recovery Services Vault → hours | Must restore entire VM + all disks, then bring SQL online |
| **HA** | Single VM, no Always On AG detected | 99.0% SLA; no automatic failover |
| **GEO/Zone DR** | Not confirmed — dependent on Backup vault geo-redundancy | Vault replication passive; no active standby |

### 4.2 ANF DR Capabilities

#### 4.2.1 ANF Snapshots

ANF snapshots are **space-efficient, near-instantaneous volume-level operations** taken at the storage layer, independent of the VM or SQL Server agent.

| Property | Detail |
|---|---|
| **Frequency** | Configurable per volume: up to hourly, daily, weekly, monthly |
| **Retention** | Per policy tier: e.g., keep 24 hourly, 7 daily, 4 weekly |
| **Storage cost** | Charged only for changed blocks since last snapshot (delta) |
| **Restore** | Single-file restore or full volume revert (online, no VM restart) |
| **Application consistency** | Use SQL VSS writer or `BACKUP DATABASE ... SNAPSHOT` before triggering ANF snapshot for crash-consistent guarantee |

Recommended snapshot policy for sql-data and sql-logs:

```
Hourly:  retain 24 snapshots  (every hour, ~1 hour RPO)
Daily:   retain 7 snapshots   (daily, off-peak)
Weekly:  retain 4 snapshots   (Sunday 02:00)
Monthly: retain 3 snapshots   (1st of month)
```

#### 4.2.2 ANF Cross-Zone Replication (CZR)

CZR replicates ANF volumes asynchronously to a volume in a different Availability Zone within the same region (e.g., Canada Central AZ1 → AZ2).

```mermaid
flowchart LR
    subgraph az1["Primary Zone — AZ1  ·  Flexible capacity pool"]
        d1["sql-data — 32 MiB/s"]
        l1["sql-logs — 32 MiB/s"]
        b1["sql-backup — 16 MiB/s"]
        t1["sql-tempdb — not replicated — rebuild on failover"]
    end
    subgraph az2["Secondary Zone — AZ2  ·  Standard pool — DR standby"]
        d2["sql-data-dr — 8 MiB/s"]
        l2["sql-logs-dr — 8 MiB/s"]
        b2["sql-backup-dr — 8 MiB/s"]
        note2["On failover: promote volumes + boost throughput before SQL start"]
    end
    d1 -->|"CZR async ~20 min RPO"| d2
    l1 -->|"CZR async"| l2
    b1 -->|"CZR async"| b2
```

**DR pool design:** The DR pool uses Standard Auto QoS (lower cost acceptable for standby). On failover, the DR volumes are promoted and throughput can be raised to match primary Flexible pool levels via `az netappfiles volume update --throughput-mibps` before bringing SQL online.

| Property | Detail |
|---|---|
| **RPO** | ~20 minutes (async replication interval) |
| **RTO** | Break replication → mount volumes on DR VM → start SQL → ~15–30 minutes |
| **Failover** | Manual (`az netappfiles volume replication approve-external-replication`) or triggered by Azure Monitor alert |
| **Cost** | Pay for destination volume (Standard tier acceptable for DR) + data transfer |

#### 4.2.3 ANF Backup

ANF Backup is a managed long-term backup that stores data in Azure storage independent of the ANF capacity pool — protecting against accidental volume deletion.

| Property | Detail |
|---|---|
| **Policy** | Configurable: daily, weekly, monthly retention |
| **Storage** | Stored in Azure storage (not ANF pool) — no pool capacity consumed |
| **Use case** | Long-term retention (30/60/180 days) replacing or complementing Azure Backup vault |
| **Restore** | Restore to a new ANF volume; remount and attach to SQL |
| **RTO for long-term restore** | ~1–2 hours (depends on volume size and network) |

### 4.3 Recommended DR Design: ANF + SQL HA

#### Tiered DR architecture

```mermaid
flowchart TB
    t1["Tier 1 — High Availability — &lt; 30 sec RTO<br/>SQL Always On AG · Primary: CATORHYPSQL1 AZ1 · Secondary: new VM AZ2<br/>Both mount ANF volumes via SMB3"]
    t2["Tier 2 — Zone Failure DR — ~30 min RTO / ~20 min RPO<br/>ANF Cross-Zone Replication · AZ1 volumes to AZ2 async<br/>DR VM pre-provisioned off"]
    t3["Tier 3 — Long-term / Vault — Hours RTO / 1h RPO<br/>ANF Snapshot Policy + ANF Backup to Azure Storage<br/>Replaces Azure Backup MARS"]
    t1 --> t2 --> t3
```

**Phased approach for RioTinto:** Start with Tier 3 (snapshots + ANF backup) to immediately resolve backup capacity crisis, then add Tier 2 (CZR) for zone DR, then evaluate Tier 1 (AG) based on RTO requirements.

### 4.4 DR Comparison Matrix

| Capability | Azure Backup (current) | ANF Snapshots | ANF CZR | ANF Backup |
|---|---|---|---|---|
| RPO | 24 hours (daily) | 1 hour | ~20 minutes | 24 hours |
| RTO | 4–8 hours (full VM restore) | Minutes (file/vol revert) | 15–30 minutes | 1–2 hours |
| Backup drive capacity | Limited by J: disk size | Not applicable | Not applicable | Stored outside pool |
| Application consistency | VSS (agent-based) | VSS + ANF snapshot | Async (log-based) | Same as snapshot |
| Test/clone for DR drill | Full VM copy required | Instant ANF clone | Restore from DR volume | Restore to new volume |
| Cross-zone protection | Vault GRS (passive) | Same zone only | Active async replication | Vault GRS |
| SLA | Backup vault 99.9% | ANF 99.99% | ANF 99.99% | Azure Storage 99.999% |
| Cost model | Per VM per month | Snapshot delta storage | Destination volume + transfer | Per GiB per month |
| Operational complexity | Medium (agent + policy) | Low (portal/CLI policy) | Medium (peering + failover) | Low |

---

## 5. Daily Operations & Troubleshooting

### 5.1 Storage Administration Changes

| Task | With Azure Disk | With ANF |
|---|---|---|
| **Expand backup volume** | Detach disk → resize in portal → expand partition in OS | Change ANF volume quota in portal/CLI — no OS steps |
| **Create test DB copy** | Clone disk (full GiB copy, slow) | Create ANF volume clone from snapshot — instant, space-efficient |
| **Add capacity** | Attach new disk, format, mount, update SQL paths | Increase capacity pool size or add to existing pool |
| **View storage metrics** | Azure Monitor Disk metrics (IOPS, MB/s) | ANF volume metrics (throughput, consumed size, snapshot size) |
| **Snapshot management** | Azure Backup dashboard | ANF → Volumes → Snapshots (per-volume list) |
| **Reduce throughput cost** | Detach + copy to cheaper disk SKU (hours) | Lower `--throughput-mibps` on the volume (online, seconds) |
| **Rebalance for peak events** | Not possible without adding disks | Shift MiB/s from idle volumes (e.g., sql-index) to active ones (e.g., sql-backup during backup window) — online, no SQL restart |

#### Volume quota expansion (no downtime):

```bash
# Expand sql-backup from 1 TiB to 2 TiB
az netappfiles volume update \
  --resource-group RT-CA-PRD-ANF-RG \
  --account-name anfacct-catorhyp \
  --pool-name sql-pool-prd \
  --name sql-backup \
  --usage-threshold 2048
# The volume appears larger to the OS immediately — no restart, no repartition needed
```

#### Dynamic throughput rebalancing (Flexible service level — no downtime, no quota change):

```bash
# Boost sql-backup throughput before nightly backup window (e.g., 02:00)
# Flexible pool max is 2,560 MiB/s; VM NIC cap on D8s_v3 is ~192 MB/s in practice
az netappfiles volume update \
  --resource-group RT-CA-PRD-ANF-RG \
  --account-name anfacct-catorhyp \
  --pool-name sql-pool-prd \
  --name sql-backup \
  --throughput-mibps 150

# Restore to baseline after backup completes (e.g., 05:00)
az netappfiles volume update ... --name sql-backup --throughput-mibps 16

# Temporarily boost sql-index during weekend index rebuild
az netappfiles volume update ... --name sql-index --throughput-mibps 128
# Restore after rebuild
az netappfiles volume update ... --name sql-index --throughput-mibps 8

# Check current throughput assignments across all volumes in the pool
az netappfiles volume list \
  --resource-group RT-CA-PRD-ANF-RG \
  --account-name anfacct-catorhyp \
  --pool-name sql-pool-prd \
  --query "[].{Name:name, ThroughputMibps:throughputMibps, QuotaGiB:usageThreshold}" -o table
```

> **Rule:** The sum of all volume `--throughput-mibps` values must not exceed the pool max budget. For the Flexible service level: `5 × 128 MiB/s × pool_TiB`. A 4 TiB Flexible pool supports up to **2,560 MiB/s** total (minimum guaranteed: 128 MiB/s regardless of pool size). The CLI will reject an assignment that would exceed the pool budget. In practice, the D8s_v3 VM NIC cap (~192 MB/s) is the lower per-VM limit — the pool budget is rarely the constraint when sharing across multiple VMs.

#### On-demand snapshot before maintenance:

```bash
az netappfiles snapshot create \
  --resource-group RT-CA-PRD-ANF-RG \
  --account-name anfacct-catorhyp \
  --pool-name sql-pool-prd \
  --volume-name sql-data \
  --name pre-patching-$(date +%Y%m%d%H%M)
```

### 5.2 Performance Monitoring

#### Key ANF metrics to monitor (Azure Monitor)

| Metric | Alert Threshold | Meaning |
|---|---|---|
| `VolumeConsumedSizePercentage` | > 80% | Volume filling — expand quota before hitting limit |
| `VolumeThroughput` | > 85% of provisioned | Approaching tier throughput ceiling |
| `VolumeReadThroughput` + `VolumeWriteThroughput` | Baseline × 2 | Unusual I/O spike |
| `VolumeSnapshotSize` | > 20% of volume | Snapshot churn high — review retention policy |
| `AverageReadLatency` | > 5 ms | Network or ANF latency issue |
| `AverageWriteLatency` | > 2 ms | Log volume latency — check sql-logs throughput allocation (increase `--throughput-mibps`) |

#### SQL Server wait stats on ANF (post-migration reference)

After migration, watch these waits to confirm ANF is not a bottleneck:

```sql
-- Run weekly and compare to pre-migration baseline
SELECT TOP 10
    wait_type,
    waiting_tasks_count,
    wait_time_ms / 1000.0 AS wait_time_sec,
    ROUND(100.0 * wait_time_ms / SUM(wait_time_ms) OVER(), 2) AS pct_total
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'SLEEP_TASK','BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_AUTO_EVENT',
    'REQUEST_FOR_DEADLOCK_MONITOR','RESOURCE_QUEUE','SERVER_IDLE_CHECK',
    'SLEEP_DBSTARTUP','SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY',
    'SLEEP_MASTERMDREADY','SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP',
    'SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT','SP_SERVER_DIAGNOSTICS_SLEEP',
    'SQLTRACE_BUFFER_FLUSH','WAITFOR','XE_DISPATCHER_WAIT','XE_TIMER_EVENT'
)
ORDER BY wait_time_ms DESC;
```

**Expected change post-migration:**
- `PAGEIOLATCH_SH` / `PAGEIOLATCH_EX` — should decrease (ANF lower latency for sequential reads vs Standard SSD)
- `WRITELOG` — should decrease (32 MiB/s dedicated throughput on sql-logs via Flexible service level)
- `BACKUPIO` — should decrease (higher throughput to sql-backup volume)

### 5.3 Capacity Management

#### Current problem: J: backup drive at 96% peak

With ANF, the sql-backup volume at 1 TiB quota means the backup process has 4× the current headroom. The consumed space is visible directly in ANF metrics. Set an alert at 80% consumed (`VolumeConsumedSizePercentage > 80`) to trigger capacity review before any crisis.

#### Snapshot space tracking

Snapshots consume delta space in the capacity pool (not the volume quota). Monitor the `VolumeSnapshotSize` metric per volume. If snapshot accumulation is large:

```bash
# List snapshot sizes for sql-data
az netappfiles snapshot list \
  --resource-group RT-CA-PRD-ANF-RG \
  --account-name anfacct-catorhyp \
  --pool-name sql-pool-prd \
  --volume-name sql-data \
  --query "[].{Name:name, Created:created}" -o table
```

### 5.4 Troubleshooting Runbook

#### Scenario 1: SMB share not accessible from SQL Server

```
Symptom: SQL Server service fails to start / databases in RECOVERY_PENDING
Check:
1. Test UNC path: Test-Path \\ANFSMB01\sql-data
2. Check ANF subnet delegation: Portal → VNet → Subnets → anf-delegated
3. Verify AD computer object for ANFSMB01 in AD
4. Check SMB signing: Get-SmbClientConfiguration | Select RequireSecuritySignature
5. Review ANF portal → Volume → Status should show "Available"
Resolution:
- If AD auth failure: rejoin ANF to domain via Portal → ANF Account → Active Directory
- If network: check NSG on anf-delegated subnet (no NSG should be applied to delegated subnet)
```

#### Scenario 2: High latency on sql-logs volume

```
Symptom: WRITELOG waits elevated in SQL wait stats; log write latency > 2 ms
Check:
1. Portal → ANF → sql-logs → Metrics → AverageWriteLatency
2. Check VolumeThroughput vs assigned (sql-logs currently set to 32 MiB/s)
   az netappfiles volume show ... --name sql-logs --query throughputMibps
3. Confirm volume is in the same AZ as the VM (cross-AZ adds latency)
Resolution:
- If throughput cap hit: increase sql-logs throughput from the Flexible pool budget
  az netappfiles volume update ... --name sql-logs --throughput-mibps 64
  (Flexible pool max for 4 TiB = 2,560 MiB/s; sum of all volume assignments must stay within that limit)
- If latency structural (> 3 ms consistently): verify ANF delegated subnet is in same AZ as VM
```

#### Scenario 3: Backup job failing or slow

```
Symptom: SQL Agent backup job times out; sql-backup at high consumed %
Check:
1. Portal → ANF → sql-backup → Metrics → VolumeConsumedSizePercentage
2. Check backup file count: dir \\ANFSMB01\sql-backup
3. Verify ANF snapshot policy isn't also consuming pool space unexpectedly
Resolution:
- Immediate: expand sql-backup quota (az netappfiles volume update --usage-threshold 2048)
- Long-term: implement backup file retention cleanup job
- Enable ANF Backup for sql-backup volume to offload old backups to vault storage
```

#### Scenario 4: Volume consumed percentage suddenly increases

```
Symptom: Alert fires — VolumeConsumedSizePercentage > 80% for sql-data
Check:
1. List snapshots and their ages — old snapshots hold delta data
2. Check for large transaction log VLF growth
3. Verify no unauthorized file copies placed on share
Resolution:
- Delete expired snapshots: az netappfiles snapshot delete ...
- Expand volume quota if legitimate data growth: --usage-threshold +256
```

---

## 6. Technical Validation Test Plan

### 6.1 Test Objectives

| # | Objective | Success Criterion |
|---|---|---|
| T1 | Confirm SQL Server connects and operates on ANF SMB3 volumes | All databases ONLINE; no errors in SQL error log |
| T2 | Performance parity or improvement vs baseline disks | P95 query response time within 10% of baseline; key waits (PAGEIOLATCH, WRITELOG) not degraded |
| T3 | Snapshot creation and restore (application-consistent) | Snapshot created in < 5 seconds; restore completes without data loss |
| T4 | ANF Cross-Zone Replication failover | DR volume mountable and SQL recoverable within 30 minutes |
| T5 | Capacity and throughput scaling (no downtime) | Volume quota expansion AND throughput rebalancing both take effect within 60 seconds; no SQL interruption |
| T6 | ANF Backup and restore (long-term) | Backup created; restore to new volume succeeds; data integrity validated |
| T7 | SQL Server Always On AG viability (if AG planned) | AG can use ANF SMB3 for shared witness or shared storage for FCI |

### 6.2 Test Environment

Use **CATORHYPSQLC1 (NPE)** as the validation target — it is the direct Non-Production equivalent of CATORHYPSQL1 (same SKU: D8s_v3, same disk layout, named volumes confirming SQL role mapping). This ensures production is not impacted during testing.

```
Test VM: CATORHYPSQLC1 (Standard_D8s_v3, NPE)
ANF test account: anfacct-catorhyp-npe (same ANF setup as target production design)
Test volumes: npe-sql-data, npe-sql-logs, npe-sql-tempdb, npe-sql-index, npe-sql-backup
Duration: 4 weeks (1 week setup, 1 week functional/perf, 1 week DR, 1 week ops)
```

### 6.3 Test Cases

#### T1 — Functional Connectivity

| Step | Action | Expected Result |
|---|---|---|
| T1.1 | Create ANF test volumes; mount as SMB3 UNC paths on CATORHYPSQLC1 | Drive letters map to ANF UNC paths successfully |
| T1.2 | Restore test database from backup to ANF sql-data and sql-logs | Database comes ONLINE without error |
| T1.3 | Run SQL DBCC CHECKDB on restored database | DBCC reports 0 errors |
| T1.4 | Create a new database with data, log, and tempdb files on ANF volumes | Database creation completes; files visible in ANF volume |
| T1.5 | Restart SQL Server service; confirm databases auto-mount | All databases return ONLINE after service restart |
| T1.6 | Simulate VM restart; confirm SMB reconnects automatically | SQL Server reconnects to ANF shares on boot via Persistent DFS mapping |

#### T2 — Performance Validation

**Baseline measurement** (before migration, on existing disks):

```powershell
# Run DiskSpd against existing disk paths
.\diskspd.exe -b8K -d300 -o32 -t4 -r -w30 -L -Z1G F:\testfile.dat > baseline_disk_perf.txt
.\diskspd.exe -b64K -d300 -o4 -t1 -s -w100 -L -Z1G G:\testfile.dat > baseline_log_perf.txt
```

**Post-migration measurement** (on ANF volumes, same parameters):

```powershell
.\diskspd.exe -b8K -d300 -o32 -t4 -r -w30 -L -Z1G \\ANFSMB01\npe-sql-data\testfile.dat > anf_data_perf.txt
.\diskspd.exe -b64K -d300 -o4 -t1 -s -w100 -L -Z1G \\ANFSMB01\npe-sql-logs\testfile.dat > anf_log_perf.txt
```

**SQL Server workload simulation:**

```sql
-- Simulate read-heavy OLTP workload (run for 30 minutes)
-- Use HammerDB or custom loop to simulate concurrent sessions

-- Capture I/O stats before and after
SELECT
    DB_NAME(vfs.database_id) AS db,
    mf.physical_name,
    vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) AS avg_read_ms,
    vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) AS avg_write_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id;
```

**Pass criteria:**
- Random 8K read latency: ≤ 2 ms (P95)
- Sequential write latency (log): ≤ 1.5 ms (P95)
- IOPS: at least equal to current disk observed peaks (306 IOPS max observed)
- Throughput: at least equal to current peak (36 MB/s max observed)

#### T3 — Snapshot: Create and Restore

| Step | Action | Expected Result |
|---|---|---|
| T3.1 | Freeze SQL I/O with `BACKUP DATABASE ... WITH SNAPSHOT` or VSS writer quiesce | SQL I/O frozen (< 5 sec) |
| T3.2 | Trigger ANF snapshot on sql-data and sql-logs simultaneously | Snapshot appears in ANF within 5 seconds |
| T3.3 | Unfreeze SQL I/O | Normal I/O resumes; no SQL errors |
| T3.4 | Delete a test table row from database | Row deleted |
| T3.5 | Revert volume to snapshot (or single-file restore from snapshot) | Deleted row recoverable |
| T3.6 | Run DBCC CHECKDB after restore | 0 errors |
| T3.7 | Measure revert time for sql-data (512 GiB volume) | Volume revert completes in < 5 minutes |

**ANF snapshot CLI commands for T3:**

```bash
# Freeze SQL (via SQL command or VSS), then:
az netappfiles snapshot create \
  --resource-group RT-CA-NPE-ANF-RG \
  --account-name anfacct-catorhyp-npe \
  --pool-name sql-pool-npe \
  --volume-name npe-sql-data \
  --name snapshot-t3-$(date +%Y%m%d%H%M)

# To revert volume to snapshot
az netappfiles volume revert \
  --resource-group RT-CA-NPE-ANF-RG \
  --account-name anfacct-catorhyp-npe \
  --pool-name sql-pool-npe \
  --name npe-sql-data \
  --snapshot-id <snapshot-resource-id>
```

#### T4 — Cross-Zone Replication Failover

| Step | Action | Expected Result |
|---|---|---|
| T4.1 | Configure CZR from npe-sql-data (AZ1) to npe-sql-data-dr (AZ2) | Replication status shows "Mirrored" |
| T4.2 | Wait for initial sync to complete | Mirror state: Mirrored |
| T4.3 | Commit writes to test database on primary | Transactions written |
| T4.4 | Wait replication interval (~20 min); confirm lag | Replication lag < 20 minutes |
| T4.5 | Simulate primary zone failure: stop writing, break replication | DR volume detached from primary |
| T4.6 | Authorize replication reversal on DR volume | DR volume becomes writable |
| T4.7 | Mount DR volumes on a DR VM; start SQL Server | SQL databases come ONLINE |
| T4.8 | Validate database is accessible; check for data loss | Confirm last committed transaction visible; measure data loss (RPO) |
| T4.9 | Measure total time from step T4.5 to T4.8 | RTO ≤ 30 minutes |

**CZR failover commands for T4:**

```bash
# Break replication and authorize DR volume
az netappfiles volume replication approve-external-replication \
  --resource-group RT-CA-NPE-ANF-RG \
  --account-name anfacct-catorhyp-npe \
  --pool-name sql-pool-npe-dr \
  --volume-name npe-sql-data-dr

# After DR testing, re-establish replication back to primary
az netappfiles volume replication re-initialize \
  --resource-group RT-CA-NPE-ANF-RG \
  --account-name anfacct-catorhyp-npe \
  --pool-name sql-pool-npe \
  --volume-name npe-sql-data
```

#### T5 — Capacity Scaling (No Downtime)

| Step | Action | Expected Result |
|---|---|---|
| T5.1 | Connect SQL; confirm npe-sql-backup is at initial quota (256 GiB) and throughput (16 MiB/s) | Volume shows 256 GiB to OS; pool shows 120 MiB/s assigned of 2,560 MiB/s Flexible max budget |
| T5.2 | Expand quota to 512 GiB via CLI (no SQL downtime) | Volume reports 512 GiB in OS within 60 seconds |
| T5.3 | Confirm no SQL interruption during resize | Active SQL queries continue uninterrupted |
| T5.4 | Write additional backup to fill beyond original 256 GiB boundary | Backup succeeds beyond old limit |
| T5.5 | Boost npe-sql-backup throughput to 150 MiB/s (VM NIC-limited) while SQL runs | Throughput limit raised; no SQL restart; backup job completes faster |
| T5.6 | Reduce npe-sql-backup back to 16 MiB/s; confirm sql-logs throughput unaffected | Pool rebalance takes effect; sql-logs latency unchanged |
| T5.7 | Attempt to assign total volume throughput exceeding Flexible pool max (e.g., try to set all volumes to sum > 2,560 MiB/s on a 4 TiB pool) | CLI returns error; pool budget enforcement confirmed |

#### T6 — ANF Backup and Long-Term Restore

| Step | Action | Expected Result |
|---|---|---|
| T6.1 | Enable ANF Backup policy on npe-sql-data (daily, retain 7 days) | Backup policy active; first backup completes |
| T6.2 | Verify backup stored independently of ANF capacity pool | ANF pool consumed size unchanged by backup |
| T6.3 | Restore ANF backup to a new volume | New volume created from backup |
| T6.4 | Mount restored volume; run DBCC CHECKDB | 0 errors; data matches expected state |
| T6.5 | Simulate accidental volume delete; restore from backup | Volume reconstructed from ANF Backup |

#### T7 — Operational Validation

| Step | Action | Expected Result |
|---|---|---|
| T7.1 | Simulate high backup volume consumption (fill sql-backup to 85%) | Alert fires in Azure Monitor (`VolumeConsumedSizePercentage > 80`) |
| T7.2 | Expand quota while SQL backup job is running | Backup job completes; no interruption |
| T7.3 | Simulate index rebuild: temporarily raise sql-index throughput from 8 to 128 MiB/s | Throughput change completes online; total pool allocation remains well within 2,560 MiB/s Flexible max |
| T7.4 | Restore sql-index to 8 MiB/s; confirm total pool allocation returns to baseline | Pool budget tracking correct |
| T7.5 | List all snapshots older than 7 days and delete via script | Snapshot cleanup completes; pool space reclaimed |
| T7.6 | Schedule nightly throughput boost for sql-backup via Azure Automation runbook | Runbook executes on schedule; throughput confirmed raised at 02:00 and reduced at 05:00 |

### 6.4 Success Criteria Summary

| Test | Pass Condition |
|---|---|
| T1 Functional | All databases ONLINE; DBCC 0 errors; auto-reconnect on restart |
| T2 Performance | Latency ≤ 2 ms (data), ≤ 1.5 ms (log); IOPS ≥ observed peaks; wait stats not degraded |
| T3 Snapshot | Snapshot < 5 sec; restore < 5 min; DBCC 0 errors |
| T4 CZR Failover | RTO ≤ 30 min; RPO ≤ 20 min; data accessible on DR VM |
| T5 Scale | Quota expansion AND throughput rebalancing < 60 sec; zero SQL downtime; Flexible pool budget enforcement confirmed |
| T6 ANF Backup | Backup stored outside pool; restore succeeds; DBCC 0 errors |
| T7 Ops | Alerts fire correctly; tier change online; snapshot cleanup functional |

### 6.5 Test Execution Timeline

| Week | Activity |
|---|---|
| **Week 1** | ANF NPE infrastructure setup; AD integration; volume creation; T1 functional tests |
| **Week 2** | T2 performance baseline vs ANF; T5 capacity scaling; T7 operational checks |
| **Week 3** | T3 snapshot create/restore; T6 ANF backup; T4 CZR setup and failover drill |
| **Week 4** | Full cutover rehearsal on CATORHYPSQLC1; document results; production readiness sign-off |
| **Week 5+** | Production migration of CATORHYPSQL1 using validated runbook |

### 6.6 Production Readiness Gate

Before proceeding to production migration of CATORHYPSQL1, all T1–T7 tests must pass and the following must be signed off:

- [ ] Network latency from CATORHYPSQL1 to ANF endpoint confirmed < 2 ms
- [ ] SQL Server error log clean (no SMB-related warnings) after 72-hour NPE soak
- [ ] ANF snapshot policy configured and first scheduled snapshot confirmed
- [ ] CZR replication established and lag < 20 minutes confirmed
- [ ] Rollback plan tested: original disks remain attached for 7-day post-cutover window
- [ ] Azure Monitor alerts active for `VolumeConsumedSizePercentage` and `VolumeThroughput`
- [ ] DBA runbook updated with ANF-specific commands (volume expand, snapshot, tier change)
- [ ] Backup drive capacity crisis resolved: sql-backup quota set to 1 TiB

---

## Appendix A: Cost Comparison Estimate

### Current monthly cost (CATORHYPSQL1 data disks only)

| Disk | SKU | Size | Est. Monthly Cost |
|---|---|---|---|
| disk01 | StandardSSD_LRS | 128 GB | ~$11 |
| disk02 | StandardSSD_LRS | 256 GB | ~$22 |
| disk03 | StandardSSD_LRS | 128 GB | ~$11 |
| disk04 | StandardSSD_LRS | 60 GB | ~$6 |
| disk05 | StandardSSD_LRS | 128 GB | ~$11 |
| **Total** | | **700 GB** | **~$61/month** |

### ANF target monthly cost — Single Flexible Service Level Pool (shared across 4 production VMs)

| Resource | Detail | Est. Monthly Cost |
|---|---|---|
| ANF Capacity Pool | 4 TiB, Flexible service level | ~$220–240/month |
| Snapshot delta storage | Varies by change rate (est. ~10% of consumed) | ~$5–15/month |
| ANF Backup (optional) | Per GiB of backup data | ~$10–20/month |
| **Total pool (4 VMs)** | | **~$235–275/month** |
| **Per-VM share (÷4)** | | **~$59–69/month per VM** |

**Single pool advantage:** A single Flexible capacity pool eliminates the need for separate Standard, Premium, and Ultra pools. The Flexible service level's large throughput ceiling (up to 2,560 MiB/s for a 4 TiB pool) allows individual volumes to be boosted well beyond what any Auto QoS tier offers — the D8s_v3 VM NIC (192 MB/s) is the practical limit, not the pool. All four production VMs share the 4 TiB pool, making cost per VM comparable to or lower than current Standard SSD disks while gaining 99.99% SLA, snapshots, CZR, and full throughput flexibility. The `--throughput-mibps` model means you only provision what is needed — there is no per-volume tier cost premium.

> **Note:** ANF is economical when the 4 TiB capacity pool is shared across multiple VMs (CATORHYPSQL1, CATORSQL17, CATORSQL5, CATORSQL6). A shared pool amortizes the fixed 4 TiB floor across all four production VMs, targeting cost neutrality or better vs. individual Premium SSD disks while gaining significantly higher SLA, snapshots, CZR, and data management capabilities. Detailed pricing should be validated with the Azure Pricing Calculator using Canada Central rates.

### Potential VM Rightsizing and SQL Server License Reduction (post-migration)

ANF's consistent low-latency I/O over SMB3 removes a common reason to over-provision compute: with direct-attached disks, DBAs often size VMs larger than the CPU workload requires to maintain IOPS and throughput headroom. With ANF, throughput is a pool-level parameter decoupled from VM size. This opens the door to a significant secondary cost saving.

**CATORHYPSQL1 CPU evidence (90-day observed):**

| Metric | Value |
|---|---|
| Average CPU utilization | 3.66% |
| Peak CPU utilization | 11.91% |
| Current VM SKU | Standard_D8s_v3 (8 vCPU, 32 GiB) |
| Potential right-sized SKU | Standard_D4s_v3 (4 vCPU, 16 GiB) |

> **Note on memory:** Peak memory is 94% on 32 GiB. If downsizing to D4s_v3 (16 GiB), memory must be re-evaluated post-migration before the resize. Consider D4ds_v5 or E4s_v5 (4 vCPU, 32 GiB) as an alternative that preserves memory while halving core count.

**Estimated monthly savings from VM + SQL license rightsizing (4 vCPU):**

| Cost Item | Current (8 vCPU) | Rightsized (4 vCPU) | Monthly Saving |
|---|---|---|---|
| VM compute (PAYG, Canada Central) | ~$277/month (D8s_v3 Windows) | ~$139/month (D4s_v3 Windows) | ~$138/month |
| SQL Server Standard license (4 × 2-core packs vs 2 × 2-core packs) | ~$1,195/month | ~$598/month | **~$597/month** |
| SQL Server Enterprise license (4 × 2-core packs vs 2 × 2-core packs) | ~$2,376/month | ~$1,188/month | **~$1,188/month** |

> SQL Server per-core pricing: Standard ~\$3,586/year per 2-core pack; Enterprise ~\$7,128/year per 2-core pack (retail). Actual costs depend on Microsoft licensing agreement (EA, CSP, or BYOL via Azure Hybrid Benefit).

**Total potential monthly saving per VM (ANF storage – disks + VM rightsizing + SQL license Standard):** ~$596 + $138 + ~$2/month disk saving = **~$736/month per VM** vs current baseline.

**Important caveats:**
- This rightsizing analysis applies only after the ANF migration is validated and post-migration CPU / memory behavior is confirmed stable for ≥ 30 days.
- Memory pressure (94% peak on CATORHYPSQL1) must be resolved before reducing RAM. If memory is the binding constraint, a memory-optimized SKU (e.g., Standard_E4s_v3: 4 vCPU, 32 GiB) preserves RAM while halving core license cost.
- Azure Hybrid Benefit (AHB) may already apply to the SQL license; verify with the RioTinto EA/CSP agreement before calculating net savings.
- This optimization is **not part of the migration design or test plan** — it is a post-migration cost review action.

---

## Appendix B: Key Reference Links

- [ANF Flexible service level — throughput examples](https://learn.microsoft.com/en-us/azure/azure-netapp-files/azure-netapp-files-service-levels#flexible-examples)
- [SQL Server on Azure NetApp Files (Microsoft Docs)](https://learn.microsoft.com/en-us/azure/azure-netapp-files/solutions-benefits-azure-netapp-files-sql-server)
- [ANF SMB volume requirements for SQL Server](https://learn.microsoft.com/en-us/azure/azure-netapp-files/azure-netapp-files-create-volumes-smb)
- [ANF Cross-Zone Replication](https://learn.microsoft.com/en-us/azure/azure-netapp-files/cross-zone-replication-introduction)
- [ANF Snapshot Policy](https://learn.microsoft.com/en-us/azure/azure-netapp-files/snapshots-introduction)
- [ANF Backup](https://learn.microsoft.com/en-us/azure/azure-netapp-files/backup-introduction)
- [DiskSpd download](https://github.com/microsoft/diskspd)
- [HammerDB for SQL Server load testing](https://www.hammerdb.com/)
