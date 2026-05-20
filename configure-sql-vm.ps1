<#
.SYNOPSIS
  Configure SQLPRD01SIM — disk layout, SQL Server paths, TempDB, test database.
  Runs inside the VM via az vm run-command (called by deploy-sqlprd01-sim.ps1)
  or manually over RDP.
  Matches SQLPRD01 production disk layout exactly.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step { param($n, $msg) Write-Host "`n[$n] $msg" -ForegroundColor Cyan }

# ── 1. Wait for all 5 data disks to appear ────────────────────────────────────
Write-Step "1/6" "Waiting for 5 RAW data disks..."

$maxWait = 120
$elapsed = 0
do {
    $rawDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' } | Sort-Object Number
    if ($rawDisks.Count -eq 5) { break }
    Start-Sleep -Seconds 10
    $elapsed += 10
    Write-Host "  Found $($rawDisks.Count)/5 RAW disks — waiting ($elapsed s)..."
} while ($elapsed -lt $maxWait)

if ($rawDisks.Count -ne 5) {
    throw "Expected 5 RAW disks but found $($rawDisks.Count) after ${maxWait}s. Check disk attachment."
}

# ── 2. Initialize disks and assign drive letters ───────────────────────────────
Write-Step "2/6" "Initializing disks and assigning drive letters..."
#
# Azure presents data disks sorted by LUN in disk-number order (after OS=0 and Temp=1).
# Sorted RAW disks map to LUNs 0-4 in order:
#   Index 0  →  LUN 0, 32 GB  →  F: SQLData
#   Index 1  →  LUN 1, 32 GB  →  J: SQLBackup
#   Index 2  →  LUN 2, 32 GB  →  G: SQLLogs
#   Index 3  →  LUN 3, 32 GB  →  I: SQLIndex
#   Index 4  →  LUN 4, 32 GB  →  H: SQLTempDB

$driveMap = @(
    [PSCustomObject]@{ Letter = 'F'; Label = 'SQLData';   ExpectedGB = 32 }   # LUN 0
    [PSCustomObject]@{ Letter = 'J'; Label = 'SQLBackup'; ExpectedGB = 32 }   # LUN 1
    [PSCustomObject]@{ Letter = 'G'; Label = 'SQLLogs';   ExpectedGB = 32 }   # LUN 2
    [PSCustomObject]@{ Letter = 'I'; Label = 'SQLIndex';  ExpectedGB = 32 }   # LUN 3
    [PSCustomObject]@{ Letter = 'H'; Label = 'SQLTempDB'; ExpectedGB = 32 }   # LUN 4
)

