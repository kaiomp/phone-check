#!/usr/bin/env bash
# Turns one scan folder into summary.txt (plain text) and report.html.
# Reads only that folder. Never talks to the phone.
set -uo pipefail

dir="${1:?usage: ./analyze.sh reports/<timestamp>}"
here="$(cd "$(dirname "$0")" && pwd)"
cd "$dir" || exit 1
prop() { sed -n "s/^\[$1\]: \[\(.*\)\]$/\1/p" device.txt 2>/dev/null; }
[ -n "$(prop ro.product.model)" ] || { echo "$dir is not a phone-check scan (no device.txt with a phone model)." >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

scan_date="$(sed -n 's/^scan_date=//p' device.txt | grep . || date +%F)"
days_ago() { date -j -v-"$1"d -f %F "$scan_date" +%F 2>/dev/null || date -d "$scan_date -$1 days" +%F; }
# A file counts only if the phone answered: not empty and not an adb error.
have() { [ -s "$1" ] && ! grep -q '^error: ' "$1"; }
unknown() { section INFO "$1: unknown (no data in this scan)"; }
gb() { awk -v b="$1" 'BEGIN{if (b>=1e9) printf "%.1f GB", b/1e9; else printf "%d MB", b/1e6}'; }
# Status words: OK (fine), INFO (look once), CHECK (you decide), FIX (act on it).
section() { printf '\n# %s %s\n' "$1" "$2"; }

# "package installer" for every app the user installed
sed -n 's/^package:.*\.apk=\([^ ]*\)  installer=\([^ ]*\).*/\1 \2/p' apps_user.txt > "$tmp/user" 2>/dev/null
# app -> where it came from (shown next to app names)
origin() {
  awk -v p="$1" '$1==p{f=1; i=$2} END{
    if (!f) print "built-in"
    else if (i=="com.android.vending") print "Play Store"
    else if (i=="com.google.android.packageinstaller") print "APK file"
    else if (i=="com.google.android.apps.nbu.files") print "APK via Files app"
    else if (i=="null") print "installed over USB"
    else print "from " i }' "$tmp/user"
}

integrity() {
  local boot locked dbg su bad=0
  boot="$(prop ro.boot.verifiedbootstate)"; locked="$(prop ro.boot.flash.locked)"
  dbg="$(prop ro.debuggable)"; su="$(grep -c '/su$' device.txt 2>/dev/null)"
  # Only a known-bad value is FIX: some makers leave these properties unset.
  case "$boot" in yellow|orange|red) bad=1 ;; esac
  [ "$locked" = 0 ] && bad=1; [ "$dbg" = 1 ] && bad=1; [ "${su:-0}" -gt 0 ] && bad=1
  if [ $bad = 0 ] && { [ -z "$boot" ] || [ -z "$locked" ]; }; then
    unknown "Phone system check"
    echo "Verified boot: ${boot:-not reported}. Bootloader locked: ${locked:-not reported}. No root (su) found."
  elif [ $bad = 0 ]; then
    section OK "Phone system is not tampered with"
    echo "Verified boot is green, the bootloader is locked, and there is no root (su)."
  else
    section FIX "Phone system is changed"
    echo "Verified boot: ${boot:-?}. Bootloader locked: ${locked:-?}. Debuggable: ${dbg:-?}. Root (su) found: ${su:-0}."
    echo "If you did not unlock or root this phone yourself, back up your data and do a factory reset."
  fi
}

updates() {
  local patch pending
  patch="$(prop ro.build.version.security_patch)"
  pending="$(grep -c 'Pending System Update: SystemUpdateInfo (receivedTime = [1-9]' device_admin.txt 2>/dev/null)"
  if [ -z "$patch" ] && [ "${pending:-0}" = 0 ]; then
    unknown "Security updates"
  elif [[ "$patch" < "$(days_ago 90)" ]] || [ "${pending:-0}" -gt 0 ]; then
    section FIX "Security updates are behind"
  else
    section OK "Security updates are recent"
  fi
  echo "Security patch: ${patch:-unknown}."
  [ "${pending:-0}" -gt 0 ] && echo "- An update is waiting. Install it: Settings → System → Software updates. It can need a few GB of free space."
  return 0
}

