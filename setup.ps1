<#
.SYNOPSIS
  Preps Windows for Ark: Survival Ascended server mod downloads via CFCore.

.DESCRIPTION
  - Installs/refreshes Windows trusted roots from Windows Update (fixes TLS handshakes).
  - Creates Mods and ModsUserData directories and grants Modify to your service account.
  - (Optional) Clears ModsUserData to force CFCore to regenerate its machine ID.
  - Adds firewall rules: outbound allowance for ArkAscendedServer.exe and inbound UDP for game/query ports.
  - (Optional) Does a brief warm-boot to let CFCore create its local context.

.NOTES
  Run as Administrator. Tested on Windows Server 2019/2022 & Windows 10/11.
#>

#region === USER CONFIG ===
# Path to your ASA install root (folder that contains ShooterGame\Binaries\Win64\ArkAscendedServer.exe)
$ServerRoot   = "C:\arkascendedserver"

# Full path to the server executable:
$ExePath      = Join-Path $ServerRoot "ShooterGame\Binaries\Win64\ArkAscendedServer.exe"

# Account the Windows Service (or scheduled task) runs under. Example: "MYDOMAIN\arksvc"
# Leave $null to skip ACL changes for a service account (Admins keep Modify).
$ServiceUser  = $null  # e.g. "MYDOMAIN\arksvc"

# (Optional) clear CFCore user context (forces regeneration of machine id on next boot)
$ResetModsUserData = $true

# Inbound ports you actually use:
$GamePortUDP  = 7777
$QueryPortUDP = 27015

# OPTIONAL: Do a "warm boot" for a short time so CFCore can init.
# Set to >0 seconds to enable. If enabled, set minimal args below.
$WarmBootSeconds = 0
$WarmBootArgs = @(
    "TheIsland_WP?SessionName=WarmBoot?Port=$GamePortUDP?QueryPort=$QueryPortUDP",
    "-NoBattleEye",
    "-server",
    "-log",
    "-automanagedmods"
)
#endregion === USER CONFIG ===

# Derived paths
$ModsDir        = Join-Path $ServerRoot "ShooterGame\Mods"
$ModsUserData   = Join-Path $ServerRoot "ShooterGame\ModsUserData"

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw "Please run this script in an elevated PowerShell session (Run as Administrator)."
    }
}

function New-Dir {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Grant-Modify {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Identity
    )
    Write-Host "Granting Modify on '$Path' to '$Identity'..."
    & icacls $Path /grant "${Identity}:(OI)(CI)M" /T | Out-Null
}

function Install-RootCertsFromWU {
    Write-Host "Refreshing Windows trusted roots from Windows Update (generating SST)..."
    $sst = Join-Path $env:TEMP "roots.sst"
    if (Test-Path $sst) { Remove-Item $sst -Force }
    # Generate from Windows Update
    & certutil.exe -generateSSTFromWU $sst | Out-Null
    if (-not (Test-Path $sst)) { throw "Failed to generate roots.sst (Windows Update not reachable?)." }

    Write-Host "Importing trusted roots into LocalMachine\Root..."
    & certutil.exe -addstore -f root $sst | Out-Null
    Write-Host "Importing trusted CAs into LocalMachine\AuthRoot..."
    & certutil.exe -addstore -f authroot $sst | Out-Null

    Remove-Item $sst -Force
    Write-Host "Root certificate refresh complete."
}

