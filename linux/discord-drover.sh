#!/usr/bin/env bash
# discord-drover.sh
# Launches Discord with drover.so injected via LD_PRELOAD.
#
# Supports:
#   - Native RPM / deb install  (/usr/bin/discord or /opt/discord/Discord)
#   - Direct-download tar.gz    (/opt/Discord/Discord)
#   - Canary / PTB variants
#
# Flatpak is NOT supported (it runs in a sandbox that blocks LD_PRELOAD).
# If you use Flatpak Discord, switch to the native RPM package:
#   sudo dnf install discord        # after enabling the RPM Fusion repo, or
#   sudo dnf install discord        # via Terra / COPR, or grab the RPM from
#                                    # https://discord.com/download

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SO="$SCRIPT_DIR/drover.so"

if [[ ! -f "$SO" ]]; then
    echo "drover.so not found. Run ./build.sh first."
    exit 1
fi

# ---- locate Discord executable ----
DISCORD_BIN=""

CANDIDATES=(
    "/usr/bin/discord"
    "/usr/bin/Discord"
    "/usr/bin/discord-canary"
    "/usr/bin/discord-ptb"
    "/opt/discord/Discord"
    "/opt/Discord/Discord"
    "/opt/discord-canary/DiscordCanary"
    "$HOME/.local/share/discord/Discord"
    "$HOME/Discord/Discord"
)

# also accept a path passed as first argument
if [[ -n "$1" && -x "$1" ]]; then
    DISCORD_BIN="$1"
fi

if [[ -z "$DISCORD_BIN" ]]; then
    for c in "${CANDIDATES[@]}"; do
        if [[ -x "$c" ]]; then
            DISCORD_BIN="$c"
            break
        fi
    done
fi

# fall back to whatever 'discord' resolves to in PATH
if [[ -z "$DISCORD_BIN" ]]; then
    DISCORD_BIN="$(command -v discord 2>/dev/null || true)"
fi

if [[ -z "$DISCORD_BIN" ]]; then
    echo "Could not find the Discord executable."
    echo "Usage: $0 [/path/to/Discord]"
    exit 1
fi

echo "Using Discord: $DISCORD_BIN"
echo "Injecting:     $SO"

exec env LD_PRELOAD="$SO${LD_PRELOAD:+:$LD_PRELOAD}" "$DISCORD_BIN" "$@"
