#!/usr/bin/env bash
#
# wifi-regdom-fix.sh
#
# Some Wi-Fi cards (notably Intel AX200/AX210/AX211) boot into the "world"
# regulatory domain (country 00), which disables HT/VHT/HE rates and caps
# the link at legacy 802.11a/g speeds (~54 Mbit/s). They associate at that
# capped rate immediately on boot. Only later, after receiving enough beacons
# from the AP, does the firmware adopt the real country code advertised by
# the gateway's country IE (can take 30-90s) — but the existing association
# never renegotiates, so the link stays stuck at legacy rates until the next
# reconnect.
#
# This script waits for the firmware to leave country 00, then (only if the
# link actually looks stuck at legacy rates) forces one reconnect so it comes
# up at full speed. It is idempotent per boot via a lock file in /run.
#
# Usage:
#   wifi-regdom-fix.sh [interface]
#
# With no argument, the first wireless interface reported by `iw dev` is
# used. Can be run standalone (e.g. from a systemd service, cron @reboot, or
# rc.local), or wired up as a NetworkManager dispatcher script, which invokes
# it as:
#   wifi-regdom-fix.sh <interface> <action>
# (only the "up" action is acted on; everything else is a no-op).
#
# Requires: iw, awk, grep, coreutils. Uses nmcli to reconnect if present,
# otherwise falls back to `ip link` down/up (which will drop and re-obtain
# a DHCP lease on most setups).
#
# Env vars:
#   WIFI_REGDOM_TIMEOUT   seconds to wait for the country to change (default 90)

set -euo pipefail

IFACE="${1:-}"
ACTION="${2:-}"

# NetworkManager dispatcher scripts are invoked for every interface and
# action; only act on this interface coming up.
if [ -n "$ACTION" ] && [ "$ACTION" != "up" ]; then
    exit 0
fi

if [ -z "$IFACE" ]; then
    IFACE=$(iw dev 2>/dev/null | awk '$1 == "Interface" { print $2; exit }')
fi

if [ -z "$IFACE" ]; then
    echo "wifi-regdom-fix: no wireless interface found" >&2
    exit 0
fi

LOCK="/run/wifi-regdom-fixed-${IFACE}"
if [ -e "$LOCK" ]; then
    exit 0
fi

PHY=$(iw dev "$IFACE" info 2>/dev/null | awk '/wiphy/ { print $2; exit }')
if [ -z "$PHY" ]; then
    exit 0
fi

TIMEOUT="${WIFI_REGDOM_TIMEOUT:-90}"

for _ in $(seq 1 "$TIMEOUT"); do
    country=$(iw reg get 2>/dev/null | awk -v phy="phy#${PHY}" '
        $0 ~ "^" phy { in_phy = 1; next }
        in_phy && /^phy#/ { exit }
        in_phy && /^[[:space:]]*country/ { print $2; exit }
    ')
    country="${country%:}"

    if [ -n "$country" ] && [ "$country" != "00" ]; then
        break
    fi
    sleep 1
done

# Only one attempt per boot, whether or not the country ever changed.
touch "$LOCK" 2>/dev/null || true

# "no HT" in `iw ... info` means the link negotiated without HT/VHT/HE
# support — the symptom of having associated under the world domain.
if iw dev "$IFACE" info 2>/dev/null | grep -q "no HT"; then
    if command -v nmcli >/dev/null 2>&1; then
        nmcli device disconnect "$IFACE"
        sleep 3
        nmcli device connect "$IFACE"
    else
        ip link set "$IFACE" down
        sleep 3
        ip link set "$IFACE" up
    fi
fi
