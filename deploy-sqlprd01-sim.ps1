<#
.SYNOPSIS
  Set up ANF test infrastructure for SQL Server migration feasibility testing.
  Creates: ANF account, Flexible capacity pool (Manual QoS), and 3 SMB volumes
  (sql-data, sql-logs, sql-backup) sized for a single Standard_B4ms test VM.

.REQUIREMENTS
  - VM already created in Azure portal (see README Appendix C for manual steps and spec)
  - configure-sql-vm.ps1 already run on the VM over RDP
  - ANF delegated subnet (/28) exists in garyVNet — set $ANFSubnetId below
  - Azure CLI logged in: az login
  - Contributor access on garyRG

.NOTES
  VM creation is intentionally manual — see README Appendix C for portal steps.
  This script handles only the ANF side of the test environment.
#>

param(
    [string]$SubscriptionId = "",      # leave blank to use current subscription
    [string]$ANFSubnetId    = ""       # full resource ID of the ANF delegated /28 subnet
                                       # e.g. /subscriptions/<sub>/resourceGroups/garyRG/providers/
                                       #      Microsoft.Network/virtualNetworks/garyVNet/subnets/anf-subnet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $ANFSubnetId) {
    throw "ANFSubnetId is required. Set it in the param block or pass it: -ANFSubnetId '/subscriptions/<sub>/resourceGroups/garyRG/providers/Microsoft.Network/virtualNetworks/garyVNet/subnets/anf-subnet'"
}

# ── Configuration ─────────────────────────────────────────────────────────────
$location   = "australiaeast"
$rg         = "garyRG"
$anfAccount = "anfacct-gary-test"
$anfPool    = "sql-pool-test"
$poolSizeTiB = 4       # Flexible pool minimum — max $(5 * 128 * 4) = 2,560 MiB/s; VM NIC is the practical ceiling
$adDomain   = ""       # Required for SMB volumes — set to your AD domain, e.g. "corp.contoso.com"
$adDNS      = ""       # AD DNS server IP
$adUser     = ""       # AD join account username (without domain prefix)
$adOU       = ""       # OU for ANF computer object (optional, leave blank to use default)

# ── Subscription ───────────────────────────────────────────────────────────────
if ($SubscriptionId) {
    az account set --subscription $SubscriptionId
}
Write-Host "Using subscription: $(az account show --query name -o tsv)"

# ── 1. ANF Account ─────────────────────────────────────────────────────────────
Write-Host "`n[1/4] Creating ANF account $anfAccount in $rg ($location)..."
az netappfiles account create `
    --resource-group $rg `
    --location $location `
    --name $anfAccount | Out-Null
Write-Host "  ANF account ready."

# ── 2. AD Connector (required before SMB volume creation) ─────────────────────
if ($adDomain -and $adDNS -and $adUser) {
    Write-Host "[2/4] Registering AD connector for domain $adDomain..."
    $adPass = Read-Host "AD join account password for $adUser" -AsSecureString
    $adPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adPass)
    )
    $ouArgs = if ($adOU) { @("--organizational-unit", $adOU) } else { @() }
    az netappfiles account ad add `
        --resource-group $rg `
        --name $anfAccount `
        --username $adUser `
        --password $adPlain `
        --domain $adDomain `
        --dns $adDNS `
        --smb-server-name ANFTEST01 `
        @ouArgs | Out-Null
    Write-Host "  AD connector registered — SMB server name: ANFTEST01"
} else {
    Write-Host "[2/4] Skipping AD connector — set `$adDomain, `$adDNS, `$adUser at the top of this script to enable SMB volumes."
    Write-Warning "SMB volume creation in step 4 will fail without an AD connector. Register it first."
}

