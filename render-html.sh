#!/usr/bin/env bash
# summary.txt -> one self-contained HTML page on stdout.
# Format: line 1 title, line 2 counts, "# STATUS Title" opens a section, "- " is a list item.
set -euo pipefail

cat <<'HEAD'
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>phone-check report</title>
<style>
:root{--bg:#f7f7f5;--card:#fff;--text:#1d1d1b;--muted:#6b6b66;--line:#e4e4df;
--ok:#1f7a4d;--info:#3b5bdb;--check:#b26a00;--fix:#c92a2a}
@media (prefers-color-scheme:dark){:root{--bg:#161615;--card:#1f1f1d;--text:#ededea;--muted:#9a9a94;--line:#33332f;
--ok:#4cc38a;--info:#7c9cff;--check:#f0a83a;--fix:#ff6b6b}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:760px;margin:0 auto;padding:32px 16px 64px}
h1{font-size:1.5rem;margin:0 0 4px}
.counts{color:var(--muted);margin:0 0 24px}
section{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--c);border-radius:10px;padding:14px 18px;margin:12px 0}
h2{font-size:1.05rem;margin:0 0 6px;display:flex;gap:10px;align-items:baseline}
.badge{font-size:.7rem;font-weight:700;letter-spacing:.06em;color:var(--c)}
p{margin:6px 0}
ul{margin:6px 0;padding-left:20px}
li{margin:2px 0;overflow-wrap:anywhere}
.OK{--c:var(--ok)}.INFO{--c:var(--info)}.CHECK{--c:var(--check)}.FIX{--c:var(--fix)}
.INFO ul,.OK ul{color:var(--muted)}
footer{color:var(--muted);font-size:.85rem;margin-top:24px}
</style></head><body><main>
HEAD

sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$1" | awk '
  function close_list(){ if (inlist) { print "</ul>"; inlist=0 } }
  NR==1 { print "<h1>" $0 "</h1>"; next }
  NR==2 { print "<p class=\"counts\">" $0 "</p>"; next }
  /^# / { close_list(); if (open) print "</section>"
          st=$2; t=$0; sub(/^# [A-Z]+ /,"",t)
          print "<section class=\"" st "\"><h2><span class=\"badge\">" st "</span>" t "</h2>"; open=1; next }
  /^- / { if (!inlist) { print "<ul>"; inlist=1 } print "<li>" substr($0,3) "</li>"; next }
  /^$/  { next }
        { close_list(); print "<p>" $0 "</p>" }
  END   { close_list(); if (open) print "</section>" }'

cat <<'FOOT'
<footer>Made by phone-check. This page holds personal data. Do not share it.</footer>
</main></body></html>
FOOT
