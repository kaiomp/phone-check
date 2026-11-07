#!/usr/bin/env bash
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
grab device       'getprop | grep -E "ro.product.model|ro.build.version.release|ro.build.version.security_patch|ro.build.fingerprint|ro.boot.verifiedbootstate|ro.boot.flash.locked|ro.debuggable"; echo; uptime; echo; which su'

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
grab certs_user   'ls -la /data/misc/user/0/cacerts-added 2>&1'

# who used camera, mic, location, photos and when
grab appops       dumpsys appops
grab packages     dumpsys package

# speed: CPU, memory, storage, battery, heat
grab top          top -b -n 1 -m 40
grab cpuinfo      dumpsys cpuinfo
grab meminfo      dumpsys meminfo
grab storage      'df -h /data; echo; dumpsys diskstats'
grab battery      'dumpsys battery; echo; dumpsys batterystats --charged | head -400'
grab thermal      dumpsys thermalservice

echo "Done: $out"
