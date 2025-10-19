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
  [ValidateSet("start","update","prefetch")]
  [string]$Command,

  # --- Shared -----------------------------------------------------------------
  [string]$WorkingDir = "E:\arkascendedserver\ShooterGame\Binaries\Win64",

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

  $url = @()
  $url += "$Map"
  $url += "?SessionName=$([uri]::EscapeDataString($SessionName))"
  $url += "?Port=$GamePort"
  $url += "?QueryPort=$QueryPort"
  $url += "?MaxPlayers=$MaxPlayers"
  if ($ServerPassword)      { $url += "?ServerPassword=$ServerPassword" }
  if ($ServerAdminPassword) { $url += "?ServerAdminPassword=$ServerAdminPassword" }
  if ($null -ne $RCONPort)  { $url += "?RCONPort=$RCONPort" }
  $url += "listen"

  $args = @($url -join "")
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

  'start' {
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

