# Discord Drover — Linux

Linux port of [Discord Drover](../README.md) using `LD_PRELOAD` to inject the UDP trick that bypasses voice chat restrictions (e.g. UAE) without any proxy.

This is the equivalent of **Direct mode** from the Windows installer — no proxy is set up, only the UDP manipulation is applied.

## How it works

When Discord's WebRTC stack sends its first 74-byte UDP packet to a voice server, the library intercepts it and injects two tiny probe packets (`0x00` and `0x01`) to the same destination first, then waits 50 ms before letting the real packet through. This is the same technique used by the Windows version.

## Requirements

- Linux (tested on Fedora)
- `gcc`
- A native Discord install (**.tar.gz** or **RPM**) — Flatpak is **not** supported because its sandbox blocks `LD_PRELOAD`

## Installation

### 1. Install Discord

Go to [discord.com/download](https://discord.com/download) and download either the `.rpm` (if available for your distro) or the `.tar.gz`.

**RPM (Fedora/RHEL):**
```bash
sudo dnf install ./discord-*.rpm
```

**tar.gz (any distro):**
```bash
tar -xzf discord-*.tar.gz -C ~/Downloads/
# creates ~/Downloads/Discord/
```

### 2. Build the library

```bash
cd linux/
chmod +x build.sh discord-drover.sh
./build.sh
```

This produces `drover.so` in the same folder.

### 3. Launch Discord with Drover

**If you used the RPM install:**
```bash
./discord-drover.sh
# Discord is found automatically at /usr/bin/discord
```

**If you used the tar.gz:**
```bash
./discord-drover.sh ~/Downloads/Discord/Discord
```

## Auto-start on login

To have Discord launch automatically with Drover on every login:

```bash
mkdir -p ~/.config/autostart

cat > ~/.config/autostart/discord-drover.desktop << EOF
[Desktop Entry]
Type=Application
Name=Discord (Drover)
Exec=/full/path/to/linux/discord-drover.sh /full/path/to/Discord/Discord
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
```

Replace the paths with the actual locations on your system.

## Notes

- **Flatpak** — not supported. Switch to the native RPM or tar.gz install.
- **Discord Canary / PTB** — pass the path to the binary explicitly:
  ```bash
  ./discord-drover.sh /path/to/DiscordCanary
  ```
- The library hooks `sendto` and `sendmsg` so it works regardless of which syscall Electron/Chromium uses internally.
