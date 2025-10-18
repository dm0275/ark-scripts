<# 
.SYNOPSIS
  ARK: Survival Ascended server helper.

.USAGE
  .\server.ps1 start [flags...]
  .\server.ps1 update [flags...]

.EXAMPLES
  # Start with defaults (BattlEye OFF by default)
  .\server.ps1 start

  # Start with mods and a custom name
  .\server.ps1 start -SessionName "Friends Night" -Mods 123456,987654

  # Temporarily enable BattlEye (overrides default)
  .\server.ps1 start -NoBattlEye:$false

  # Update the server app via SteamCMD (anonymous) and validate files
  .\server.ps1 update -Validate
#>

[CmdletBinding(DefaultParameterSetName="Start")]
param(
  # --- Top-level command ------------------------------------------------------
  [Parameter(Mandatory=$true, Position=0)]
  [ValidateSet("start","update")]
  [string]$Command,

  # --- Shared -----------------------------------------------------------------
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

  # BattlEye disabled by default; override with -NoBattlEye:$false when starting
  [Parameter(ParameterSetName="Start")]
  [switch]$NoBattlEye = $true,

  [Parameter(ParameterSetName="Start")]
  [switch]$NoFirewall,          # skip firewall rule creation

  [Parameter(ParameterSetName="Start")]
  [switch]$NoAutoRestart,       # do not auto-restart the process

  [Parameter(ParameterSetName="Start")]
  [int]$RestartDelaySeconds = 5,

  # ASA mods via -mods= (comma-separated IDs)
  #   Example: -Mods 123456,987654,111222
  [Parameter(ParameterSetName="Start")]
  [string[]]$Mods = @(),

  # Extra raw flags passed after the URL block
  [Parameter(ParameterSetName="Start")]
  [string[]]$ExtraArgs = @("-server","-log"),

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

    # ---------------- Build URL-style block ----------------------------------
    # Order: Map -> ?key=value ... -> listen
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

    # ---------------- Build final argument list ------------------------------
    $args = @($url -join "")

    # ASA mods: -mods=ID1,ID2,... (server auto-downloads/updates on boot)
    if ($Mods.Count -gt 0) {
      $modList = ($Mods -join ",")
      $args += "-mods=$modList"
      Write-Host "Using ASA mods: $modList"
    }

    if ($NoBattlEye) { $args += "-NoBattlEye" }
    $args += $ExtraArgs

    # ---------------- Optional firewall rules --------------------------------
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

    # ---------------- Launch loop (optional auto-restart) --------------------
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

    $appId = 2430930  # ASA Dedicated Server
    $validateToken = if ($Validate) { " validate" } else { "" }
    $cmd = "+force_install_dir `"$InstallDir`" +login $SteamLogin +app_update $appId$validateToken +quit"

    Write-Header "Updating ASA Dedicated Server (Steam AppID $appId)"
    Write-Host "SteamCMD: $SteamCmdPath"
    Write-Host "InstallDir: $InstallDir"
    if ($Validate) { Write-Host "Validate: true" }

    & $SteamCmdPath $cmd

    if ($LASTEXITCODE -ne 0) {
      throw "SteamCMD returned exit code $LASTEXITCODE"
    } else {
      Write-Host "`nUpdate completed."
    }
  }
}

