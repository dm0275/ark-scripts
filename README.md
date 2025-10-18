# ARK: Survival Ascended Server Manager (PowerShell)

A lightweight PowerShell utility to manage your **ARK: Survival Ascended dedicated server** on Windows.
Supports server startup, automatic restarts, SteamCMD updates, mod loading, and basic firewall configuration.

---

## 🚀 Features

* **Start or update** your server with a single script
* **Automatic server restarts** on crash or exit
* **Automatic firewall rule creation** for game, query, and RCON ports
* **BattlEye disabled by default** (can be toggled)
* **Mod support** using the `-mods` argument (auto-download/update on startup)
* **SteamCMD integration** for game updates (App ID `2430930`)

---

## 📂 File Setup

Place this script somewhere accessible (can be inside or outside your server folder).

Your server folder structure should look like:

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
* PowerShell 5.1 or later
* Ports forwarded on your router/firewall (default: `7777 UDP`, `27015 UDP`, `27020 TCP`)

---

## 🧠 Commands

### 🟢 Start the server

```powershell
.\server.ps1 start
```

Starts your ASA server with the configured defaults.
It will automatically restart if the process exits unless you use `-NoAutoRestart`.

#### Optional flags:

| Flag                       | Description                                       | Default              |
| -------------------------- | ------------------------------------------------- | -------------------- |
| `-Map <map>`               | Map to load (e.g., `TheIsland_WP`)                | `TheIsland_WP`       |
| `-SessionName <name>`      | Server name visible in-game                       | `My ASA Server`      |
| `-MaxPlayers <num>`        | Max connected players                             | `16`                 |
| `-GamePort <port>`         | Game port (UDP)                                   | `7777`               |
| `-QueryPort <port>`        | Steam query port (UDP)                            | `27015`              |
| `-RCONPort <port>`         | RCON port (TCP)                                   | `27020`              |
| `-Mods <id1,id2,...>`      | Comma-separated mod IDs (ASA auto-downloads them) | none                 |
| `-NoBattlEye`              | Disables BattlEye                                 | ✅ Enabled by default |
| `-NoBattlEye:$false`       | Enables BattlEye                                  |                      |
| `-NoFirewall`              | Skip creating inbound firewall rules              |                      |
| `-NoAutoRestart`           | Prevent auto-restart if server exits              |                      |
| `-RestartDelaySeconds <n>` | Delay before restart                              | `5`                  |
| `-ExtraArgs <args>`        | Extra launch parameters                           | `"-server","-log"`   |

**Examples**

```powershell
# Start with default settings
.\server.ps1 start

# Start with mods
.\server.ps1 start -Mods 123456,987654

# Start without auto-restart
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

#### Optional flags:

| Flag            | Description                            | Default                    |
| --------------- | -------------------------------------- | -------------------------- |
| `-SteamCmdPath` | Path to your `steamcmd.exe`            | `C:\steamcmd\steamcmd.exe` |
| `-InstallDir`   | Installation folder                    | `E:\arkascendedserver`     |
| `-SteamLogin`   | Steam login (anonymous or credentials) | `anonymous`                |
| `-Validate`     | Verify all files                       | off                        |

**Examples**

```powershell
# Basic update
.\server.ps1 update

# Update and validate
.\server.ps1 update -Validate

# Update using a custom SteamCMD path
.\server.ps1 update -SteamCmdPath "D:\Tools\steamcmd\steamcmd.exe"
```

---

## 🧩 Mods

Mods are specified via the `-Mods` argument.
ASA will **auto-download and update** these mods on startup.
They are passed to the server using the `-mods=<id1,id2,...>` flag.

Example:

```powershell
.\server.ps1 start -Mods 123456,987654
```

You can also hardcode your mods in the script:

```powershell
[string[]]$Mods = @("123456", "987654")
```

---

## 🔒 Firewall Configuration

On first run, PowerShell may prompt for admin rights to open ports.

Automatically adds inbound rules for:

* UDP: `GamePort`, `QueryPort`
* TCP: `RCONPort`

If you want to handle ports manually, use `-NoFirewall` to skip this step.

---

## ⚡ Optional Prefetch (Mods Warm-up)

You can create a helper to prefetch mods before hosting (useful before play sessions).
Example:

```powershell
.\server.ps1 start -Mods 123,456 -NoAutoRestart
# Wait for mods to download, then Ctrl+C to stop
```

---

## 🧩 Common Paths

| File        | Location                                                                           |
| ----------- | ---------------------------------------------------------------------------------- |
| Server EXE  | `E:\arkascendedserver\ShooterGame\Binaries\Win64\ArkAscendedServer.exe`            |
| Game config | `E:\arkascendedserver\ShooterGame\Saved\Config\WindowsServer\GameUserSettings.ini` |
| Saved data  | `E:\arkascendedserver\ShooterGame\Saved\SavedArks`                                 |

---

## 🧱 Example Automation

To update and start automatically:

```powershell
.\server.ps1 update -Validate
.\server.ps1 start -SessionName "Weekly Server" -Mods 111222,333444 -NoFirewall
```
