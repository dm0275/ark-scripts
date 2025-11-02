<# 
.SYNOPSIS
  ARK: Survival Ascended Server Manager

.USAGE
  .\server.ps1 start [flags...]
  .\server.ps1 update [flags...]
  .\server.ps1 prefetch [flags...]

.NOTES
  - Default path: E:\arkascendedserver\ShooterGame\Binaries\Win64
  - Steam App ID: 2430930
  - Mods auto-download/update when using -mods=<ids>
#>

[CmdletBinding(DefaultParameterSetName="Start")]
param(
  # --- Top-level command ------------------------------------------------------
  [Parameter(Mandatory=$true, Position=0)]
  [ValidateSet("setup", "start","update","prefetch")]
  [string]$Command,

  # --- Shared -----------------------------------------------------------------
  [string]$WorkingDir = "E:\arkascendedserver\ShooterGame\Binaries\Win64",
  [switch]$BootstrapIfMissing,

  # --- START / PREFETCH PARAMS ------------------------------------------------
  [Parameter(ParameterSetName="Start")]
  [Parameter(ParameterSetName="Prefetch")]
  [string]$Map = "TheIsland_WP",

  [Parameter(ParameterSetName="Start")]
  [Parameter(ParameterSetName="Prefetch")]
  [string]$SessionName = "My ASA Server",

  [Parameter(ParameterSetName="Start")]
  [Parameter(ParameterSetName="Prefetch")]
  [int]$MaxPlayers = 16,

  [Parameter(ParameterSetName="Start")]
  [Parameter(ParameterSetName="Prefetch")]
  [int]$GamePort = 7777,

  [Parameter(ParameterSetName="Start")]
  [Parameter(ParameterSetName="Prefetch")]
  [int]$QueryPort = 27015,

  [Parameter(ParameterSetName="Start")]
  [Parameter(ParameterSetName="Prefetch")]
  [Nullable[int]]$RCONPort = 27020,

  [Parameter(ParameterSetName="Start")]
  [Parameter(ParameterSetName="Prefetch")]
  [string]$ServerPassword = "",

  [Parameter(ParameterSetName="Start")]
  [Parameter(ParameterSetName="Prefetch")]
  [string]$ServerAdminPassword = "ChangeMeAdmin!",

  # BattlEye disabled by default
  [Parameter(ParameterSetName="Start")]
  [Parameter(ParameterSetName="Prefetch")]
  [switch]$NoBattlEye = $true,

  [Parameter(ParameterSetName="Start")]
  [switch]$NoFirewall,

  [Parameter(ParameterSetName="Start")]
  [switch]$NoAutoRestart,

  [Parameter(ParameterSetName="Start")]
  [int]$RestartDelaySeconds = 5,

  # ASA mods via -mods=
  [Parameter(ParameterSetName="Start")]
  [Parameter(ParameterSetName="Prefetch")]
  [string[]]$Mods = @("929578", "953154", "934231"),

  [Parameter(ParameterSetName="Start")]
  [string[]]$ExtraArgs = @("-server","-log"),

  # --- PREFETCH PARAMS --------------------------------------------------------
  [Parameter(ParameterSetName="Prefetch")]
  [int]$TimeoutMinutes = 20,

  # --- UPDATE PARAMS ----------------------------------------------------------
  [Parameter(ParameterSetName="Update")]
  [string]$SteamCmdPath = "C:\steamcmd\steamcmd.exe",

  [Parameter(ParameterSetName="Update")]
  [string]$InstallDir = "E:\arkascendedserver",

  [Parameter(ParameterSetName="Update")]
  [switch]$Validate,

  [Parameter(ParameterSetName="Update")]
  [string]$SteamLogin = "anonymous"
)

# =====================[ Bootstrap Helpers ]=====================

function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    throw "This action requires an elevated PowerShell (Run as Administrator)."
  }
}