strong_access() {
  have apps_user.txt || { unknown "Apps with strong access"; return 0; }
  { tr ':' '\n' < accessibility.txt | sed 's#/.*##; s/^/accessibility /'
    tr ':' '\n' < notif_listeners.txt | sed 's#/.*##; s/^/notifications /'
    sed -n 's#^    \([A-Za-z0-9_.]*\)/.*:$#device-admin \1#p' device_admin.txt
    sed 's#/.*##; s/^/keyboard /' keyboards.txt
  } 2>/dev/null | awk '$2!="" && $2!="null" && index(k[$2], $1)==0 {k[$2]=k[$2] (k[$2]==""?"":", ") $1}
      END{for (p in k) print p "\t" k[p]}' | sort > "$tmp/access"
  local p kinds o n=0
  while IFS=$'\t' read -r p kinds; do
    o="$(origin "$p")"; [ "$o" = built-in ] || n=$((n+1))
    echo "- $p: $kinds ($o)" >> "$tmp/access.out"
  done < "$tmp/access"
  if [ $n -gt 0 ]; then section CHECK "$n installed apps have strong access"; else section OK "Only built-in apps have strong access"; fi
  echo "Strong access lets an app read your screen, read notifications, lock the phone or see what you type. Spy apps need it. Each app here must be one you chose."
  cat "$tmp/access.out" 2>/dev/null
  return 0
}

sideloaded() {
  have apps_user.txt || { unknown "Apps from outside the Play Store"; : > "$tmp/side"; return 0; }
  awk '$2!="com.android.vending" && $2!="com.android.chrome" {print $1}' "$tmp/user" | sort > "$tmp/side"
  local n; n="$(wc -l < "$tmp/side" | tr -d ' ')"
  if [ "$n" -gt 0 ]; then section CHECK "$n apps are not from the Play Store"; else section OK "All apps come from the Play Store"; fi
  [ "$n" -gt 0 ] && echo "Apps from outside the Play Store skip Google's checks. Spy apps often come this way. Remove the ones you do not know."
  local p
  while read -r p; do
    echo "- $p ($(origin "$p"), installed $(awk -v p="Package [$p]" 'index($0,p){f=1} f&&/firstInstallTime=/{sub(/.*=/,""); print substr($0,1,10); exit}' packages.txt 2>/dev/null | grep . || echo unknown))"
  done < "$tmp/side"
  return 0
}

network() {
  have network.txt || { unknown "Internet traffic"; return 0; }
  local proxy dns spec vpn bad=0
  proxy="$(sed -n 's/^http_proxy=//p' network.txt 2>/dev/null)"
  dns="$(sed -n 's/^private_dns_mode=//p' network.txt 2>/dev/null)"
  spec="$(sed -n 's/^private_dns_specifier=//p' network.txt 2>/dev/null)"
  vpn="$(grep -c 'ni{VPN' network.txt 2>/dev/null)"
  case "$proxy" in ""|null|:0) ;; *) bad=1 ;; esac
  [ "$dns" = hostname ] && bad=1
  [ "${vpn:-0}" -gt 0 ] && bad=1
  if [ $bad = 0 ]; then
    section OK "Internet traffic goes the normal way"
    echo "No proxy, no custom private DNS and no VPN."
  else
    section CHECK "Internet traffic is redirected"
    echo "This is fine if you set it up yourself. If not, someone may read your traffic."
    case "$proxy" in ""|null|:0) ;; *) echo "- Proxy: $proxy" ;; esac
    [ "$dns" = hostname ] && echo "- Private DNS: $spec"
    [ "${vpn:-0}" -gt 0 ] && echo "- A VPN is on."
  fi
  return 0
}

