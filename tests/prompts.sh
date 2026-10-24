#!/bin/bash
# Drive the interactive prompts through a terminal, then decline before anything is installed.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -n $(bash liberate.sh --game 6 --inspect | head -1) ]] || { echo 'SKIP prompt checks: Civ VI is not installed';exit 0; }
work=$(mktemp -d "${TMPDIR:-/tmp}/civ-prompts-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir "$work/My Apps"
cat > "$work/prompts.exp" <<'EXPECT'
set timeout 15
log_user 0
proc want {text} {
 expect {
  -ex $text {}
  timeout { puts "Missing: $text"; exit 1 }
  eof { puts "Ended before: $text"; exit 1 }
 }
}
spawn -noecho bash liberate.sh
want {Which game, 1 or 2?}
send "3\r"
want {Choose one of the numbers above.}
send "2\r"
want {Step 2 of 4}
want {Where should the game go? [}
want {] }
# A Finder drag escapes spaces with backslashes and adds a trailing space.
send "$env(WORK)/My\\ Apps \r"
want {Where should saves and mods go? [}
want {] }
send "~/Library/Application Support/Steam/civ-prompts-test\r"
want {outside Steam}
want {Where should saves and mods go? [}
want {] }
send "'$env(WORK)/Data'\r"
want {Hide menus for unavailable online features? [Y/n]}
send "maybe\r"
want {Type y for yes or n for no.}
send "\r"
want {Copy your downloaded mods? [Y/n]}
send "n\r"
want {Enable Rise and Fall? [Y/n]}
send "\r"
want {Enable Gathering Storm? [Y/n]}
send "n\r"
want "Install in    $env(WORK)/My Apps"
want "Saves & mods  $env(WORK)/Data"
want {Mods          Not copied}
want {Expansions    Rise and Fall}
want {Install now? [Y/n]}
send "n\r"
want {Cancelled. Nothing was installed.}
expect eof
lassign [wait] pid spawnid os_error status
if {$status != 0} { puts "Declining exited with $status"; exit 1 }
spawn -noecho bash liberate.sh
want {Which game, 1 or 2?}
send "\003"
want {Cancelled. Nothing was installed.}
expect eof
EXPECT
WORK="$work" NO_COLOR=1 /usr/bin/expect "$work/prompts.exp"
[[ -z $(ls -A "$work/My Apps") && ! -e "$work/Data" && ! -e "$HOME/Library/Application Support/Steam/civ-prompts-test" ]]
echo 'PASS game menu, dragged and quoted paths, answers checked as given, expansions, decline and Ctrl-C'
