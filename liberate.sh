#!/bin/bash
# Bash 3.2-compatible interface; runtime tools are included with macOS.
set -euo pipefail
START=$PWD
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
BOLD='' BLUE='' RED='' RESET=''
if [[ -t 1 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'; BLUE=$'\033[34m'; RED=$'\033[31m'; RESET=$'\033[0m'
fi
fail() { printf '%sError:%s %s\n' "$BOLD$RED" "$RESET" "$*" >&2; exit 1; }
# Everything inside a step is indented to line up with the text after ==>.
say() { printf '    %s\n' "$@"; }
cancel() { printf '\n';say "Cancelled. $unchanged"; exit 130; }
help() {
 cat <<'HELP'
Civ Liberator: independent Mac copies of Civilization V and VI

Usage: bash liberate.sh [options]
       bash liberate.sh --manage [--game 5|6] [--destination PATH] [--without NAME] [--yes]

  --game 5|6            Game to build
  --source PATH         Native .app inside a completed Steam installation
  --destination PATH    Applications folder (default: /Applications if writable)
  --data PATH           Dedicated save and mod folder
  --no-menus            Keep the original online menus
  --no-mods             Skip downloaded mod import
  --without NAME        Turn off an expansion; repeat for more than one.
                        Civ V: godsandkings, bravenewworld
                        Civ VI: riseandfall, gatheringstorm
                        With --manage, --without none turns them all back on.
  --replace             Back up and replace an existing destination app
  --manage              Change the expansions in a copy you already made
  --yes                 Use supplied/default choices without prompting
  --inspect             Read-only Steam discovery (requires --game)
  --help                Show this help

No Python, Homebrew or Xcode required. Do not run with sudo.
Use NO_COLOR=1 for plain output. Ctrl-C cancels before completion.
HELP
}
game='' source_app='' destination='' data='' menus=yes mods=yes unattended=no inspect=no replace=no without='' without_given=no manage=no
while [[ $# -gt 0 ]]; do
 case "$1" in
 --game|--source|--destination|--data|--without)
  [[ $# -ge 2 && -n "$2" ]] || fail "$1 needs a value."
  case "$1" in --game) game=$2;; --source) source_app=$2;; --destination) destination=$2;; --data) data=$2;; --without) without="${without:+$without,}$2" without_given=yes;; esac; shift 2;;
 --no-menus) menus=no;shift;; --no-mods) mods=no;shift;; --yes) unattended=yes;shift;; --inspect) inspect=yes;shift;;
 --replace) replace=yes;shift;; --manage) manage=yes;shift;;
 --help|-h) help;exit 0;; *) fail "Unknown option: $1. Use --help.";;
 esac
done
[[ $without != none ]] || without=''
[[ $(uname -s) == Darwin ]] || fail 'macOS is required.'
[[ $EUID -ne 0 ]] || fail 'Run as your normal user, without sudo.'
major=$(/usr/bin/sw_vers -productVersion);major=${major%%.*}
[[ $major -ge 11 ]] || fail 'This build targets macOS 11 or newer.'
helper="$ROOT/dependencies/civ-liberator"
[[ -x "$helper" ]] || fail 'The native helper is missing. Download the complete repository.'
/usr/bin/shasum -a 256 -c dependencies/native.sha256 >/dev/null 2>&1 || fail 'Native helper checksum mismatch. Restore it from a trusted copy.'
# Browser downloads mark every file as quarantined, and macOS then refuses to run the ad-hoc signed
# helper. Clear the mark from our own dependencies only, after the helper's checksum has matched.
/usr/bin/xattr -dr com.apple.quarantine "$ROOT/dependencies" 2>/dev/null || true
if [[ $unattended == no && $inspect == no && ! -t 0 ]]; then fail 'Interactive setup needs a terminal. Use --game and --yes for unattended use.';fi
if [[ $inspect == yes ]]; then
 [[ $game == 5 || $game == 6 ]] || fail '--inspect requires --game 5 or --game 6.'
 exec "$helper" discover "$game"