function Get-RootFromWorkingDir {
  param([Parameter(Mandatory)][string]$WorkingDir)
  try {
    $wd = Resolve-Path $WorkingDir
  } catch { $wd = $WorkingDir }
  # Expect ...\ShooterGame\Binaries\Win64 -> root is 3 levels up
  $root = Join-Path $wd "..\..\.."
  $root = Resolve-Path $root -ErrorAction SilentlyContinue
  if (-not $root) {
    # Fallback: parent of the working dir
    $root = Split-Path -Path $WorkingDir -Parent
  }
  return $root
}

function Ensure-Folder {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Test-Command {
  param([Parameter(Mandatory)][string]$Name)
  $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-VCppRedist {
  Write-Host "Checking Microsoft Visual C++ 2015-2022 x64 Redistributable..."
  # Try winget first
  if (Test-Command -Name 'winget') {
    $pkg = winget list --id Microsoft.VCRedist.2015+.x64 --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $pkg -match 'Microsoft Visual C\+\+.*2015.*2022.*x64') {
      Write-Host "VC++ Redist already installed."
      return
    }
    Write-Host "Installing VC++ Redist via winget..."
    winget install --id Microsoft.VCRedist.2015+.x64 --silent --accept-source-agreements --accept-package-agreements
    return
  }

  # Fallback: direct download
  $temp = Join-Path $env:TEMP "vc_redist_x64.exe"
  $url  = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
  Write-Host "Downloading VC++ Redist from Microsoft..."
  Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing
  Write-Host "Installing VC++ Redist (silent)..."
  Start-Process -FilePath $temp -ArgumentList "/install","/passive","/norestart" -Wait
}

function Ensure-SteamCMD {
  param([Parameter(Mandatory)][string]$BaseDir)

  $steamCmdDir = Join-Path $BaseDir "steamcmd"
  $steamCmdExe = Join-Path $steamCmdDir "steamcmd.exe"

  if (Test-Path $steamCmdExe) {
    Write-Host "SteamCMD already present at $steamCmdExe"
    return $steamCmdExe
  }

  Assert-Admin
  Ensure-Folder $steamCmdDir
  $zipPath = Join-Path $steamCmdDir "steamcmd.zip"
  $url     = "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip"

  Write-Host "Downloading SteamCMD..."
  Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

  Write-Host "Extracting SteamCMD..."
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $steamCmdDir)

  Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
  Write-Host "SteamCMD installed to $steamCmdExe"
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
  $installDir = $BaseDir  # Use root as the app install base (matches your default layout)

  Ensure-Folder $installDir

  $login = "+login anonymous"
  $branchArgs = ""
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

  Write-Host "Syncing ASA server files to $installDir (this can take a while on first run)..."
  & $SteamCmdExe $args
  if ($LASTEXITCODE -ne 0) {
    throw "SteamCMD failed to install/update ASA server (exit $LASTEXITCODE)."
  }
  Write-Host "ASA server files are present."
}

