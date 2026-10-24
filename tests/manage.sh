#!/bin/bash
# Drive --manage against a recorded-choices fixture, then decline before anything is rebuilt.
set -euo pipefail
cd "$(dirname "$0")/.."
source_app=$(bash liberate.sh --game 6 --inspect | head -1)
[[ -n "$source_app" ]] || { echo 'SKIP manage checks: Civ VI is not installed';exit 0; }
work=$(mktemp -d "${TMPDIR:-/tmp}/civ-manage-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
app="$work/Applications/Sid Meier's Civilization VI.app"
mkdir -p "$app/Contents/Resources" "$work/Empty"
printf '{"game":"6","data":"%s","source":"%s","menus":"no","mods":"no","without":"gatheringstorm"}' "$work/Data" "$source_app" > "$app/Contents/Resources/civ-liberator.json"
fails() {
 if bash liberate.sh "${@:2}" > "$work/refused.log" 2>&1;then echo "Accepted: ${*:2}";exit 1;fi
 grep -q "$1" "$work/refused.log" || { echo "Missing: $1";cat "$work/refused.log";exit 1; }
}
cat > "$work/manage.exp" <<'EXPECT'
set timeout 15
log_user 0
proc want {text} {
 expect {
  -ex $text {}
  timeout { puts "Missing: $text"; exit 1 }
  eof { puts "Ended before: $text"; exit 1 }
 }
}
spawn -noecho bash liberate.sh --manage --destination "$env(WORK)/Applications"
want {Step 1 of 2: Choose expansions}
want {Changing Civilization VI in}
# Recorded choices become the defaults: Gathering Storm was off.
want {Enable Rise and Fall? [Y/n]}
send "n\r"
want {Enable Gathering Storm? [y/N]}
send "y\r"
want {Step 2 of 2: Check and apply}
want {Expansions    Gathering Storm}
want {Only the expansion list changes.}
want {Apply now? [Y/n]}
send "n\r"
want {Cancelled. Nothing was changed.}
expect eof
lassign [wait] pid spawnid os_error status
if {$status != 0} { puts "Declining exited with $status"; exit 1 }
EXPECT
WORK="$work" NO_COLOR=1 /usr/bin/expect "$work/manage.exp"
[[ $(ls -A "$work/Applications") == "Sid Meier's Civilization VI.app" && ! -e "$work/Data" ]]
fails 'keeps your other choices' --manage --yes --destination "$work/Applications" --data "$work/Elsewhere"
fails 'No copy made by Civ Liberator was found' --manage --yes --destination "$work/Empty"
fails 'no installed expansion called hotseat' --manage --yes --destination "$work/Applications" --without hotseat
printf '{"game":"6","data":"%s"}' "$work/Data" > "$app/Contents/Resources/civ-liberator.json"
fails 'made by an earlier version of setup' --manage --yes --destination "$work/Applications"
# End to end on a real Civ V copy: switch Brave New World off in place, then back on.
civ5=$(bash liberate.sh --game 5 --inspect | head -1)
if [[ -n "$civ5" ]]; then
 bash liberate.sh --game 5 --yes --no-mods --destination "$work/Real" --data "$work/RealData" > "$work/build.log" 2>&1 || { cat "$work/build.log";exit 1; }
 real="$work/Real/Sid Meier's Civilization V.app"
 dlc="$real/Contents/Helpers/Game.app/Contents/MacOS/steam_settings/DLC.txt"
 [[ -z $(grep '^#' "$dlc") ]]
 bash liberate.sh --manage --yes --destination "$work/Real" --without bravenewworld > "$work/off.log" 2>&1 || { cat "$work/off.log";exit 1; }
 grep -q '^#235580=' "$dlc"
 if grep -q '^#16870=' "$dlc";then echo 'Gods & Kings was turned off too';exit 1;fi
 [[ $(plutil -extract without raw -o - "$real/Contents/Resources/civ-liberator.json") == bravenewworld ]]
 [[ $(ls -A "$work/Real") == "Sid Meier's Civilization V.app" ]]
 codesign --verify --deep --strict "$real"
 bash liberate.sh --manage --yes --destination "$work/Real" --without none > "$work/on.log" 2>&1 || { cat "$work/on.log";exit 1; }
 [[ -z $(grep '^#' "$dlc") ]]
 codesign --verify --deep --strict "$real"
else
 echo 'SKIP in-place manage check: Civ V is not installed'
fi
echo 'PASS manage finds the copy, reuses recorded choices, switches expansions in place without a backup and refuses older copies'
