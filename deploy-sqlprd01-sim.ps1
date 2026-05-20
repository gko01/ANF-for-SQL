<#
.SYNOPSIS
  Deploy a SQLPRD01 simulation VM in Australia East for ANF test plan (README Section 6).
  Matches: Standard_D8s_v3, 5x StandardSSD_LRS disks, SQL Server 2022 Developer.

.REQUIREMENTS
  - Azure CLI (az) logged in: az login
  - Contributor access on target subscription
  - configure-sql-vm.ps1 in the same directory as this script
#>

param(
    [string]$SubscriptionId = "",           # leave blank to use current subscription
    [string]$AllowRdpFromCIDR = "*"         # SECURITY: restrict to your IP, e.g. "203.0.113.10/32"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Configuration ─────────────────────────────────────────────────────────────
$location    = "australiaeast"
$rg          = "garyRG"
$vmName      = "garySQLPRD01SIM"
$vmSize      = "Standard_D8s_v3"
$adminUser   = "sqladmin"
$sqlImage    = "MicrosoftSQLServer:sql2022-ws2022:sqldev-gen2:latest"
$diskSku     = "StandardSSD_LRS"
$osDiskSku   = "StandardSSD_LRS"
$vnetName    = "garyVNet"
$vmSubnet    = "workload-subnet"
$anfSubnet   = "anf-subnet"    # /28 delegated — ready for Section 3.2 ANF setup
$nsgName     = "gary-allow-lab-nsg"   # pre-existing NSG
$pipName     = "$vmName-pip"
$nicName     = "$vmName-nic"

# ── Validate configure script exists ──────────────────────────────────────────
$configScript = Join-Path $PSScriptRoot "configure-sql-vm.ps1"
if (-not (Test-Path $configScript)) {
    throw "configure-sql-vm.ps1 not found alongside this script. Cannot proceed."
}

# ── Password prompt ────────────────────────────────────────────────────────────
$secPass = Read-Host "Enter VM admin password (min 12 chars, upper+lower+digit+symbol)" -AsSecureString
$adminPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
)

# Validate password complexity (Azure requirement)
if ($adminPassword.Length -lt 12) { throw "Password must be at least 12 characters." }

# ── Subscription ───────────────────────────────────────────────────────────────
if ($SubscriptionId) {
    az account set --subscription $SubscriptionId
}
Write-Host "Using subscription: $(az account show --query name -o tsv)"

# ── 1. Resource Group ──────────────────────────────────────────────────────────
Write-Host "`n[1/8] Creating resource group $rg in $location..."
az group create --name $rg --location $location --tags "Purpose=SQLPRD01-Simulation" "Project=ANF-Evaluation" | Out-Null

# ── 2. VNet + Subnets ─────────────────────────────────────────────────────────
Write-Host "[2/8] Creating VNet and subnets..."
#az network vnet create `
#    --resource-group $rg `
#    --name $vnetName `
#    --location $location `
#    --address-prefix "10.10.0.0/16" | Out-Null

# VM subnet
#az network vnet subnet create `
#    --resource-group $rg `
#    --vnet-name $vnetName `
#    --name $vmSubnet `
#    --address-prefix "10.10.1.0/24" | Out-Null

# ANF delegated subnet (/28 minimum — required for ANF volumes in Section 3.2)
#az network vnet subnet create `
#    --resource-group $rg `
#    --vnet-name $vnetName `
#    --name $anfSubnet `
#    --address-prefix "10.10.2.0/28" `
#    --delegations "Microsoft.NetApp/volumes" | Out-Null

#Write-Host "  VM subnet:  10.10.1.0/24"
#Write-Host "  ANF subnet: 10.10.2.0/28 (delegated — ready for Section 3.2)"

# ── 3. NSG ────────────────────────────────────────────────────────────────────
Write-Host "[3/8] Using existing NSG: $nsgName (skipping creation)..."
# NSG gary-allow-lab-nsg is pre-existing — no rules added here

# ── 4. Public IP + NIC ────────────────────────────────────────────────────────
Write-Host "[4/8] Ensuring public IP and NIC exist..."

