#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_app=$(bash liberate.sh --game 6 --inspect | head -1)
[[ -n "$source_app" ]] || { echo 'SKIP replacement checks: Civ VI is not installed';exit 0; }
work=$(mktemp -d "${TMPDIR:-/tmp}/civ-replacement-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/Applications"
target="$work/Applications/Sid Meier's Civilization VI.app"
# Older standalone apps must be offered for replacement, regardless of bundle ID.
mkdir "$target"
printf preserved > "$target/sentinel"
token=$(dependencies/civ-liberator target-identity 6 "$work/Applications")
dependencies/civ-liberator check 6 "$source_app" "$work/Applications" "$work/Data" "$token"
if bash liberate.sh --game 6 --yes --destination "$work/Applications" --data "$work/Data" > "$work/refused.log" 2>&1;then echo 'Implicit unattended overwrite accepted';exit 1;fi
[[ $(cat "$target/sentinel") == preserved ]]
# A different directory appearing after approval must not inherit that approval.
mv "$target" "$work/old.app"
mkdir "$target"
if dependencies/civ-liberator check 6 "$source_app" "$work/Applications" "$work/Data" "$token" >/dev/null 2>&1;then echo 'Stale approval accepted';exit 1;fi
rmdir "$target"
# A Steam symlink is approved as a directory entry, never its target.
ln -s "$source_app" "$target"
token=$(dependencies/civ-liberator target-identity 6 "$work/Applications")
dependencies/civ-liberator check 6 "$source_app" "$work/Applications" "$work/Data" "$token"
[[ $(readlink "$target") == "$source_app" ]]
unlink "$target"
# Finder alias files and broken shortcuts can also be backed up as entries.
printf alias-fixture > "$target"
token=$(dependencies/civ-liberator target-identity 6 "$work/Applications")
dependencies/civ-liberator check 6 "$source_app" "$work/Applications" "$work/Data" "$token"
[[ $(cat "$target") == alias-fixture ]]
mv "$target" "$work/alias.app"
ln -s "$work/missing-game.app" "$target"
token=$(dependencies/civ-liberator target-identity 6 "$work/Applications")
dependencies/civ-liberator check 6 "$source_app" "$work/Applications" "$work/Data" "$token"
[[ -L "$target" ]]
echo 'PASS old apps, shortcut entries, explicit overwrite and stale approval'