sensitive_use() {
  { have appops.txt && have apps_user.txt; } || { unknown "Camera, mic, photos and location use"; return 0; }
  awk '
    /^  Uid /{pkg=""}
    /^    Package /{pkg=$2; sub(/:$/,"",pkg)}
    /^      [A-Z_]+ \(/{op=$1}
    /Access:/ && pkg!="" {
      if (match($0,/\(-[0-9]+d/)) d=substr($0,RSTART+2,RLENGTH-3)+0; else if ($0 ~ /\(-/) d=0; else next
      if (d>30) next
      k=""
      if (op=="CAMERA") k="camera"
      else if (op=="RECORD_AUDIO") k="microphone"
      else if (op ~ /^READ_MEDIA_(IMAGES|VIDEO|VISUAL_USER_SELECTED)$/ || op=="READ_EXTERNAL_STORAGE") k="photos/videos"
      else if (op ~ /^(FINE|COARSE)_LOCATION$/) k="location"
      else if (op=="PROJECT_MEDIA") k="screen recording"
      if (k!="" && index(u[pkg],k)==0) u[pkg]=u[pkg] (u[pkg]==""?"":", ") k
    }
    END{for (p in u) print p "\t" u[p]}' appops.txt 2>/dev/null | sort > "$tmp/use"
  local p what o side=0
  while IFS=$'\t' read -r p what; do
    o="$(origin "$p")"; grep -qxF "$p" "$tmp/side" && side=1
    echo "- $p: $what ($o)" >> "$tmp/use.out"
  done < "$tmp/use"
  if [ $side = 1 ]; then section CHECK "An app from outside the Play Store used camera, mic, photos or location"
  else section INFO "Apps that used camera, mic, photos or location (last 30 days)"; fi
  echo "Each app here should be one you expect to use that. A flashlight app with the microphone is a red flag."
  cat "$tmp/use.out" 2>/dev/null
  return 0
}

accounts() {
  section INFO "Accounts on the phone"
  echo "Each account should be yours. An unknown account can sync your data to someone else."
  sed -n 's/^ *Account {name=\(.*\), type=\(.*\)}$/- \1 (\2)/p' accounts.txt 2>/dev/null | sort -u
}

storage() {
  have storage.txt || { unknown "Storage"; return 0; }
  local free; free="$(sed -n 's/^Data-Free: .* = \([0-9]*\)% free$/\1/p' storage.txt 2>/dev/null)"
  if [ "${free:-100}" -lt 10 ]; then section FIX "Storage is almost full (${free}% free)"
  elif [ "${free:-100}" -lt 20 ]; then section CHECK "Storage is getting full (${free}% free)"
  else section OK "Storage has room (${free:-?}% free)"; fi
  [ "${free:-100}" -lt 20 ] && echo "A full phone gets slow and cannot install updates."
  awk -F': ' '/^(Photos|Videos|Audio) Size:/{sub(/ Size/,"",$1); printf "- %s: %.1f GB\n", $1, $2/1e9}
              /^App Size:|^App Data Size:/{a+=$2} END{if (a) printf "- Apps and their data: %.1f GB\n", a/1e9}' storage.txt 2>/dev/null
  folders; duplicates; unused_apps
  echo "How to free space:"
  echo "- Google Photos → your profile picture → Free up space. It deletes only photos that are backed up."
  echo "- WhatsApp → Settings → Storage and data → Manage storage. Sort by size. Deleted media is gone from the chat too."
  echo "- Telegram → Settings → Data and Storage → Storage usage → Clear cache. Your chats stay in the Telegram cloud."
  echo "- Big apps: Settings → Apps → the app → Storage → Clear cache."
}

folders() {
  [ -s files.txt ] || return 0
  echo "Biggest folders:"
  awk -F'|' '{n=split($2,a,"/"); k=a[3]; if (n>4) k=k"/"a[4]; if (a[3]=="Android" && n>5) k=k"/"a[5]; t[k]+=$1}
             END{for (k in t) printf "%d\t%s\n", t[k], k}' files.txt | sort -rn | head -8 |
    while IFS=$'\t' read -r b k; do echo "- $k: $(gb "$b")"; done
}

duplicates() {
  [ -s hashes.txt ] || return 0
  awk -F'|' 'NR==FNR{p=$0; sub(/^[^|]*\|/,"",p); s[p]=$1; next}
    { h=substr($0,1,32); p=substr($0,35); if (!(p in s)) next
      if (h in first) {w+=s[p]; c++; l[c]=s[p] "\t" first[h] " = " p} else first[h]=p }
    END{print w+0 "\t" c+0; for (i=1;i<=c;i++) print l[i]}' files.txt hashes.txt > "$tmp/dup"
  local w c; IFS=$'\t' read -r w c < "$tmp/dup"
  echo "Exact duplicate files: $c, using $(gb "$w")."
  tail -n +2 "$tmp/dup" | sort -rn | head -10 | while IFS=$'\t' read -r b pair; do echo "- $(gb "$b"): $pair"; done
}

unused_apps() {
  have usage.txt || return 0
  awk '/^Package Names:/{gsub(/^Package Names: \[|\]$|"/,""); n=split($0,N,",")}
       /^App Sizes:/{gsub(/^App Sizes: \[|\]$/,""); split($0,A,",")}
       /^App Data Sizes:/{gsub(/^App Data Sizes: \[|\]$/,""); split($0,D,",")}
       END{for (i=1;i<=n;i++) print N[i], A[i]+D[i]}' storage.txt 2>/dev/null > "$tmp/size"
  sed -n 's/.*package=\([^ ]*\) .*lastTimeVisible="\([0-9-]*\) .*/\1 \2/p' usage.txt 2>/dev/null |
    awk '$2>l[$1]{l[$1]=$2} END{for (p in l) print p, l[p]}' > "$tmp/last"
  awk -v cut="$(days_ago 60)" 'FILENAME==ARGV[1]{s[$1]=$2; next} FILENAME==ARGV[2]{l[$1]=$2; next}
    { last=($1 in l && l[$1]>"1971") ? l[$1] : "never"
      if (s[$1]>50e6 && (last=="never" || last<cut)) printf "%d\t%s\t%s\n", s[$1], $1, last }' \
    "$tmp/size" "$tmp/last" "$tmp/user" | sort -rn > "$tmp/unused"
  [ -s "$tmp/unused" ] || return 0
  echo "Apps not opened in 60 days: $(wc -l < "$tmp/unused" | tr -d ' '), using $(gb "$(awk '{t+=$1} END{print t}' "$tmp/unused")"). The biggest:"
  head -20 "$tmp/unused" | while IFS=$'\t' read -r b p l; do echo "- $p: $(gb "$b"), last opened $l"; done
  echo "Before you remove a crypto wallet, a login-code app (like Authy) or a messenger, check for money, codes and messages."
}

memory() {
  local used total
  read -r used total < <(sed -n 's/.*ZRAM: .* for \([0-9,]*\)K in swap (\([0-9,]*\)K total swap).*/\1 \2/p' meminfo.txt 2>/dev/null | tr -d ,)
  if [ -z "${total:-}" ] || [ "$total" = 0 ]; then
    unknown "Memory"
  elif [ $((used * 10)) -gt $((total * 9)) ]; then
    section CHECK "Memory is full"
    echo "Restart the phone. Apps that always run (security apps, app blockers, launchers) use memory all the time."
  else
    section OK "Memory is fine"
  fi
  echo "Apps that use the most memory now:"
  sed -n '/^Total PSS by process:/,/^$/p' meminfo.txt 2>/dev/null | sed -n '2,6p' |
    sed -E 's/^ *([0-9,]+)K: ([^ ]+).*/- \2: \1 KB/'
}

battery() {
  local h c name
  h="$(sed -n 's/^  health: //p' battery.txt 2>/dev/null | head -1)"
  c="$(sed -n 's/^cycle_count: //p' battery.txt 2>/dev/null | head -1)"
  case "$h" in 2) name=good ;; 3) name=overheating ;; 4) name="worn out" ;; 5) name="over voltage" ;; 6) name=failure ;; 7) name=cold ;; *) name=unknown ;; esac
  [ -n "$h" ] || { unknown "Battery"; return 0; }
  if [ "$h" = 2 ] && [ "${c:-0}" -lt 800 ]; then section OK "Battery is fine"
  else section CHECK "Battery may be worn"; fi
  echo "Health: $name. Charge cycles: ${c:-unknown}."
  [ "$h" = 2 ] || echo "A new battery at a repair shop is the usual fix. Some phone makers also limit old batteries for safety."
  return 0
}

