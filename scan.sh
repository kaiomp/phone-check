#!/usr/bin/env bash
# shellcheck disable=SC2016  # $(...) in single quotes must expand on the phone, not the Mac
# Read-only snapshot of an Android phone over adb. Changes nothing on the phone.
# Output: reports/<timestamp>/ (personal data, git-ignored).
set -euo pipefail

ADB="$(command -v adb || echo "${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb")"
[ -x "$ADB" ] || { echo "adb not found. Install Android platform-tools." >&2; exit 1; }

state="$("$ADB" get-state 2>/dev/null || true)"
if [ "$state" != "device" ]; then
  echo "No phone ready. Turn on USB debugging, plug in, tap Allow on the phone." >&2
  "$ADB" devices >&2
  exit 1
fi

out="reports/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
run() { "$ADB" shell "$@" 2>&1 || true; }
grab() { local name="$1"; shift; echo "  $name"; run "$@" > "$out/$name.txt"; }

echo "Saving to $out"

# device and integrity
grab device       'echo "scan_date=$(date +%F)"; getprop | grep -E "ro.product.model|ro.build.version.release|ro.build.version.security_patch|ro.build.fingerprint|ro.boot.verifiedbootstate|ro.boot.flash.locked|ro.debuggable"; echo; uptime; echo; which su'

# apps: user-installed with source APK path and installer, plus everything
grab apps_user    pm list packages -3 -f -i -U
grab apps_all     pm list packages -f -i -u
grab apps_disabled pm list packages -d

# powerful access spyware relies on
grab accessibility settings get secure enabled_accessibility_services
grab notif_listeners settings get secure enabled_notification_listeners
grab keyboards    'settings get secure default_input_method; ime list -s'
grab device_admin dumpsys device_policy
grab accounts     dumpsys account

# network routing: VPN, proxy, private DNS
grab network      'echo "http_proxy=$(settings get global http_proxy)"; echo "private_dns_mode=$(settings get global private_dns_mode)"; echo "private_dns_specifier=$(settings get global private_dns_specifier)"; echo; dumpsys connectivity | grep -iE "VPN|NetworkAgentInfo" | head -50'

# who used camera, mic, location, photos and when; which apps sit unused
grab appops       dumpsys appops
grab packages     dumpsys package
grab usage        dumpsys usagestats

# speed: CPU, memory, storage, battery, heat
grab top          top -b -n 1 -m 40
grab cpuinfo      dumpsys cpuinfo
grab meminfo      dumpsys meminfo
grab storage      'df -h /data; echo; dumpsys diskstats'
grab battery      'dumpsys battery; echo "cycle_count: $(cat /sys/class/power_supply/battery/cycle_count 2>/dev/null)"; echo; dumpsys batterystats --charged | head -400'
grab thermal      dumpsys thermalservice

# files over 100 KB on shared storage, then a hash of every file that shares its size with another
echo "  files (can take a minute)"
run 'find /sdcard/ -type f -size +100k -not -path "*/.*" -print0 2>/dev/null | xargs -0 stat -c "%s|%n"' > "$out/files.txt"
echo "  duplicates"
awk -F'|' '{n[$1]++; l[NR]=$0} END{for (i=1;i<=NR;i++) {s=l[i]; sub(/\|.*/,"",s); if (n[s]>1) print substr(l[i], length(s)+2)}}' "$out/files.txt" |
  tr '\n' '\0' | "$ADB" shell 'xargs -0 md5sum' > "$out/hashes.txt" 2>/dev/null || true

"$(dirname "$0")/analyze.sh" "$out"
cat "$out/summary.txt"
echo
echo "Full report: $out/report.html"
open "$out/report.html" 2>/dev/null || xdg-open "$out/report.html" 2>/dev/null || true
