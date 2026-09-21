#!/usr/bin/env python3
"""Print the CHANGELOG.md section for a version as a self-contained HTML
fragment for Sparkle's inline release notes. Exits 1 if the section is
missing. Supports bullets, **bold**, `code` and [links](url) — nothing more.
With --md, prints the raw markdown section instead (for the GitHub release)."""
import html, re, sys

version = sys.argv[1]
text = open("CHANGELOG.md", encoding="utf-8").read()
m = re.search(rf"^## {re.escape(version)}\s*\n(.*?)(?=^## |\Z)", text, re.S | re.M)
if not m:
    sys.exit(1)
if "--md" in sys.argv[2:]:
    print(m.group(1).strip())
    sys.exit(0)

# Merge wrapped bullet lines, then collect bullets.
items = []
for line in m.group(1).splitlines():
    if re.match(r"^\s*[-*] ", line):
        items.append(re.sub(r"^\s*[-*] ", "", line).strip())
    elif line.strip() and items:
        items[-1] += " " + line.strip()

def inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return s

css = (
    "body{font:13px -apple-system,system-ui;margin:10px 14px;color:#222}"
    "h3{margin:0 0 6px;font-size:14px}ul{padding-left:18px;margin:0}li{margin:3px 0}"
    "code{font:12px ui-monospace,Menlo}a{color:#0a84ff}"
    "@media(prefers-color-scheme:dark){body{color:#ddd;background:transparent}}"
)
print(f"<style>{css}</style>")
print(f"<h3>kuroko {html.escape(version)}</h3>")
print("<ul>")
for it in items:
    print(f"  <li>{inline(it)}</li>")
print("</ul>")