$ErrorActionPreference = "SilentlyContinue"
$pipExists = az network public-ip show --resource-group $rg --name $pipName --query "name" -o tsv 2>$null
$ErrorActionPreference = "Stop"
if (-not $pipExists) {
    Write-Host "  Creating public IP $pipName..."
    az network public-ip create `
        --resource-group $rg --name $pipName --location $location `
        --sku Standard --allocation-method Static --zone 1 | Out-Null
} else {
    Write-Host "  Public IP $pipName already exists, skipping."
}

$ErrorActionPreference = "SilentlyContinue"
$nicExists = az network nic show --resource-group $rg --name $nicName --query "name" -o tsv 2>$null
$ErrorActionPreference = "Stop"
if (-not $nicExists) {
    Write-Host "  Creating NIC $nicName..."
    az network nic create `
        --resource-group $rg --name $nicName --location $location `
        --vnet-name $vnetName --subnet $vmSubnet `
        --network-security-group $nsgName `
        --public-ip-address $pipName | Out-Null
} else {
    Write-Host "  NIC $nicName already exists, updating NSG to $nsgName..."
    az network nic update --resource-group $rg --name $nicName --network-security-group $nsgName | Out-Null
}

# ── 5. VM Creation ────────────────────────────────────────────────────────────
Write-Host "[5/8] Creating VM with SQL Server 2022 Developer image (10-15 min)..."

$ErrorActionPreference = "SilentlyContinue"
$vmExists = az vm show --resource-group $rg --name $vmName --query "name" -o tsv 2>$null
$ErrorActionPreference = "Stop"
if ($vmExists) {
    Write-Host "  VM $vmName already exists, skipping creation."
} else {
    az vm create `
        --resource-group $rg `
        --name $vmName `
        --location $location `
        --size $vmSize `
        --image $sqlImage `
        --authentication-type password `
        --os-disk-name "$vmName-osdisk" `
        --os-disk-size-gb 127 `
        --storage-sku "$osDiskSku" `
        --nics $nicName `
        --admin-username $adminUser `
        --admin-password $adminPassword `
        --enable-agent true `
        --tags "Role=SQLPRD01-Simulation" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "VM creation failed (exit $LASTEXITCODE). Check az error above." }
    Write-Host "  VM created. Waiting for agent to become ready..."
    Start-Sleep -Seconds 60
}

# ── 6. Attach 5 Data Disks (same LUN/letter layout as SQLPRD01; 32 GB each to minimise cost) ──────
Write-Host "[6/8] Attaching data disks..."
#  LUN  Size    Drive  Role
#   0    32 GB   F:    SQL Data   (production: 128 GB)
#   1    32 GB   J:    SQL Backup (production: 256 GB)
#   2    32 GB   G:    SQL Logs   (production: 128 GB)
#   3    32 GB   I:    SQL Index  (production: 60 GB)
#   4    32 GB   H:    SQL TempDB (production: 128 GB)

$disks = @(
    @{ Lun = 0; Name = "$vmName-disk01"; SizeGB = 32 }
    @{ Lun = 1; Name = "$vmName-disk02"; SizeGB = 32 }
    @{ Lun = 2; Name = "$vmName-disk03"; SizeGB = 32 }
    @{ Lun = 3; Name = "$vmName-disk04"; SizeGB = 32 }
    @{ Lun = 4; Name = "$vmName-disk05"; SizeGB = 32 }
)

