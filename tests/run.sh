#!/usr/bin/env bash
# Runs analyze.sh on fake phone data and checks that each red flag shows up.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp "$root"/tests/fixture/*.txt "$work/"
"$root/analyze.sh" "$work"
s="$work/summary.txt"
fail=0
expect() { grep -qF -- "$1" "$s" || { echo "MISSING: $1"; fail=1; }; }
expect "phone-check: Test Phone, Android 15, scanned 2026-01-01"
expect "# OK Phone system is not tampered with"
expect "# FIX Security updates are behind"
expect "- An update is waiting."
expect "# CHECK 1 installed apps have strong access"
expect "- com.example.tracker: accessibility, device-admin (APK file)"
expect "# CHECK 1 apps are not from the Play Store"
expect "- com.example.tracker (APK file, installed 2025-12-01)"
expect "# CHECK Internet traffic is redirected"
expect "- Proxy: 10.0.0.5:8080"
expect "# CHECK An app from outside the Play Store used"
expect "- com.example.tracker: microphone (APK file)"
expect "- someone@example.com (com.google)"
expect "# FIX Storage is almost full (5% free)"
expect "Exact duplicate files: 1, using 5 MB."
expect "- com.example.notes: 70 MB, last opened 2020-01-01"
expect "# CHECK Memory is full"
expect "Health: worn out. Charge cycles: 900."
expect "# OK Phone is not hot"
grep -q "camera" <(grep "com.example.tracker:" "$s" | grep microphone) && { echo "camera use older than 30 days was counted"; fail=1; }
grep -q '<section class="FIX">' "$work/report.html" || { echo "report.html has no FIX section"; fail=1; }

# Missing data must never look like good news.
rm "$work"/{apps_user,network,storage,meminfo,battery,thermal,usage}.txt
echo "error: no devices/emulators found" > "$work/appops.txt"
"$root/analyze.sh" "$work"
for t in "Apps with strong access" "Apps from outside the Play Store" "Internet traffic" \
         "Camera, mic, photos and location use" "Storage" "Memory" "Battery" "Heat"; do
  grep -qF "# INFO $t: unknown" "$s" || { echo "no 'unknown' for: $t"; fail=1; }
done
grep -E '^# OK' "$s" | grep -v "Phone system is not tampered with" && { echo "OK shown without data"; fail=1; }

# Phone text with HTML in it stays text.
printf '[ro.product.model]: [<script>x</script> & Co]\n' > "$work/device.txt"
"$root/analyze.sh" "$work"
grep -q '<script>' "$work/report.html" && { echo "HTML not escaped"; fail=1; }

# A folder that is not a scan is refused.
"$root/analyze.sh" "$root/tests" 2>/dev/null && { echo "non-scan folder accepted"; fail=1; }

[ $fail = 0 ] && echo "tests passed"
exit $fail