# ── 3. Flexible Capacity Pool (Manual QoS) ────────────────────────────────────
Write-Host "[3/4] Creating Flexible capacity pool $anfPool ($poolSizeTiB TiB, Manual QoS)..."
az netappfiles pool create `
    --resource-group $rg `
    --location $location `
    --account-name $anfAccount `
    --pool-name $anfPool `
    --size $poolSizeTiB `
    --service-level Flexible `
    --qos-type Manual | Out-Null
Write-Host "  Pool budget: $poolSizeTiB TiB Flexible — max $($poolSizeTiB * 5 * 128) MiB/s (VM NIC ~1,500 Mbps is practical ceiling for B4ms)"

# ── 4. SMB Volumes — minimum 3 for migration feasibility test ─────────────────
Write-Host "[4/4] Creating SMB volumes..."
#
# Three volumes cover the essential migration paths:
#   sql-data   — migrate .mdf files to ANF (T1: connectivity, T3: snapshot/restore)
#   sql-logs   — migrate .ldf files; latency-sensitive (T1, T2)
#   sql-backup — migration staging + backup window test (T5: throughput scaling)
#
# All quotas are thin-provisioned — billing based on consumed GiB only.

$volumes = @(
    @{ Name = "sql-data";   QuotaGiB = 100; TputMiBs = 16 }   # SQL data files (.mdf)
    @{ Name = "sql-logs";   QuotaGiB = 100; TputMiBs = 8  }   # Transaction logs (.ldf)
    @{ Name = "sql-backup"; QuotaGiB = 256; TputMiBs = 8  }   # Backups + migration staging
)

foreach ($vol in $volumes) {
    Write-Host "  Creating $($vol.Name) — $($vol.QuotaGiB) GiB / $($vol.TputMiBs) MiB/s..."
    az netappfiles volume create `
        --resource-group $rg `
        --location $location `
        --account-name $anfAccount `
        --pool-name $anfPool `
        --name $vol.Name `
        --usage-threshold $vol.QuotaGiB `
        --throughput-mibps $vol.TputMiBs `
        --protocol-types CIFS `
        --subnet-id $ANFSubnetId | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Volume creation failed for $($vol.Name) (exit $LASTEXITCODE)." }
}

# ── Output ─────────────────────────────────────────────────────────────────────
Write-Host "`n========================================================="
Write-Host "  ANF Test Infrastructure — Ready"
Write-Host "========================================================="
Write-Host "  Account  : $anfAccount  ($rg, $location)"
Write-Host "  Pool     : $anfPool  ($poolSizeTiB TiB Flexible, Manual QoS)"
Write-Host ""
Write-Host "  Volumes  (thin-provisioned — billing on consumed GiB only):"
Write-Host "    \\ANFTEST01\sql-data   — 100 GiB / 16 MiB/s — SQL data files (.mdf)"
Write-Host "    \\ANFTEST01\sql-logs   — 100 GiB /  8 MiB/s — Transaction logs (.ldf)"
Write-Host "    \\ANFTEST01\sql-backup — 256 GiB /  8 MiB/s — Backups + migration staging"
Write-Host ""
Write-Host "  Next steps:"
Write-Host "    1. Mount SMB shares on the test VM (run on VM over RDP):"
Write-Host "         net use \\ANFTEST01\sql-data /persistent:yes"
Write-Host "         net use \\ANFTEST01\sql-logs /persistent:yes"
Write-Host "         net use \\ANFTEST01\sql-backup /persistent:yes"
Write-Host "    2. Follow README Section 3.3 to migrate TestDB from local F: to ANF volumes"
Write-Host "    3. Run T1–T7 test cases in README Section 6"
Write-Host ""
Write-Host "  To boost sql-backup throughput for T5 test (online, no restart):"
Write-Host "    az netappfiles volume update --resource-group $rg --account-name $anfAccount --pool-name $anfPool --name sql-backup --throughput-mibps 128"
Write-Host ""
Write-Host "  To clean up all ANF resources:"
Write-Host "    az netappfiles account delete --resource-group $rg --name $anfAccount --yes"
