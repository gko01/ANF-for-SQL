<#
.SYNOPSIS
  Configure test SQL VM for ANF migration and technology feasibility testing.
  Minimum setup: 1 data disk (F:), all SQL directories on F:.
  Run this script manually on the VM over RDP after creating the VM in Azure portal.
  Tested with: Standard_B4ms, 1x 32 GB StandardSSD data disk, SQL Server 2022 Developer.

.REQUIREMENTS
  - VM created in Azure portal (see README Appendix C for manual steps and spec)
  - 1 data disk (32 GB, Standard SSD, LUN 0) attached to the VM
  - Run as Administrator in PowerShell on the VM
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step { param($n, $msg) Write-Host "`n[$n] $msg" -ForegroundColor Cyan }

# ── 1. Wait for the single data disk to appear ────────────────────────────────
Write-Step "1/5" "Waiting for 1 RAW data disk (LUN 0, 32 GB)..."

$maxWait = 120
$elapsed = 0
do {
    $rawDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' } | Sort-Object Number
    if ($rawDisks.Count -ge 1) { break }
    Start-Sleep -Seconds 10
    $elapsed += 10
    Write-Host "  Found $($rawDisks.Count)/1 RAW disks — waiting ($elapsed s)..."
} while ($elapsed -lt $maxWait)

if ($rawDisks.Count -lt 1) {
    throw "Expected at least 1 RAW data disk but found none after ${maxWait}s. Attach a 32 GB data disk in Azure portal and retry."
}

$disk   = $rawDisks[0]
$diskGB = [math]::Round($disk.Size / 1GB, 0)
Write-Host "  Found disk $($disk.Number) ($diskGB GB) — will format as F: [SQLData]"

# ── 2. Initialize disk and assign drive letter F: ─────────────────────────────
Write-Step "2/5" "Initializing disk and assigning drive letter F:..."

$disk | Initialize-Disk -PartitionStyle GPT -PassThru |
    New-Partition -DriveLetter 'F' -UseMaximumSize |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel 'SQLData' `
                  -AllocationUnitSize 65536 -Confirm:$false | Out-Null
# 64 KiB allocation unit — recommended for SQL Server data and log files

Write-Host "  Disk $($disk.Number) ($diskGB GB) → F: [SQLData]"

# ── 3. Create SQL directory structure on F: ───────────────────────────────────
Write-Step "3/5" "Creating SQL directory structure on F:..."

# All SQL roles share the single F: disk — sufficient for technology feasibility testing
$dirs = @(
    'F:\MSSQL\DATA'               # SQL data files (.mdf, .ndf)
    'F:\MSSQL\LOG'                # Transaction log files (.ldf)
    'F:\MSSQL\TEMPDB'             # TempDB data + log
    'F:\MSSQL\BACKUP'             # SQL Server backups
    'F:\MSSQL\BACKUP\MIGRATION'   # Migration staging (README Section 3.3 Phase A)
)

foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Write-Host "  $dir"
}

# Grant SQL Server service account full control on all SQL directories
$sqlServiceAccount = "NT SERVICE\MSSQLSERVER"
foreach ($dir in ($dirs | Where-Object { $_ -notlike '*MIGRATION*' })) {
    $acl = Get-Acl $dir
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sqlServiceAccount, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.SetAccessRule($rule)
    Set-Acl -Path $dir -AclObject $acl
}

# ── 4. Configure SQL Server ───────────────────────────────────────────────────
Write-Step "4/5" "Configuring SQL Server (paths, memory, TempDB)..."

# Wait for SQL Server service to be running
$retries = 0
do {
    $svc = Get-Service -Name MSSQLSERVER -ErrorAction SilentlyContinue
    if ($svc.Status -eq 'Running') { break }
    Write-Host "  Waiting for SQL Server service ($retries)..."
    Start-Sleep -Seconds 15
    $retries++
} while ($retries -lt 16)    # max 4 minutes

if ($svc.Status -ne 'Running') {
    throw "SQL Server service did not start after 4 minutes."
}

# Locate sqlcmd
$sqlcmd = @(
    "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE"
    "C:\Program Files\Microsoft SQL Server\110\Tools\Binn\SQLCMD.EXE"
    "sqlcmd"
) | Where-Object { Test-Path $_ -ErrorAction SilentlyContinue } | Select-Object -First 1

if (-not $sqlcmd) { $sqlcmd = "sqlcmd" }

# Helper: run T-SQL via sqlcmd (Windows auth — runs as SYSTEM which has sysadmin)
function Invoke-SQL {
    param([string]$query, [string]$label = "")
    if ($label) { Write-Host "  SQL: $label" }
    & $sqlcmd -S "localhost" -E -b -Q $query
    if ($LASTEXITCODE -ne 0) { Write-Warning "sqlcmd returned $LASTEXITCODE for: $label" }
}

# All SQL directories are on the single F: disk
Invoke-SQL -label "Default data/log/backup paths (all on F:)" -query @"
EXEC xp_instance_regwrite
    N'HKEY_LOCAL_MACHINE',
    N'Software\Microsoft\MSSQLServer\MSSQLServer',
    N'DefaultData', REG_SZ, N'F:\MSSQL\DATA';

EXEC xp_instance_regwrite
    N'HKEY_LOCAL_MACHINE',
    N'Software\Microsoft\MSSQLServer\MSSQLServer',
    N'DefaultLog', REG_SZ, N'F:\MSSQL\LOG';

EXEC xp_instance_regwrite
    N'HKEY_LOCAL_MACHINE',
    N'Software\Microsoft\MSSQLServer\MSSQLServer',
    N'BackupDirectory', REG_SZ, N'F:\MSSQL\BACKUP';
"@

# Standard_B4ms: 16 GiB total — leave 4 GiB for OS = 12 GiB for SQL
Invoke-SQL -label "Max server memory = 12288 MB (12 GiB for Standard_B4ms)" -query @"
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', 12288;
RECONFIGURE;
"@

# Enable SQL Server to accept remote connections (usually pre-enabled on marketplace image)
Invoke-SQL -label "Enable remote access" -query @"
EXEC sp_configure 'remote access', 1;
RECONFIGURE;
"@

# Relocate TempDB to F:\MSSQL\TEMPDB (requires SQL restart)
Invoke-SQL -label "Relocate TempDB to F:\MSSQL\TEMPDB" -query @"
USE master;
ALTER DATABASE tempdb
    MODIFY FILE (NAME = N'tempdev', FILENAME = N'F:\MSSQL\TEMPDB\tempdb.mdf');
ALTER DATABASE tempdb
    MODIFY FILE (NAME = N'templog', FILENAME = N'F:\MSSQL\TEMPDB\templog.ldf');
"@

# Open Windows Firewall for SQL Server 1433 (in case not done by marketplace image)
netsh advfirewall firewall add rule `
    name="SQL Server 1433" dir=in action=allow protocol=TCP localport=1433 | Out-Null