function Configure-Firewall {
    param([string]$Exe,[int]$GamePort,[int]$QueryPort)
    Write-Host "Adding outbound allow rule for Ark ASA executable..."
    $nameOut = "ARK ASA Outbound Allow"
    if (-not (Get-NetFirewallApplicationFilter -PolicyStore ActiveStore -ErrorAction SilentlyContinue | Where-Object Program -eq $Exe)) {
        New-NetFirewallRule -DisplayName $nameOut -Program $Exe -Direction Outbound -Action Allow -Profile Any | Out-Null
    }

    Write-Host "Ensuring inbound UDP rules for game/query ports..."
    $nameGame  = "ARK ASA UDP GamePort $GamePort"
    $nameQuery = "ARK ASA UDP QueryPort $QueryPort"

    if (-not (Get-NetFirewallRule -DisplayName $nameGame  -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $nameGame  -Direction Inbound -Action Allow -Protocol UDP -LocalPort $GamePort  -Program $Exe -Profile Any | Out-Null
    }
    if (-not (Get-NetFirewallRule -DisplayName $nameQuery -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $nameQuery -Direction Inbound -Action Allow -Protocol UDP -LocalPort $QueryPort -Program $Exe -Profile Any | Out-Null
    }
}

function Test-CFCoreConnectivity {
    [CmdletBinding()]
    param()

    $urls = @(
        "https://83374.api.curseforge.com",
        "https://analyticsnew.overwolf.com/analytics/Counter"
    )
    foreach ($u in $urls) {
        try {
            Write-Host "Testing HTTPS HEAD $u ..."
            $resp = Invoke-WebRequest -Uri $u -UseBasicParsing -Method Head -TimeoutSec 20
            Write-Host "  -> OK ($($resp.StatusCode))"
        } catch {
            Write-Warning "  -> FAILED: $($_.Exception.Message)"
        }
    }
}

function Warm-BootServer {
    param(
        [string]$Exe,
        [string[]]$Args,
        [int]$Seconds
    )
    if ($Seconds -le 0) { return }

    Write-Host "Starting warm boot for $Seconds seconds to let CFCore init..."
    $p = Start-Process -FilePath $Exe -ArgumentList $Args -PassThru -WindowStyle Hidden
    try {
        Start-Sleep -Seconds $Seconds
    } finally {
        if (!$p.HasExited) {
            Write-Host "Stopping warm boot process (PID $($p.Id))..."
            Stop-Process -Id $p.Id -Force
        }
    }
    Write-Host "Warm boot complete."
}

# === MAIN ===
try {
    Assert-Admin

    if (-not (Test-Path $ExePath)) {
        throw "ArkAscendedServer.exe not found at: $ExePath"
    }

    # 1) Trusted Roots (TLS)
    Install-RootCertsFromWU

    # 2) Folders + Permissions
    New-Dir -Path $ModsDir
    New-Dir -Path $ModsUserData

    # Always ensure Administrators have Modify
    Grant-Modify -Path $ModsDir      -Identity "Administrators"
    Grant-Modify -Path $ModsUserData -Identity "Administrators"

    if ($ServiceUser) {
        Grant-Modify -Path $ModsDir      -Identity $ServiceUser
        Grant-Modify -Path $ModsUserData -Identity $ServiceUser
    }

    # 3) Reset CFCore user context (optional)
    if ($ResetModsUserData -and (Test-Path $ModsUserData)) {
        Write-Host "Clearing CFCore user context at '$ModsUserData'..."
        Remove-Item -LiteralPath $ModsUserData -Recurse -Force
        New-Dir -Path $ModsUserData
        if ($ServiceUser) { Grant-Modify -Path $ModsUserData -Identity $ServiceUser }
    }

    # 4) Firewall rules
    Configure-Firewall -Exe $ExePath -GamePort $GamePortUDP -QueryPort $QueryPortUDP

    # 5) Quick connectivity sanity checks
    Test-CFCoreConnectivity

    # 6) Optional warm boot to let CFCore create its machine id
    Warm-BootServer -Exe $ExePath -Args $WarmBootArgs -Seconds $WarmBootSeconds

    Write-Host "`nAll done. Next step: start your server normally (service or console).`n" -ForegroundColor Green
    Write-Host "If you still see 'serverUnreachable' or 'No machine id was found' in LogCFCore," `
    "double-check that your service account is the SAME one that just gained folder permissions." `
    "On first run after this script, watch the log until CFCore initializes."
}
catch {
    Write-Error $_
    exit 1
}
