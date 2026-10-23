#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for game in 5 6; do
 source_app=$(bash liberate.sh --game "$game" --inspect | head -1)
 [[ -n "$source_app" ]] || { echo "Missing Civ $game test installation" >&2;exit 1; }
 dependencies/civ-liberator verify-menus "$game" "dependencies/menus-$game.json" "$source_app"
done
# Check offset validation without writing to a real game.
work=$(mktemp -d "${TMPDIR:-/tmp}/civ-menu-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
printf hello > "$work/menu.lua"
before=$(shasum -a 256 "$work/menu.lua");before=${before%% *}
after=$(printf hallo | shasum -a 256);after=${after%% *}
printf '[{"path":"menu.lua","before":"%s","after":"%s","edits":[{"offset":1,"length":1,"text":"a"}]}]\n' "$before" "$after" > "$work/rules.json"
dependencies/civ-liberator verify-menus 6 "$work/rules.json" "$work"
[[ $(cat "$work/menu.lua") == hello ]]
sed 's/"offset":1/"offset":99/' "$work/rules.json" > "$work/bad.json"
if dependencies/civ-liberator verify-menus 6 "$work/bad.json" "$work" >/dev/null 2>&1;then echo 'Invalid patch accepted';exit 1;fi
printf changed > "$work/menu.lua"
if dependencies/civ-liberator verify-menus 6 "$work/rules.json" "$work" >/dev/null 2>&1;then echo 'Unknown source accepted';exit 1;fi
echo 'PASS patch bounds, source hashes and read-only verification'