fi
# The helper's argument check needs a game number; verification covers both games.
"$helper" verify 6 "$ROOT" >/dev/null
trap cancel INT

# Expand ~, resolve relative paths from where setup started and drop trailing slashes.
absolute() {
 local p=$1
 case "$p" in '~') p=$HOME;; '~/'*) p="$HOME/${p:2}";; esac
 [[ -z "$p" || $p == /* ]] || p="$START/$p"
 while [[ $p == */ && $p != / ]]; do p=${p%/}; done
 printf '%s' "$p"
}
short() { case "$1" in "$HOME") printf '~';; "$HOME"/*) printf '~%s' "${1#"$HOME"}";; *) printf '%s' "$1";; esac; }
step() {
 local count=''
 [[ $unattended == yes || -z "$1" ]] || count="Step $1 of $steps: "
 printf '\n%s==>%s %s%s%s%s\n' "$BOLD$BLUE" "$RESET" "$BOLD" "$count" "$2" "$RESET"
}
warn() { printf '    %s%s%s\n' "$RED" "$1" "$RESET"; }
# Ask a bold question with its default in brackets; sets reply.
# \001 and \002 tell readline the colour codes take no space on the line.
prompt_for() {
 local p="    "$'\001'"$BOLD"$'\002'"$1"$'\001'"$RESET"$'\002'
 [[ -z "$2" ]] || p="$p [$2]"
 IFS= read -r -e -p "$p " reply || cancel
}
# Prompts set answer, so they run in this shell and Ctrl-C reaches the cancel trap.
ask_path() {
 local s c out=''
 prompt_for "$1" "$(short "$2")"
 # Finder drags add a trailing space; drags and Tab completion escape spaces and quotes.
 s=${reply#"${reply%%[![:space:]]*}"};s=${s%"${s##*[![:space:]]}"}
 if [[ ${#s} -ge 2 && ( $s == \'*\' || $s == \"*\" ) ]]; then out=${s:1:${#s}-2}
 else while [[ -n "$s" ]];do c=${s:0:1};s=${s:1};if [[ $c == \\ && -n "$s" ]];then c=${s:0:1};s=${s:1};fi;out+=$c;done
 fi
 if [[ -z "$out" ]];then answer=$2;else answer=$(absolute "$out");fi
}
ask_bool() {
 local hint='Y/n'
 [[ $2 == yes ]] || hint='y/N'
 while :; do
  prompt_for "$1" "$hint"
  case "$reply" in '') answer=$2;return;; [yY]|[yY][eE][sS]) answer=yes;return;; [nN]|[nN][oO]) answer=no;return;; esac
  warn 'Type y for yes or n for no.'
 done
}
# Ask $2 until the answer is a number from 1 to $1; Return picks $3 when it is set.
choose() {
 while :; do
  prompt_for "$2" "$3"
  [[ -n "$reply" ]] || reply=$3
  if [[ $reply =~ ^[1-9][0-9]*$ ]] && [[ $reply -le $1 ]];then answer=$reply;return;fi
  warn 'Choose one of the numbers above.'
 done
}
# Say what is already at the install path, so the replace question is clear.
describe_existing() {
 local target="$destination/Sid Meier's $title.app" where name keep='Setup will keep it as a backup, then install the new copy.' magic
 where=$(short "$destination") name="Sid Meier's $title.app"
 if [[ -L "$target" && "$target" -ef "$source_app" ]]; then
  say "$where has a shortcut to your Steam copy of $title." 'Setup will keep the shortcut as a backup, then install the new copy.' 'The Steam game stays untouched.'
 elif [[ -L "$target" && ! -e "$target" ]]; then
  say "$where has a broken shortcut named $name." "$keep"
 elif [[ -L "$target" ]]; then
  say "$where has a shortcut to $(short "$(readlink "$target")")." 'Setup will keep the shortcut as a backup, then install the new copy.' 'The app it points to stays untouched.'
 elif [[ -f "$target" ]]; then
  # Finder aliases are bookmark files, which start with "book".
  magic=$(head -c 4 "$target" 2>/dev/null || true)
  if [[ $magic == book ]]; then
   say "$where has a Finder alias named $name." 'Setup will keep the alias as a backup, then install the new copy.' 'The app it points to stays untouched.'
  else
   say "$where has a file named $name." "$keep"
  fi
 elif [[ -f "$target/Contents/Resources/civ-liberator.json" ]]; then
  say "$where already has an earlier Civ Liberator copy of $title." "$keep" 'Your saves and mods stay where they are.'
 else
  say "$where already has $name. It is a full app, not a shortcut." "$keep"
 fi
}
# Checks set why when they fail, so each step can explain and ask again.
usable() {
 if why=$("$helper" check "$game" "$@" 2>&1 >/dev/null);then return 0;fi
 why=${why#"${why%%[![:space:]]*}"};why=${why#Error: }
 return 1
}
writable() {
 local p=$1
 while [[ ! -e "$p" && ! -L "$p" ]]; do p=$(dirname "$p"); done
 [[ -d "$p" && -w "$p" ]]
}
can_install_in() {
 why='Choose the folder to put the game in, not an app.'
 [[ $1 != *.app ]] || return 1
 why='Setup cannot write to this folder. Choose one inside your home folder.'
 writable "$1" || return 1
 why='Setup cannot look inside this folder.'
 replacement=$("$helper" target-identity "$game" "$1" 2>/dev/null) || return 1
 usable "$source_app" "$1" "$probe/Data" "$replacement"
}
can_keep_data_in() {
 why='Setup cannot write to this folder. Choose one inside your home folder.'
 writable "$1" || return 1
 usable "$source_app" "$destination" "$1" "$replacement"
}
# Ask about each installed expansion; the answers replace the --without list.
ask_expansions() {
 local i=0 off='' default later=' Change them later with --manage.'
 [[ $manage == no ]] || later=''
 [[ ${#exp_keys[@]} -eq 0 ]] || say "Expansions you turn off are hidden in the game.$later"
 while [[ $i -lt ${#exp_keys[@]} ]]; do
  default=yes;[[ ",$without," != *",${exp_keys[i]},"* ]] || default=no
  ask_bool "Enable ${exp_names[i]}?" "$default"
  [[ $answer == yes ]] || off="${off:+$off,}${exp_keys[i]}"
  i=$((i+1))
 done
 without=$off
}
answer='' why='' replacement=none steps=4 unchanged='Nothing was installed.'
# Never created: lets the game be checked before its folders are chosen.
probe="${TMPDIR:-/tmp}/civ-liberator-probe-$$"
source_app=$(absolute "$source_app");destination=$(absolute "$destination");data=$(absolute "$data")

if [[ $manage == yes ]]; then
 [[ -z "$source_app$data" && $menus == yes && $mods == yes ]] || fail '--manage keeps your other choices. Use it only with --game, --destination, --without and --yes.'
 steps=2 unchanged='Nothing was changed.'
 printf '%sCiv Liberator:%s change the expansions in a copy you already made.\n' "$BOLD" "$RESET"
else
 printf '%sCiv Liberator:%s play your installed Civilization games without Steam.\n' "$BOLD" "$RESET"
fi
[[ $unattended == yes ]] || printf 'Press Return to accept the answer in [brackets]. Ctrl-C cancels.\n'
if [[ $manage == yes ]]; then
 # Look for copies this version of setup made, which record their choices.
 [[ $unattended == yes ]] || step 1 'Choose expansions'
 copies=() dirs=("$destination") games=("$game")
 [[ -n "$destination" ]] || dirs=(/Applications "$HOME/Applications")
 [[ -n "$game" ]] || games=(5 6)
 for dir in "${dirs[@]}"; do
  for g in "${games[@]}"; do
   r=VI;if [[ $g == 5 ]];then r=V;fi
   if [[ -f "$dir/Sid Meier's Civilization $r.app/Contents/Resources/civ-liberator.json" ]];then copies[${#copies[@]}]="$dir/Sid Meier's Civilization $r.app";fi
  done
 done
 if [[ ${#copies[@]} -eq 0 ]];then
  where='/Applications or ~/Applications';[[ -z "$destination" ]] || where=$(short "$destination")
  fail "No copy made by Civ Liberator was found in $where. Use --destination to choose its folder."
 elif [[ ${#copies[@]} -eq 1 ]];then app=${copies[0]}
 elif [[ $unattended == yes ]];then fail 'More than one copy was found. Choose one with --game or --destination.'
 else
  i=0;for path in "${copies[@]}";do i=$((i+1));say "$i) $(short "$path")";done
  range='1 or 2';[[ ${#copies[@]} -eq 2 ]] || range="1 to ${#copies[@]}"
  choose ${#copies[@]} "Which copy, $range?" '';app=${copies[answer-1]}
 fi
 json="$app/Contents/Resources/civ-liberator.json"
 recorded() { /usr/bin/plutil -extract "$1" raw -o - "$json" 2>/dev/null; }
 source_app=$(recorded source) || fail "$(short "$app") was made by an earlier version of setup, so its choices weren't saved. Run setup without --manage once to rebuild it."
 game=$(recorded game)
 [[ $without_given == yes ]] || without=$(recorded without)
 destination=$(dirname "$app")
 # If Steam moved the game since, fall back to finding it again.
 usable "$source_app" "$probe/Applications" "$probe/Data" || source_app=''
fi
[[ $unattended == yes || $manage == yes ]] || step 1 'Choose your game'
if [[ -z "$game" ]]; then
 [[ $unattended == no ]] || fail '--yes requires --game 5 or --game 6.'
 found5=$("$helper" discover 5);found6=$("$helper" discover 6)
 status5='not found' status6='not found' suggest=''
 [[ -z "$found5" ]] || status5=installed
 [[ -z "$found6" ]] || status6=installed
 [[ -z "$found5" || -n "$found6" ]] || suggest=1
 [[ -n "$found5" || -z "$found6" ]] || suggest=2
 say "1) Civilization V    $status5" "2) Civilization VI   $status6"
 choose 2 'Which game, 1 or 2?' "$suggest"
 game=5;[[ $answer == 1 ]] || game=6
fi
[[ $game == 5 || $game == 6 ]] || fail 'Choose --game 5 or --game 6.'
roman=VI;[[ $game == 5 ]] && roman=V
title="Civilization $roman"
if [[ -z "$source_app" ]]; then
 sources=()
 while IFS= read -r path; do [[ -z "$path" ]] || sources[${#sources[@]}]=$path; done < <("$helper" discover "$game")
 if [[ ${#sources[@]} -eq 1 ]]; then source_app=${sources[0]}
 elif [[ $unattended == yes ]]; then
  if [[ ${#sources[@]} -eq 0 ]];then fail "$title was not found in Steam. Choose it with --source.";fi
  fail "$title is in more than one Steam library. Choose one with --source."
 elif [[ ${#sources[@]} -gt 1 ]]; then
  say "$title is in more than one Steam library."
  i=0;for path in "${sources[@]}";do i=$((i+1));say "$i) $(short "$path")";done
  range='1 or 2';[[ ${#sources[@]} -eq 2 ]] || range="1 to ${#sources[@]}"
  choose ${#sources[@]} "Which copy, $range?" '';source_app=${sources[answer-1]}
 else
  say "$title was not found in Steam." 'Finish downloading it in Steam, or drag the game in from Finder.'
  while :; do
   ask_path 'Where is the game?' ''
   if [[ -z "$answer" ]];then warn 'Drag the game into this window, or type its path.'
   elif usable "$answer" "$probe/Applications" "$probe/Data";then source_app=$answer;break
   else warn "$why";fi
  done
 fi
fi
usable "$source_app" "$probe/Applications" "$probe/Data" || fail "$why"
# Installed expansions as parallel lists; --without names must be among them.
exp_keys=() exp_names=()
while IFS=$'\t' read -r key name; do exp_keys[${#exp_keys[@]}]=$key;exp_names[${#exp_names[@]}]=$name; done < <("$helper" expansions "$game" "$source_app")
for key in $(printf '%s' "$without" | tr ',' ' '); do
 [[ " ${exp_keys[*]:-} " == *" $key "* ]] || fail "$title has no installed expansion called $key. Use --help for the names."
done
if [[ $manage == yes ]];then
 [[ ${#exp_keys[@]} -gt 0 ]] || fail "$title has no installed expansions to turn on or off."
 [[ $unattended == yes ]] || say "Changing $title in $(short "$destination")."
elif [[ $unattended == no ]];then
 say "Found $title in Steam. Your Steam copy stays untouched."
fi

if [[ -z "$destination" ]];then destination=/Applications;[[ -w "$destination" ]] || destination="$HOME/Applications";fi
[[ -n "$data" ]] || data="$HOME/Documents/Games/$title"
if [[ $manage == yes ]]; then
 [[ $unattended == yes ]] || ask_expansions
elif [[ $unattended == yes ]]; then
 can_install_in "$destination" || fail "$why"
 can_keep_data_in "$data" || fail "$why"
else
 step 2 'Choose your folders'
 say 'Type a folder, or drag one in from Finder.'
 while :; do ask_path 'Where should the game go?' "$destination";can_install_in "$answer" && break;warn "$why";done
 destination=$answer
 while :; do ask_path 'Where should saves and mods go?' "$data";can_keep_data_in "$answer" && break;warn "$why";done
 data=$answer
 step 3 'Choose what to include'
 say "Single-player, expansions and hotseat work. Steam online features don't."
 ask_bool 'Hide menus for unavailable online features?' "$menus";menus=$answer
 ask_bool 'Copy your downloaded mods?' "$mods";mods=$answer
 ask_expansions
fi
exp_text='' i=0
while [[ $i -lt ${#exp_keys[@]} ]]; do [[ ",$without," == *",${exp_keys[i]},"* ]] || exp_text="${exp_text:+$exp_text, }${exp_names[i]}";i=$((i+1));done

# --manage only rewrites the expansion list inside the app and re-signs it.
if [[ $manage == yes ]];then
 step 2 'Check and apply'
 printf '    %-14s%s\n' Game "$title" App "$(short "$app")" Expansions "${exp_text:-None}"
 printf '\n';say 'Only the expansion list changes. Your saves, mods and other choices stay as they are.'
 if [[ $unattended == no ]];then
  printf '\n';ask_bool 'Apply now?' yes
  [[ $answer == yes ]] || { say "Cancelled. $unchanged";exit 0; }
 fi
 step "" "Updating $title"
 exec "$helper" set-expansions "$game" "$app" "$source_app" "$without"
fi

step 4 'Check and install'
menu_text=Hidden;[[ $menus == yes ]] || menu_text='Kept (online features remain unavailable)'
mod_text='Copied when supported';[[ $mods == yes ]] || mod_text='Not copied'
printf '    %-14s%s\n' Game "$title" 'Install in' "$(short "$destination")" 'Saves & mods' "$(short "$data")" 'Online menus' "$menu_text" Mods "$mod_text"
[[ ${#exp_keys[@]} -eq 0 ]] || printf '    %-14s%s\n' Expansions "${exp_text:-None}"
prompt='Install now?'
if [[ $replacement != none ]];then
 printf '\n';describe_existing
 if [[ $unattended == yes && $replace != yes ]];then
  fail 'To replace this app without prompting, add --replace. Otherwise run without --yes.'
 fi
 prompt='Replace it and install?'
fi
if [[ $unattended == no ]];then
 printf '\n';ask_bool "$prompt" yes
 [[ $answer == yes ]] || { say "Cancelled. $unchanged";exit 0; }
fi
step "" "Installing $title"
exec "$helper" build "$game" "$ROOT" "$source_app" "$destination" "$data" "$menus" "$mods" "$replacement" "$without"