heat() {
  local t; t="$(sed -n 's/^Thermal Status: //p' thermal.txt 2>/dev/null | head -1)"
  [ -n "$t" ] || { unknown "Heat"; return 0; }
  if [ "${t:-0}" -gt 0 ]; then section CHECK "Phone is hot (level $t)"; echo "A hot phone slows itself down. Close heavy apps and let it cool."
  else section OK "Phone is not hot"; fi
}

manual() {
  section INFO "Check these by hand"
  echo "- Certificates: Settings → search \"Trusted credentials\" → tab User. It should be empty, unless work or school added one."
  echo "- Play Protect: Play Store → your profile picture → Play Protect → Scan."
  echo "- When you are done: Settings → System → Developer options → turn off USB debugging."
}

{
  integrity; updates; strong_access; sideloaded; network; sensitive_use; accounts
  storage; memory; battery; heat; manual
} > "$tmp/body"

{
  echo "phone-check: $(prop ro.product.model), Android $(prop ro.build.version.release), scanned $(sed -n 's/^scan_date=//p' device.txt 2>/dev/null | grep . || basename "$PWD")"
  echo "To fix: $(grep -c '^# FIX' "$tmp/body"). To check: $(grep -c '^# CHECK' "$tmp/body")."
  cat "$tmp/body"
} > summary.txt

"$here/render-html.sh" summary.txt > report.html