for ($i = 0; $i -lt $rawDisks.Count; $i++) {
    $disk  = $rawDisks[$i]
    $drive = $driveMap[$i]
    $diskGB = [math]::Round($disk.Size / 1GB, 0)

    if ($diskGB -ne $drive.ExpectedGB) {
        Write-Warning "Disk $($disk.Number): expected $($drive.ExpectedGB) GB, got $diskGB GB. Check LUN order."
    }

    Write-Host "  Disk $($disk.Number) ($diskGB GB) → $($drive.Letter): [$($drive.Label)]"

    $disk | Initialize-Disk -PartitionStyle GPT -PassThru |
        New-Partition -DriveLetter $drive.Letter -UseMaximumSize |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel $drive.Label `
                      -AllocationUnitSize 65536 -Confirm:$false | Out-Null
    # 64 KiB allocation unit — recommended for SQL Server data and log files
}

# ── 3. Create SQL directory structure ─────────────────────────────────────────
Write-Step "3/6" "Creating SQL directory structure..."

$dirs = @(
    'F:\MSSQL\DATA'               # SQL data files (.mdf, .ndf)
    'G:\MSSQL\LOG'                # Transaction log files (.ldf)
    'H:\MSSQL\TEMPDB'             # TempDB data + log
    'I:\MSSQL\INDEX'              # Secondary filegroup / index files
    'J:\MSSQL\BACKUP'             # SQL Server backups
    'J:\MSSQL\BACKUP\MIGRATION'   # Migration staging (README Section 3.3 Phase A)
)

foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Write-Host "  $dir"
}

# Grant SQL Server service account full control on each directory
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
Write-Step "4/6" "Configuring SQL Server (paths, memory, TempDB)..."

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

# Default data, log, and backup paths for all NEW databases
Invoke-SQL -label "Default data/log/backup paths" -query @"
EXEC xp_instance_regwrite
    N'HKEY_LOCAL_MACHINE',
    N'Software\Microsoft\MSSQLServer\MSSQLServer',
    N'DefaultData', REG_SZ, N'F:\MSSQL\DATA';

EXEC xp_instance_regwrite
    N'HKEY_LOCAL_MACHINE',
    N'Software\Microsoft\MSSQLServer\MSSQLServer',
    N'DefaultLog', REG_SZ, N'G:\MSSQL\LOG';

EXEC xp_instance_regwrite
    N'HKEY_LOCAL_MACHINE',
    N'Software\Microsoft\MSSQLServer\MSSQLServer',
    N'BackupDirectory', REG_SZ, N'J:\MSSQL\BACKUP';
"@

# Max server memory: 32 GiB VM, leave 4 GiB for OS = 28 GiB for SQL
# Matches SQLPRD01 observed 81-94% memory utilisation
Invoke-SQL -label "Max server memory = 28672 MB (28 GiB)" -query @"
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', 28672;
RECONFIGURE;
"@

# Enable SQL Server to accept remote connections (usually pre-enabled on marketplace image)
Invoke-SQL -label "Enable remote access" -query @"
EXEC sp_configure 'remote access', 1;
RECONFIGURE;
"@

# Move TempDB data and log files to H:\MSSQL\TEMPDB (requires SQL restart)
Invoke-SQL -label "Relocate TempDB to H:" -query @"
USE master;
ALTER DATABASE tempdb
    MODIFY FILE (NAME = N'tempdev', FILENAME = N'H:\MSSQL\TEMPDB\tempdb.mdf');
ALTER DATABASE tempdb
    MODIFY FILE (NAME = N'templog', FILENAME = N'H:\MSSQL\TEMPDB\templog.ldf');
"@

# Open Windows Firewall for SQL Server 1433 (in case not done by marketplace image)
netsh advfirewall firewall add rule `
    name="SQL Server 1433" dir=in action=allow protocol=TCP localport=1433 | Out-Null

# ── 5. Restart SQL to apply TempDB path change ────────────────────────────────
Write-Step "5/6" "Restarting SQL Server (TempDB relocation takes effect on restart)..."
Restart-Service -Name MSSQLSERVER -Force
Start-Sleep -Seconds 45

# ── 6. Create TestDB for ANF test plan (README Section 6) ────────────────────
Write-Step "6/6" "Creating TestDB for ANF evaluation test cases..."

Invoke-SQL -label "Create TestDB (data on F:, log on G:, index filegroup on I:)" -query @"
IF DB_ID(N'TestDB') IS NULL
BEGIN
    CREATE DATABASE TestDB
    ON PRIMARY (
        NAME = N'TestDB_data',
        FILENAME = N'F:\MSSQL\DATA\TestDB.mdf',
        SIZE = 512MB, MAXSIZE = UNLIMITED, FILEGROWTH = 256MB
    ),
    FILEGROUP [INDEXES] (
        NAME = N'TestDB_index',
        FILENAME = N'I:\MSSQL\INDEX\TestDB_idx.ndf',
        SIZE = 64MB, MAXSIZE = UNLIMITED, FILEGROWTH = 64MB
    )
    LOG ON (
        NAME = N'TestDB_log',
        FILENAME = N'G:\MSSQL\LOG\TestDB_log.ldf',
        SIZE = 128MB, MAXSIZE = UNLIMITED, FILEGROWTH = 64MB
    );
END
"@

# Seed workload table used by Section 6.3 T2 (DiskSpd + HammerDB simulation)
Invoke-SQL -label "Seed WorkloadTest table (T2 perf baseline)" -query @"
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

Write-Host "`nDrive layout:"
Get-Volume | Where-Object { $_.DriveLetter -in @('F','G','H','I','J') } |
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

Write-Host "`nConfiguration complete. VM mirrors SQLPRD01 disk layout."
Write-Host "Ready for ANF test plan (README Section 6)."
