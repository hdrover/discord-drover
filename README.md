# Discord Drover (Tor Edition)

Discord Drover forces Discord on Windows to route its traffic through Tor (SOCKS5 local proxy), bypassing network blocks on chat, updates, and voice channels without requiring a system-wide VPN.

## Features & How They Work

- **Automated Tor Setup (`drover-tor\`)**:
  - *What it does*: The installer bundles `tor.exe` and copies it directly into your Discord version directory (`app-x.x.x\drover-tor\`).
  - *Why it matters*: You don't need to manually install or configure Tor Browser. Even if you run the installer without extracting the zip properly, Discord keeps its own local Tor instance.

- **Temporary Tor Mode (`temp_tor_mode`)**:
  - *What it does*: Routes all TCP/handshake traffic through Tor only during Discord's initial startup and login phase. After a configurable warmup period (`tor_warmup_seconds`), new connections switch to a direct connection and the Tor background process is automatically shut down.
  - *Why it matters*: Ideal when only Discord's login/API endpoints are blocked in your region, but direct media/gateway streams work once connected. This saves bandwidth, improves latency for gaming/streaming, and frees up system resources.

- **Background Process Management (`autostart_tor`)**:
  - *What it does*: Launches Tor completely hidden (`SW_HIDE`, `CREATE_NO_WINDOW`) when Discord starts and handles clean shutdown when no longer needed.
  - *Why it matters*: No extra command prompt or terminal windows popping up on your desktop while launching Discord.

- **UDP Voice Traffic Manipulation**:
  - *What it does*: Modifies outgoing UDP voice packets at the socket level to bypass Deep Packet Inspection (DPI) blocks on voice channels.
  - *Why it matters*: Resolves "Connecting / No Route / RTC Connecting" voice errors common in regions with strict VoIP restrictions.

- **Process-Level Isolation via `version.dll`**:
  - *What it does*: Injects proxy behavior directly into the Discord process by loading alongside `Discord.exe`.
  - *Why it matters*: No admin services, kernel drivers, or system-wide proxy/VPN changes. Other applications and games on your PC continue using your normal connection untouched.

## Installation

Download the latest build from the [releases page](https://github.com/bonqf/discord-drover-tor/releases/latest).

### Using the Installer (`drover.exe`)

1. Close Discord completely.
2. Run `drover.exe`.
3. Choose your options:
   - **Instalar Tor automaticamente** *(Enabled by default)*: Copies the bundled Tor into Discord's internal folder. Uncheck only if you want to point to an existing Tor installation manually.
   - **Usar Tor apenas na inicialização (modo temporário)**: Enables Temporary Tor Mode. Set the warmup period (default: 20 seconds) for how long Tor should handle traffic before switching to direct mode.
4. Click **Install**.

To remove Drover, run `drover.exe` and click **Uninstall**.

### Configuration (`drover.ini`)

Settings are stored in `drover.ini` inside your active Discord `app-*` folder:

```ini
[drover]
proxy = socks5://127.0.0.1:9050
tor = C:\Users\<User>\AppData\Local\Discord\app-1.0.9177\drover-tor\tor.exe
autostart_tor = true
temp_tor_mode = false
tor_warmup_seconds = 20
```

- **`proxy`**: Local SOCKS5 proxy address (default: `socks5://127.0.0.1:9050`).
- **`tor`**: Path to the `tor.exe` binary.
- **`autostart_tor`**: Starts Tor automatically in the background when Discord opens.
- **`temp_tor_mode`**: When `true`, transitions to a direct connection after the warmup period.
- **`tor_warmup_seconds`**: Duration (in seconds) to stay on Tor before transitioning to direct connection.

## Optional `drover-packet.bin`

If `drover-packet.bin` is placed in the Discord folder, its contents are sent at the start of each outgoing UDP voice connection before normal packet manipulation. This adds an extra layer of packet fragmentation/padding for networks with aggressive DPI filters.