function Ensure-FirewallRules {
  param(
    [switch]$SkipFirewall
  )
  if ($SkipFirewall) {
    Write-Host "Skipping firewall configuration per -NoFirewall."
    return
  }

  Assert-Admin

  # Typical ASA ports (adjust to your script’s actual ports if different)
  $rules = @(
    @{ Name="ASA_UDP_7777";  Protocol="UDP"; LocalPort=7777;  Dir="Inbound";  Action="Allow" },
    @{ Name="ASA_UDP_7778";  Protocol="UDP"; LocalPort=7778;  Dir="Inbound";  Action="Allow" },
    @{ Name="ASA_UDP_27015"; Protocol="UDP"; LocalPort=27015; Dir="Inbound";  Action="Allow" },
    @{ Name="ASA_TCP_27020"; Protocol="TCP"; LocalPort=27020; Dir="Inbound";  Action="Allow" }
  )

  foreach ($r in $rules) {
    $existing = Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
      New-NetFirewallRule -DisplayName $r.Name -Direction $r.Dir -Action $r.Action -Protocol $r.Protocol -LocalPort $r.LocalPort | Out-Null
      Write-Host "Added firewall rule $($r.Name)"
    } else {
      Write-Host "Firewall rule $($r.Name) already exists."
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

  # Determine root dir from WorkingDir
  $baseDir = Get-RootFromWorkingDir -WorkingDir $WorkingDir
  Write-Host "Base directory resolved to: $baseDir"

  # 1) VC++ runtime
  Install-VCppRedist

  # 2) SteamCMD
  $steamCmd = Ensure-SteamCMD -BaseDir $baseDir

  # 3) ASA server files
  Ensure-ASAServerFiles -BaseDir $baseDir -SteamCmdExe $steamCmd -Branch $Branch -BetaPassword $BetaPassword

  # 4) Firewall
  Ensure-FirewallRules -SkipFirewall:$NoFirewall
  Write-Host "Bootstrap complete."
}
# ===================[ End Bootstrap Helpers ]===================



# Utility helpers
function Write-Header($Text) { Write-Host "`n=== $Text ===" -ForegroundColor Cyan }

function Ensure-FirewallRule {
  param([string]$Name,[string]$Protocol,[int]$Port)
  $existing = Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue
  if (-not $existing) {
    New-NetFirewallRule -DisplayName $Name -Direction Inbound -Action Allow `
      -Protocol $Protocol -LocalPort $Port | Out-Null
    Write-Host "Created firewall rule: $Name ($Protocol $Port)"
  }
}

function Build-ServerArgs {
  param($Map,$SessionName,$GamePort,$QueryPort,$MaxPlayers,$ServerPassword,$ServerAdminPassword,$RCONPort,$Mods,$NoBattlEye,$ExtraArgs)

  # Build URL-style part; ensure a SPACE before 'listen' so it doesn't glue to the last token
  $urlParts = @()
  $urlParts += "$Map"
  $urlParts += "?SessionName=$([uri]::EscapeDataString($SessionName))"
  $urlParts += "?Port=$GamePort"
  $urlParts += "?QueryPort=$QueryPort"
  $urlParts += "?MaxPlayers=$MaxPlayers"
  if ($ServerPassword)      { $urlParts += "?ServerPassword=$ServerPassword" }
  if ($ServerAdminPassword) { $urlParts += "?ServerAdminPassword=$ServerAdminPassword" }
  if ($null -ne $RCONPort)  { $urlParts += "?RCONPort=$RCONPort" }

  # <- key fix: add a leading space before 'listen'
  $args = @(($urlParts -join "") + " listen")

  if ($Mods.Count -gt 0) {
    $modList = ($Mods -join ",")
    $args += "-mods=$modList"
    Write-Host "Using ASA mods: $modList"
  }
  if ($NoBattlEye) { $args += "-NoBattlEye" }
  $args += $ExtraArgs
  return ,$args
}

switch ($Command) {
  'setup' {
    try {
      Bootstrap-IfNeeded -WorkingDir $WorkingDir -NoFirewall:$NoFirewall `
        -Branch $Branch -BetaPassword $BetaPassword
    } catch {
      Write-Error $_
      break
    }
    break
  }

  'start' {

  if ($BootstrapIfMissing) {
    try {
      Bootstrap-IfNeeded -WorkingDir $WorkingDir -NoFirewall:$NoFirewall `
        -Branch $Branch -BetaPassword $BetaPassword
    } catch {
      Write-Error $_
      break
    }
  }

    $exe = Join-Path $WorkingDir "ArkAscendedServer.exe"
    if (!(Test-Path $exe)) { throw "ArkAscendedServer.exe not found at: $exe" }

    $args = Build-ServerArgs $Map $SessionName $GamePort $QueryPort $MaxPlayers `
      $ServerPassword $ServerAdminPassword $RCONPort $Mods $NoBattlEye $ExtraArgs

    if (-not $NoFirewall) {
      try {
        Ensure-FirewallRule -Name "ASA GamePort $GamePort (UDP)"  -Protocol UDP -Port $GamePort
        Ensure-FirewallRule -Name "ASA QueryPort $QueryPort (UDP)" -Protocol UDP -Port $QueryPort
        if ($null -ne $RCONPort) {
          Ensure-FirewallRule -Name "ASA RCON $RCONPort (TCP)" -Protocol TCP -Port $RCONPort
        }
      } catch {
        Write-Warning "Couldn't set firewall rules (run PowerShell as Administrator if needed)."
      }
    }

    Write-Header "Launching Ark Ascended Server"
    Write-Host "Path: $exe"
    Write-Host "Args: $($args -join ' ')`n"

    $auto = -not $NoAutoRestart
    do {
      $p = Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $WorkingDir -PassThru
      Wait-Process -Id $p.Id
      Write-Warning "Server exited with code $($p.ExitCode)"
      if ($auto) {
        Write-Host "Restarting in $RestartDelaySeconds seconds..."
        Start-Sleep -Seconds $RestartDelaySeconds
      }
    } while ($auto)
  }

  'update' {

  if ($BootstrapIfMissing) {
    try {
      Bootstrap-IfNeeded -WorkingDir $WorkingDir -NoFirewall:$NoFirewall `
        -Branch $Branch -BetaPassword $BetaPassword
    } catch {
      Write-Error $_
      break
    }
  }

    if (!(Test-Path $SteamCmdPath)) { throw "SteamCMD not found at: $SteamCmdPath" }
    if (!(Test-Path $InstallDir)) {
      Write-Host "Creating InstallDir: $InstallDir"
      New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    }

    $appId = 2430930
    $validateToken = if ($Validate) { " validate" } else { "" }
    $cmd = "+force_install_dir `"$InstallDir`" +login $SteamLogin +app_update $appId$validateToken +quit"

    Write-Header "Updating ASA Dedicated Server (Steam AppID $appId)"
    Write-Host "SteamCMD: $SteamCmdPath"
    Write-Host "InstallDir: $InstallDir"
    if ($Validate) { Write-Host "Validate: true" }

    & $SteamCmdPath $cmd

    if ($LASTEXITCODE -ne 0) { throw "SteamCMD returned exit code $LASTEXITCODE" }
    Write-Host "`nUpdate completed."
  }

  'prefetch' {

  if ($BootstrapIfMissing) {
    try {
      Bootstrap-IfNeeded -WorkingDir $WorkingDir -NoFirewall:$NoFirewall `
        -Branch $Branch -BetaPassword $BetaPassword
    } catch {
      Write-Error $_
      break
    }
  }

    $exe = Join-Path $WorkingDir "ArkAscendedServer.exe"
    if (!(Test-Path $exe)) { throw "ArkAscendedServer.exe not found at: $exe" }

    if ($Mods.Count -eq 0) {
      throw "No mods specified. Use -Mods <id1,id2,...>"
    }

    Write-Header "Prefetching Mods"
    $args = Build-ServerArgs $Map $SessionName $GamePort $QueryPort $MaxPlayers `
      $ServerPassword $ServerAdminPassword $RCONPort $Mods $NoBattlEye @("-server","-NoCrashDialog")

    Write-Host "Starting server to download mods..."
    $proc = Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $WorkingDir -PassThru

    $timeout = (Get-Date).AddMinutes($TimeoutMinutes)
    $logDir = Join-Path $WorkingDir "..\..\Saved\Logs"
    Write-Host "Monitoring logs in: $logDir"

    do {
      Start-Sleep -Seconds 10
      $logFiles = Get-ChildItem -Path $logDir -Filter "*.log" -ErrorAction SilentlyContinue
      $found = $false
      foreach ($log in $logFiles) {
        $content = Get-Content $log.FullName -ErrorAction SilentlyContinue | Select-String "Downloading mod"
        if ($content) { Write-Host "Mod download in progress..." }
        $complete = Get-Content $log.FullName -ErrorAction SilentlyContinue | Select-String "Mod download complete"
        if ($complete) { $found = $true }
      }
    } until ($found -or (Get-Date) -gt $timeout)

    if ($found) {
      Write-Host "Mods downloaded successfully!"
    } else {
      Write-Warning "Timeout reached ($TimeoutMinutes minutes). Mods may still be downloading."
    }

    Write-Host "Stopping server process..."
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
  }
}
