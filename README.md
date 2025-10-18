# ARK: Survival Ascended Server Manager (PowerShell)

A lightweight PowerShell utility to manage your **ARK: Survival Ascended dedicated server** on Windows.
Supports server startup, automatic restarts, SteamCMD updates, mod loading, and basic firewall configuration.

---

## 🚀 Features

* **Start, update, or prefetch** your ASA server
* **Automatic server restarts** on crash or exit
* **Automatic firewall rule creation** for game, query, and RCON ports
* **BattlEye disabled by default** (toggleable)
* **Mod support** via `-mods` (ASA auto-downloads/updates them)
* **SteamCMD integration** (App ID `2430930`)
* **Prefetch mode** to download mods before gameplay sessions

---

## 📂 File Setup

Your server folder should look like:

```
E:\
└── arkascendedserver\
    └── ShooterGame\
        └── Binaries\
            └── Win64\
                └── ArkAscendedServer.exe
```

---

## ⚙️ Requirements

* Windows 10/11 or Windows Server
* [SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD)
* PowerShell 5.1+ or PowerShell 7+
* Ports forwarded and open:

  * **UDP:** 7777 (Game), 27015 (Query)
  * **TCP:** 27020 (RCON)

---

## 🧠 Commands

### 🟢 Start the server

```powershell
.\server.ps1 start
```

Starts your ASA server with the configured defaults.
Automatically restarts on crash or exit (use `-NoAutoRestart` to disable).

#### Optional flags:

| Flag                       | Description                          | Default            |
| -------------------------- | ------------------------------------ | ------------------ |
| `-Map <map>`               | Map to load (e.g., `TheIsland_WP`)   | `TheIsland_WP`     |
| `-SessionName <name>`      | Server name visible in-game          | `My ASA Server`    |
| `-MaxPlayers <num>`        | Max players                          | `16`               |
| `-GamePort <port>`         | Game port (UDP)                      | `7777`             |
| `-QueryPort <port>`        | Steam query port (UDP)               | `27015`            |
| `-RCONPort <port>`         | RCON port (TCP)                      | `27020`            |
| `-Mods <id1,id2,...>`      | Comma-separated mod IDs              | none               |
| `-NoBattlEye`              | Disable BattlEye                     | ✅ Default          |
| `-NoBattlEye:$false`       | Enable BattlEye                      |                    |
| `-NoFirewall`              | Skip creating inbound firewall rules |                    |
| `-NoAutoRestart`           | Don’t restart server automatically   |                    |
| `-RestartDelaySeconds <n>` | Delay before restart                 | `5`                |
| `-ExtraArgs <args>`        | Add extra CLI flags                  | `"-server","-log"` |

#### Examples

```powershell
# Start with default settings
.\server.ps1 start

# Start with mods
.\server.ps1 start -Mods 123456,987654

# Disable auto-restart
.\server.ps1 start -NoAutoRestart

# Temporarily enable BattlEye
.\server.ps1 start -NoBattlEye:$false
```

---

### 🔄 Update the server

```powershell
.\server.ps1 update
```

Uses SteamCMD to install or update the ASA dedicated server.

| Flag            | Description                          | Default                    |
| --------------- | ------------------------------------ | -------------------------- |
| `-SteamCmdPath` | Path to `steamcmd.exe`               | `C:\steamcmd\steamcmd.exe` |
| `-InstallDir`   | Server install folder                | `E:\arkascendedserver`     |
| `-SteamLogin`   | Steam login (anonymous or user/pass) | `anonymous`                |
| `-Validate`     | Verify all files                     | off                        |

**Examples**

```powershell
# Simple update
.\server.ps1 update

# Validate files
.\server.ps1 update -Validate

# Custom SteamCMD path
.\server.ps1 update -SteamCmdPath "D:\Tools\steamcmd\steamcmd.exe"
```

---

### ⚡ Prefetch Mods

```powershell
.\server.ps1 prefetch -Mods 123456,987654
```

**Prefetch mode** starts the server just long enough to trigger mod downloads, then exits automatically once the downloads are complete.

This is useful for:

* Pre-loading mods before hosting sessions
* Updating mods after SteamCMD updates
* Preparing a modded server offline before launch

| Flag              | Description                       | Default |
| ----------------- | --------------------------------- | ------- |
| `-Mods`           | Comma-separated list of mod IDs   | none    |
| `-TimeoutMinutes` | Maximum wait time before aborting | `20`    |

*(This feature runs the server in headless mode and stops it automatically once all mods finish downloading.)*

Example workflow:

```powershell
# Fetch latest mods
.\server.ps1 prefetch -Mods 123456,987654

# Then start the game server normally
.\server.ps1 start -Mods 123456,987654
```

---

## 🧩 Mods

Mods are handled with the `-mods` flag, e.g.:

```powershell
.\server.ps1 start -Mods 123456,987654
```

ASA automatically **downloads and updates** mods at startup.
You don’t need to use `SteamCMD workshop_download_item` manually.

You can also set default mods directly in the script:

```powershell
[string[]]$Mods = @("123456","987654")
```

---

## 🔒 Firewall Rules

On first run, PowerShell may request admin permissions to open inbound ports.
The script automatically creates rules for:

* UDP: `GamePort` and `QueryPort`
* TCP: `RCONPort`

To skip rule creation:

```powershell
.\server.ps1 start -NoFirewall
```

---

## 🧱 Example Automation

To always keep your server fresh:

```powershell
.\server.ps1 update -Validate
.\server.ps1 prefetch -Mods 123456,987654
.\server.ps1 start -SessionName "Weekly Server" -Mods 123456,987654
```
