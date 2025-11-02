#requires -Version 5.1
param(
# Top-level command
  [Parameter(Mandatory=$true, Position=0)]
  [ValidateSet('setup','start','update','prefetch')]
  [string]$Command,

# Shared
  [string]$WorkingDir = "C:\arkascendedserver\ShooterGame\Binaries\Win64",
  [switch]$BootstrapIfMissing,
  [switch]$NoFirewall,
  [string]$Branch = "",
  [string]$BetaPassword = "",

# Server runtime settings
  [string]$Map = "TheIsland_WP",
  [string]$SessionName = "My ASA Server",
  [int]$MaxPlayers = 16,
  [int]$GamePort = 7777,
  [int]$QueryPort = 27015,
  [Nullable[int]]$RCONPort = 27020,
  [string]$ServerPassword = "",
  [string]$ServerAdminPassword = ""
)

# =====================[ Helpers ]=====================

function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "This action requires an elevated PowerShell (Run as Administrator)." }
}

function Ensure-Folder {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Get-ChocolateyExe {
  $defaultPath = 'C:\ProgramData\chocolatey\bin\choco.exe'
  if (Test-Path -LiteralPath $defaultPath) { return $defaultPath }

  $command = Get-Command choco.exe -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }

  throw "Chocolatey (choco.exe) is required but was not found. Install Chocolatey from https://chocolatey.org/install and re-run this script."
}

function Get-SteamCmdPath {
  $command = Get-Command steamcmd.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command) { return $command.Source }

  $chocoDefault = Join-Path 'C:\ProgramData\chocolatey\lib\steamcmd\tools\steamcmd' 'steamcmd.exe'
  if (Test-Path -LiteralPath $chocoDefault) { return $chocoDefault }

  return $null
}

function Get-RootFromWorkingDir {
  param([Parameter(Mandatory=$true)][string]$WorkingDir)

  # Avoid Resolve-Path if it doesn't exist yet (fresh machine).
  $wd = $WorkingDir
  if (Test-Path -LiteralPath $WorkingDir) {
    try { $wd = (Resolve-Path -LiteralPath $WorkingDir -ErrorAction Stop).Path } catch { $wd = $WorkingDir }
  }

  # Walk up the tree without "if-as-expression" (PS5-safe).
  $lvl1 = Split-Path -Path $wd -Parent           # ...\Binaries
  $lvl2 = $null; if ($lvl1) { $lvl2 = Split-Path -Path $lvl1 -Parent }   # ...\ShooterGame
  $lvl3 = $null; if ($lvl2) { $lvl3 = Split-Path -Path $lvl2 -Parent }   # root (expected)

  $root = $lvl3
  if (-not $root) { $root = $lvl2 }
  if (-not $root) { $root = $lvl1 }
  if (-not $root) { $root = Split-Path -Path $wd -Parent }
  if (-not $root) { $root = (Get-Location).Path }
  return $root
}

function Test-VCppRedistInstalled {
  $keys = @(
    'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
  )
  foreach ($k in $keys) {
    try {
      $v = Get-ItemProperty -Path $k -ErrorAction Stop
      if ($v.Installed -eq 1 -and $v.Major -ge 14) { return $true }
    } catch {}
  }
  return $false
}

function Install-VCppRedist {
  Write-Host "Checking Microsoft Visual C++ 2015–2022 Redistributable (x64)..."

  if (Test-VCppRedistInstalled) { Write-Host "VC++ Redist already installed."; return }

  $chocoPath = Get-ChocolateyExe
  Write-Host "Installing VC++ Redist via Chocolatey ($chocoPath)..."
  & $chocoPath install vcredist140 -y --no-progress
  if ($LASTEXITCODE -ne 0) {
    throw "Chocolatey failed to install vcredist140 (exit code $LASTEXITCODE)."
  }
  if (-not (Test-VCppRedistInstalled)) {
    throw "Chocolatey completed, but the Microsoft Visual C++ 2015–2022 Redistributable (x64) is still not detected."
  }
  Write-Host "VC++ Redist installed via Chocolatey."
}