foreach ($disk in $disks) {
    Write-Host "  LUN $($disk.Lun): $($disk.Name) ($($disk.SizeGB) GB $diskSku)"
    $ErrorActionPreference = "SilentlyContinue"
    $diskManagedBy = az disk show --resource-group $rg --name $disk.Name --query "managedBy" -o tsv 2>$null
    $ErrorActionPreference = "Stop"
    if ($diskManagedBy -and $diskManagedBy -like "*$vmName*") {
        Write-Host "    Disk $($disk.Name) already attached to $vmName, skipping."
    } elseif ($diskManagedBy -ne $null -and $diskManagedBy -ne "") {
        # Exists but attached to a different VM — fail fast
        throw "Disk $($disk.Name) is attached to another VM: $diskManagedBy"
    } elseif ($diskManagedBy -eq "") {
        # Exists, unattached — attach without --new
        Write-Host "    Disk $($disk.Name) exists unattached, attaching..."
        az vm disk attach `
            --resource-group $rg `
            --vm-name $vmName `
            --name $disk.Name `
            --lun $disk.Lun | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Disk attach failed for LUN $($disk.Lun) (exit $LASTEXITCODE)." }
    } else {
        # Does not exist — create and attach
        az vm disk attach `
            --resource-group $rg `
            --vm-name $vmName `
            --name $disk.Name `
            --new `
            --size-gb $disk.SizeGB `
            --sku $diskSku `
            --lun $disk.Lun | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Disk attach failed for LUN $($disk.Lun) (exit $LASTEXITCODE)." }
    }
}

# ── 7. In-VM Configuration via Custom Script Extension ──────────────────────────────
Write-Host "[7/8] Running in-VM configuration via Custom Script Extension..."

# Script is downloaded directly from GitHub — avoids az run-command 4 KB inline limit
# JSON is written to a temp file to avoid PowerShell 5.x quoting stripping
$scriptUri = "https://raw.githubusercontent.com/gko01/ANF-for-SQL/main/configure-sql-vm.ps1"
$cseJson = [ordered]@{
    fileUris        = @($scriptUri)
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -File configure-sql-vm.ps1"
} | ConvertTo-Json -Compress
$tmpSettings = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($tmpSettings, $cseJson, [System.Text.Encoding]::UTF8)

az vm extension set `
    --resource-group $rg `
    --vm-name $vmName `
    --name CustomScriptExtension `
    --publisher Microsoft.Compute `
    --version 1.10 `
    --settings "@$tmpSettings"
$cseExit = $LASTEXITCODE
Remove-Item $tmpSettings -Force -ErrorAction SilentlyContinue
if ($cseExit -ne 0) { throw "Custom Script Extension failed (exit $cseExit)." }

# ── 8. Output Connection Info ─────────────────────────────────────────────────
Write-Host "[8/8] Retrieving connection details..."
$pip = az network public-ip show --resource-group $rg --name $pipName --query "ipAddress" -o tsv

Write-Host "`n========================================================="
Write-Host "  SQLPRD01 Simulation VM - Ready"
Write-Host "========================================================="
Write-Host "  VM Name       : $vmName"
Write-Host "  Region        : $location (Australia East)"
Write-Host "  Size          : $vmSize (8 vCPU, 32 GiB - matches SQLPRD01)"
Write-Host "  Public IP     : $pip"
Write-Host "  RDP           : mstsc /v:$pip"
Write-Host "  Admin user    : $adminUser"
Write-Host "  SQL Instance  : $vmName (default instance, Windows auth)"
Write-Host "  SQL TCP port  : 1433 (VNet-scoped; RDP in for management)"
Write-Host ""
Write-Host "  Drive layout (test VM - 32 GB data disks; production sizes in Section 2.1):"
Write-Host "    C: - OS (127 GB StandardSSD)"
Write-Host "    D: - Temp disk (Azure ephemeral)"
Write-Host "    F: - SQL Data     32 GB StandardSSD  LUN 0  ($vmName-disk01)"
Write-Host "    G: - SQL Logs     32 GB StandardSSD  LUN 2  ($vmName-disk03)"
Write-Host "    H: - SQL TempDB   32 GB StandardSSD  LUN 4  ($vmName-disk05)"
Write-Host "    I: - SQL Index    32 GB StandardSSD  LUN 3  ($vmName-disk04)"
Write-Host "    J: - SQL Backup   32 GB StandardSSD  LUN 1  ($vmName-disk02)"
Write-Host ""
Write-Host "  ANF subnet ready: 10.10.2.0/28 (delegated) - use for Section 3.2"
Write-Host ""
Write-Host "  To clean up: az group delete --name $rg --yes --no-wait"
