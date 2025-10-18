<# 
.SYNOPSIS
  ARK: Survival Ascended server helper.

.USAGE
  .\server.ps1 start [flags...]
  .\server.ps1 update [flags...]

.EXAMPLES
  # Start with defaults
  .\server.ps1 start

  # Start with overrides
  .\server.ps1 start -Map TheIsland_WP -SessionName "My ASA" -GamePort 7777 -QueryPort 27015 -RCONPort 27020 -MaxPlayers 20 -ExtraArgs "-NoBattlEye","-log"

  # Start without firewall changes and no auto-restart
  .\server.ps1 start -NoFirewall -NoAutoRestart

  # Update via SteamCMD (anonymous)
  .\server.ps1 update -SteamCmdPath "C:\steamcmd\steamcmd.exe" -InstallDir "E:\arkascendedserver" -Validate

.NOTES
  - Default server path points to your install:
      E:\arkascendedserver\ShooterGame\Binaries\Win64
  - App ID for ASA dedicated server: 2430930
#>

[CmdletBinding(DefaultParameterSetName="Start")]
param(
  # --- Top-level command ------------------------------------------------------
  [Parameter(Mandatory=$true, Position=0)]
  [ValidateSet("start","update")]
  [string]$Command,

  # --- Shared-ish ----------------------------------------------------------------
  [string]$WorkingDir = "E:\arkascendedserver\ShooterGame\Binaries\Win64",

  # --- START PARAMS -----------------------------------------------------------
  [Parameter(ParameterSetName="Start")]
  [string]$Map = "TheIsland_WP",

  [Parameter(ParameterSetName="Start")]
  [string]$SessionName = "My ASA Server",

  [Parameter(ParameterSetName="Start")]
  [int]$MaxPlayers = 16,

  [Parameter(ParameterSetName="Start")]
  [int]$GamePort = 7777,        # UDP

  [Parameter(ParameterSetName="Start")]
  [int]$QueryPort = 27015,      # UDP

  [Parameter(ParameterSetName="Start")]
  [Nullable[int]]$RCONPort = 27020, # TCP; set $null to omit

  [Parameter(ParameterSetName="Start")]
  [string]$ServerPassword = "",

  [Parameter(ParameterSetName="Start")]
  [string]$ServerAdminPassword = "ChangeMeAdmin!",

  [Parameter(ParameterSetName="Start")]
  [switch]$NoBattlEye,          # adds -NoBattlEye if set

  [Parameter(ParameterSetName="Start")]
  [switch]$NoFirewall,          # skip firewall rule creation

  [Parameter(ParameterSetName="Start")]
  [switch]$NoAutoRestart,       # do not auto-restart the process

  [Parameter(ParameterSetName="Start")]
  [int]$RestartDelaySeconds = 5,

  [Parameter(ParameterSetName="Start")]
  [string[]]$ExtraArgs = @("-server","-log"),  # more raw flags to pass after the URL block

  # --- UPDATE PARAMS ----------------------------------------------------------
  [Parameter(ParameterSetName="Update")]
  [string]$SteamCmdPath = "C:\steamcmd\steamcmd.exe",

  [Parameter(ParameterSetName="Update")]
  [string]$InstallDir = "E:\arkascendedserver",

  [Parameter(ParameterSetName="Update")]
  [switch]$Validate,

  [Parameter(ParameterSetName="Update")]
  [string]$SteamLogin = "anonymous" # or "username password" if needed
)

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

switch ($Command) {
  'start' {
    $exe = Join-Path $WorkingDir "ArkAscendedServer.exe"
    if (!(Test-Path $exe)) {
      throw "ArkAscendedServer.exe not found at: $exe"
    }

    # URL-style block: Map then ?key=value pairs then 'listen'
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
    if ($NoBattlEye) { $args += "-NoBattlEye" }
    $args += $ExtraArgs

    if (-not $NoFirewall) {
      try {
        Ensure-FirewallRule -Name "ASA GamePort $GamePort (UDP)"  -Protocol UDP -Port $GamePort
        Ensure-FirewallRule -Name "ASA QueryPort $QueryPort (UDP)" -Protocol UDP -Port $QueryPort
        if ($null -ne $RCONPort) { Ensure-FirewallRule -Name "ASA RCON $RCONPort (TCP)" -Protocol TCP -Port $RCONPort }
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
    if (!(Test-Path $SteamCmdPath)) {
      throw "SteamCMD not found at: $SteamCmdPath"
    }
    if (!(Test-Path $InstallDir)) {
      Write-Host "InstallDir doesn't exist; creating: $InstallDir"
      New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    }

    $appId = 2430930
    $validateToken = if ($Validate) { " validate" } else { "" }

    # Build the SteamCMD arg string
    $loginParts = $SteamLogin
    $cmd = "+force_install_dir `"$InstallDir`" +login $loginParts +app_update $appId$validateToken +quit"

    Write-Header "Updating ASA Dedicated Server via SteamCMD"
    Write-Host "SteamCMD: $SteamCmdPath"
    Write-Host "InstallDir: $InstallDir"
    Write-Host "App ID: $appId"
    if ($Validate) { Write-Host "Validate: true" }

    & $SteamCmdPath $cmd

    if ($LASTEXITCODE -ne 0) {
      throw "SteamCMD returned exit code $LASTEXITCODE"
    } else {
      Write-Host "`nUpdate completed."
    }
  }
}