function Ensure-SteamCMD {
  param([Parameter(Mandatory)][string]$BaseDir)
  Assert-Admin

  $existingSteamCmd = Get-SteamCmdPath
  if ($existingSteamCmd) {
    Write-Host "SteamCMD already available at $existingSteamCmd"
    return $existingSteamCmd
  }

  $chocoPath = Get-ChocolateyExe
  Write-Host "Installing SteamCMD via Chocolatey ($chocoPath)..."
  & $chocoPath install steamcmd -y --no-progress
  if ($LASTEXITCODE -ne 0) {
    throw "Chocolatey failed to install steamcmd (exit code $LASTEXITCODE)."
  }

  $steamCmdExe = Get-SteamCmdPath
  if (-not $steamCmdExe) {
    throw "SteamCMD installation via Chocolatey completed but steamcmd.exe was not found."
  }

  Write-Host "SteamCMD installed at $steamCmdExe"
  return $steamCmdExe
}

function Ensure-ASAServerFiles {
  param(
    [Parameter(Mandatory)][string]$BaseDir,
    [Parameter(Mandatory)][string]$SteamCmdExe,
    [string]$Branch = "",
    [string]$BetaPassword = ""
  )
  Assert-Admin

  $appId      = "2430930"
  $installDir = $BaseDir

  Ensure-Folder $installDir

  $login = "+login anonymous"
  if ($Branch -and $Branch.Trim()) {
    $branchArgs = "+app_update $appId -beta $Branch"
    if ($BetaPassword -and $BetaPassword.Trim()) {
      $branchArgs = "$branchArgs -betapassword $BetaPassword"
    }
    $branchArgs = "$branchArgs validate"
  } else {
    $branchArgs = "+app_update $appId validate"
  }

  $args = @(
    "+force_install_dir `"$installDir`""
    $login
    $branchArgs
    "+quit"
  ) -join ' '

  Write-Host "Syncing ASA server files to $installDir (first run may take a while)..."
  & $SteamCmdExe $args
  if ($LASTEXITCODE -ne 0) {
    throw "SteamCMD failed to install/update ASA server (exit $LASTEXITCODE)."
  }
  Write-Host "ASA server files are present."
}

function Ensure-FirewallRules {
  param([switch]$SkipFirewall)

  if ($SkipFirewall) { Write-Host "Skipping firewall configuration per -NoFirewall."; return }
  Assert-Admin

  $rules = @(
    @{ Name="ASA_UDP_7777";  Protocol="UDP"; Port=7777 },
    @{ Name="ASA_UDP_7778";  Protocol="UDP"; Port=7778 },
    @{ Name="ASA_UDP_27015"; Protocol="UDP"; Port=27015 },
    @{ Name="ASA_TCP_27020"; Protocol="TCP"; Port=27020 }
  )

  foreach ($r in $rules) {
    $Name=$r.Name; $Protocol=$r.Protocol; $Port=$r.Port
    $existing = Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue
    if (-not $existing) {
      New-NetFirewallRule -DisplayName $Name -Direction Inbound -Action Allow -Protocol $Protocol -LocalPort $Port | Out-Null
      Write-Host ("Created firewall rule: {0} ({1} {2})" -f $Name, $Protocol, $Port)
    } else {
      Write-Host ("Firewall rule already exists: {0}" -f $Name)
    }
  }
}

function Bootstrap-IfNeeded {
  param(
    [Parameter(Mandatory)][string]$WorkingDir,
    [switch]$NoFirewall,
    [string]$Branch = "",
    [string]$BetaPassword = ""
  )
  $baseDir = Get-RootFromWorkingDir -WorkingDir $WorkingDir
  Ensure-Folder $baseDir

  Install-VCppRedist
  $steamCmd = Ensure-SteamCMD -BaseDir $baseDir
  Ensure-ASAServerFiles -BaseDir $baseDir -SteamCmdExe $steamCmd -Branch $Branch -BetaPassword $BetaPassword
  Ensure-FirewallRules -SkipFirewall:$NoFirewall

  Write-Host "Bootstrap complete."
}

function Start-ASAServer {
  param(
    [Parameter(Mandatory)][string]$WorkingDir,
    [string]$Map,
    [string]$SessionName,
    [int]$MaxPlayers,
    [int]$GamePort,
    [int]$QueryPort,
    [Nullable[int]]$RCONPort,
    [string]$ServerPassword,
    [string]$ServerAdminPassword
  )

  $exe = Join-Path $WorkingDir "ShooterGameServer.exe"
  if (-not (Test-Path -LiteralPath $exe)) {
    throw "Server binary not found at $exe"
  }

  # Build map + query string safely
  $urlParts = @()
  $urlParts += "$Map"
  $urlParts += "?SessionName=$([uri]::EscapeDataString($SessionName))"
  $urlParts += "?Port=$GamePort"
  $urlParts += "?QueryPort=$QueryPort"
  $urlParts += "?MaxPlayers=$MaxPlayers"
  if ($ServerPassword)      { $urlParts += "?ServerPassword=$ServerPassword" }
  if ($ServerAdminPassword) { $urlParts += "?ServerAdminPassword=$ServerAdminPassword" }
  if ($null -ne $RCONPort)  { $urlParts += "?RCONPort=$RCONPort" }

  $mapAndParams = $urlParts -join ""

  # Add 'listen' with a leading space (do not put comments inside strings)
  $args = @($mapAndParams + " listen")

  Write-Host "Launching ASA server..."
  Write-Host "Path: $exe"
  Write-Host "Args: $($args -join ' ')"
  Start-Process -FilePath $exe -ArgumentList $args -NoNewWindow
}

# =====================[ Command Dispatch ]=====================

switch ($Command) {
  'setup' {
    try {
      Bootstrap-IfNeeded -WorkingDir $WorkingDir -NoFirewall:$NoFirewall -Branch $Branch -BetaPassword $BetaPassword
    } catch { Write-Error $_; exit 1 }
    break
  }

  'start' {
    if ($BootstrapIfMissing) {
      try { Bootstrap-IfNeeded -WorkingDir $WorkingDir -NoFirewall:$NoFirewall -Branch $Branch -BetaPassword $BetaPassword }
      catch { Write-Error $_; exit 1 }
    }
    try {
      Start-ASAServer -WorkingDir $WorkingDir -Map $Map -SessionName $SessionName -MaxPlayers $MaxPlayers `
        -GamePort $GamePort -QueryPort $QueryPort -RCONPort $RCONPort -ServerPassword $ServerPassword -ServerAdminPassword $ServerAdminPassword
    } catch { Write-Error $_; exit 1 }
    break
  }

  'update' {
    if ($BootstrapIfMissing) {
      try { Bootstrap-IfNeeded -WorkingDir $WorkingDir -NoFirewall:$NoFirewall -Branch $Branch -BetaPassword $BetaPassword }
      catch { Write-Error $_; exit 1 }
    }
    try {
      $baseDir = Get-RootFromWorkingDir -WorkingDir $WorkingDir
      $steam   = Ensure-SteamCMD -BaseDir $baseDir
      & $steam "+force_install_dir `"$baseDir`" +login anonymous +app_update 2430930 validate +quit"
    } catch { Write-Error $_; exit 1 }
    break
  }

  'prefetch' {
    if ($BootstrapIfMissing) {
      try { Bootstrap-IfNeeded -WorkingDir $WorkingDir -NoFirewall:$NoFirewall -Branch $Branch -BetaPassword $BetaPassword }
      catch { Write-Error $_; exit 1 }
    }
    # Hook for future: download mods, etc.
    Write-Host "Prefetch complete."
    break
  }

  default {
    Write-Error "Unknown command '$Command'. Use: setup | start | update | prefetch"
    exit 1
  }
}
