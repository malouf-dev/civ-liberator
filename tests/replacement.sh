#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_app=$(bash liberate.sh --game 6 --inspect | head -1)
[[ -n "$source_app" ]] || { echo 'SKIP replacement checks: Civ VI is not installed';exit 0; }
work=$(mktemp -d "${TMPDIR:-/tmp}/civ-replacement-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/Applications"
target="$work/Applications/Sid Meier's Civilization VI.app"
# Unattended setup must refuse to replace without --replace, after saying what it found.
refuses() {
 if bash liberate.sh --game 6 --yes --destination "$work/Applications" --data "$work/Data" > "$work/refused.log" 2>&1;then echo 'Implicit unattended overwrite accepted';exit 1;fi
 grep -q "$1" "$work/refused.log" || { echo "Missing: $1";exit 1; }
}
# Older standalone apps must be offered for replacement, regardless of bundle ID.
mkdir "$target"
printf preserved > "$target/sentinel"
token=$(dependencies/civ-liberator target-identity 6 "$work/Applications")
dependencies/civ-liberator check 6 "$source_app" "$work/Applications" "$work/Data" "$token"
refuses 'It is a full app, not a shortcut.'
[[ $(cat "$target/sentinel") == preserved ]]
mkdir -p "$target/Contents/Resources"
printf '{}' > "$target/Contents/Resources/civ-liberator.json"
refuses 'an earlier Civ Liberator copy of Civilization VI'
# A different directory appearing after approval must not inherit that approval.
mv "$target" "$work/old.app"
mkdir "$target"
if dependencies/civ-liberator check 6 "$source_app" "$work/Applications" "$work/Data" "$token" >/dev/null 2>&1;then echo 'Stale approval accepted';exit 1;fi
rmdir "$target"
# A Steam symlink is approved as a directory entry, never its target.
ln -s "$source_app" "$target"
token=$(dependencies/civ-liberator target-identity 6 "$work/Applications")
dependencies/civ-liberator check 6 "$source_app" "$work/Applications" "$work/Data" "$token"
refuses 'a shortcut to your Steam copy of Civilization VI'
[[ $(readlink "$target") == "$source_app" ]]
unlink "$target"
# Finder alias files and broken shortcuts can also be backed up as entries.
printf 'bookalias-fixture' > "$target"
token=$(dependencies/civ-liberator target-identity 6 "$work/Applications")
dependencies/civ-liberator check 6 "$source_app" "$work/Applications" "$work/Data" "$token"
refuses 'a Finder alias named'
[[ $(cat "$target") == bookalias-fixture ]]
mv "$target" "$work/alias.app"
ln -s "$work/missing-game.app" "$target"
token=$(dependencies/civ-liberator target-identity 6 "$work/Applications")
dependencies/civ-liberator check 6 "$source_app" "$work/Applications" "$work/Data" "$token"
refuses 'a broken shortcut named'
[[ -L "$target" ]]
echo 'PASS old apps, earlier copies, shortcut entries, explicit overwrite and stale approval'