# ── 5. Restart SQL and create TestDB ─────────────────────────────────────────
Write-Step "5/5" "Restarting SQL Server and creating TestDB..."
Restart-Service -Name MSSQLSERVER -Force
Start-Sleep -Seconds 45

# ── Create TestDB for ANF migration feasibility test ─────────────────────────
# Simple two-file database (primary data + log) — sufficient to rehearse the
# backup/restore migration path and validate SMB3 connectivity to ANF volumes.

Invoke-SQL -label "Create TestDB (data and log on F:)" -query @"
IF DB_ID(N'TestDB') IS NULL
BEGIN
    CREATE DATABASE TestDB
    ON PRIMARY (
        NAME = N'TestDB_data',
        FILENAME = N'F:\MSSQL\DATA\TestDB.mdf',
        SIZE = 256MB, MAXSIZE = UNLIMITED, FILEGROWTH = 128MB
    )
    LOG ON (
        NAME = N'TestDB_log',
        FILENAME = N'F:\MSSQL\LOG\TestDB_log.ldf',
        SIZE = 64MB, MAXSIZE = UNLIMITED, FILEGROWTH = 32MB
    );
END
"@

# Seed workload table used for ANF feasibility test (T1 connectivity, T2 latency baseline)
Invoke-SQL -label "Seed WorkloadTest table" -query @"
USE TestDB;

IF OBJECT_ID(N'dbo.WorkloadTest', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.WorkloadTest (
        Id          INT           IDENTITY(1,1) NOT NULL
                        CONSTRAINT PK_WorkloadTest PRIMARY KEY CLUSTERED,
        BatchId     UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
        Payload     NVARCHAR(500) NOT NULL DEFAULT REPLICATE(N'X', 500),
        CreatedAt   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
    );

    -- Pre-populate 10,000 rows so queries have data to read (simulates SQLPRD01 steady state)
    INSERT INTO dbo.WorkloadTest (Payload)
    SELECT TOP 10000 REPLICATE(N'SEED', 125)
    FROM sys.all_columns a CROSS JOIN sys.all_columns b;
END
"@

# ── Verification output ───────────────────────────────────────────────────────
Write-Host "`n════ Verification ════════════════════════════════════════════"

Write-Host "`nDrive layout (F: — all SQL):"
Get-Volume | Where-Object { $_.DriveLetter -eq 'F' } |
    Select-Object DriveLetter, FileSystemLabel,
        @{N='AllocUnitKB'; E={ [math]::Round($_.AllocationUnitSize/1KB, 0) }},
        @{N='SizeGB';  E={ [math]::Round($_.Size/1GB, 0) }},
        @{N='FreeGB';  E={ [math]::Round($_.SizeRemaining/1GB, 1) }} |
    Format-Table -AutoSize

Write-Host "TempDB file locations:"
Invoke-SQL -query "SELECT name, physical_name, size*8/1024 AS size_mb FROM sys.master_files WHERE database_id = 2;"

Write-Host "SQL Server wait stats baseline (save for post-ANF comparison — README Section 3.1 Step 2):"
Invoke-SQL -query @"
SELECT wait_type,
       waiting_tasks_count,
       wait_time_ms,
       signal_wait_time_ms
FROM   sys.dm_os_wait_stats
WHERE  wait_type IN (
       'PAGEIOLATCH_SH','PAGEIOLATCH_EX','WRITELOG',
       'IO_COMPLETION','BACKUPIO')
ORDER BY wait_time_ms DESC;
"@

Write-Host "TestDB files:"
Invoke-SQL -query "SELECT name, physical_name, size*8/1024 AS size_mb FROM sys.master_files WHERE DB_NAME(database_id) = 'TestDB';"

Write-Host "`nConfiguration complete. TestDB ready for ANF migration feasibility test (README Section 6)."
