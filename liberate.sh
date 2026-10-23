#!/bin/bash
# Bash 3.2-compatible interface; runtime tools are included with macOS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
BOLD='' DIM='' CYAN='' GREEN='' RESET=''
if [[ -t 1 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; CYAN=$'\033[36m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
fi
fail() { printf '\n  %sError%s  %s\n\n' "$BOLD" "$RESET" "$*" >&2; exit 1; }
step() { printf '\n%s  %s%s\n  ────────────────────────────────────────────────\n' "$CYAN" "$1" "$RESET"; }
help() {
 cat <<'HELP'
Civ Liberator — independent Mac copies of Civilization V and VI

Usage: bash liberate.sh [options]

  --game 5|6             Game to build
  --source PATH          Native .app inside a completed Steam installation
  --destination PATH     Applications folder (default: /Applications if writable)
  --data PATH            Dedicated save and mod folder
  --no-menus             Keep the original online menus
  --no-mods              Skip downloaded mod import
  --yes                 Use supplied/default choices without prompting
  --inspect             Read-only Steam discovery (requires --game)
  --help                Show this help

No Python, Homebrew or Xcode required. Do not run with sudo.
Use NO_COLOR=1 for plain output. Ctrl-C cancels before completion.
HELP
}
game='' source_app='' destination='' data='' menus=yes mods=yes unattended=no inspect=no
while [[ $# -gt 0 ]]; do
 case "$1" in
 --game|--source|--destination|--data)
  [[ $# -ge 2 && -n "$2" ]] || fail "$1 needs a value."
  case "$1" in --game) game=$2;; --source) source_app=$2;; --destination) destination=$2;; --data) data=$2;; esac; shift 2;;
 --no-menus) menus=no;shift;; --no-mods) mods=no;shift;; --yes) unattended=yes;shift;; --inspect) inspect=yes;shift;;
 --help|-h) help;exit 0;; *) fail "Unknown option: $1. Use --help.";;
 esac
done
[[ $(uname -s) == Darwin ]] || fail 'macOS is required.'
[[ $EUID -ne 0 ]] || fail 'Run as your normal user, without sudo.'
major=$(/usr/bin/sw_vers -productVersion);major=${major%%.*}
[[ $major -ge 11 ]] || fail 'This build targets macOS 11 or newer.'
helper="$ROOT/dependencies/civ-liberator"
[[ -x "$helper" ]] || fail 'The native helper is missing. Download the complete repository.'
/usr/bin/shasum -a 256 -c dependencies/native.sha256 >/dev/null 2>&1 || fail 'Native helper checksum mismatch. Restore it from a trusted copy.'
if [[ $unattended == no && $inspect == no && ! -t 0 ]]; then fail 'Interactive setup needs a terminal. Use --game and --yes for unattended use.';fi
ask_path() {
 local label=$1 current=$2 reply
 printf '  %s\n  %s%s%s\n' "$label" "$DIM" "$current" "$RESET" >&2
 if [[ -n "$current" ]]; then
  printf '  Press Return to use this folder, or type another: ' >&2
 else
  printf '  Enter the path to the game .app: ' >&2
 fi
 IFS= read -r reply || exit 130
 [[ -n "$reply" ]] || reply=$current
 case "$reply" in '~') reply=$HOME;; '~/'*) reply="$HOME/${reply:2}";; esac
 printf '%s' "$reply"
}
ask_bool() {
 local label=$1 current=$2 reply hint
 while :; do
  hint='yes';[[ $current == no ]] && hint='no'
  printf '  %s (yes/no, Return = %s): ' "$label" "$hint" >&2
  IFS= read -r reply || exit 130
  case "$reply" in '') printf '%s' "$current";return;; y|Y|yes|YES) printf yes;return;; n|N|no|NO) printf no;return;; *) printf '  Please enter y or n.\n' >&2;; esac
 done
}
if [[ $inspect == yes ]]; then
 [[ $game == 5 || $game == 6 ]] || fail '--inspect requires --game 5 or --game 6.'
 exec "$helper" discover "$game"
fi
printf '\n  %sCIV LIBERATOR%s\n  Play your installed Civilization games without Steam.\n' "$BOLD" "$RESET"
step 'Choose your game'
if [[ -z "$game" ]]; then
 [[ $unattended == no ]] || fail '--yes requires --game 5 or --game 6.'
 printf '\n  %s1)%s Civilization V\n  %s2)%s Civilization VI\n\n' "$BOLD" "$RESET" "$BOLD" "$RESET"
 while :; do
  printf '  Choose 1 or 2 (q to quit): ';IFS= read -r choice || exit 130
  case "$choice" in
   1) game=5;break;;
   2) game=6;break;;
   q|Q) exit 0;;
   *) printf '  Enter 1 for Civilization V or 2 for Civilization VI.\n';;
  esac
 done
fi
[[ $game == 5 || $game == 6 ]] || fail 'Choose --game 5 or --game 6.'
roman=VI;[[ $game == 5 ]] && roman=V
if [[ -z "$source_app" ]]; then
 sources=()
 while IFS= read -r path; do [[ -z "$path" ]] || sources[${#sources[@]}]=$path; done < <("$helper" discover "$game")
 if [[ ${#sources[@]} -eq 1 ]]; then source_app=${sources[0]}
 elif [[ $unattended == yes ]]; then fail 'Specify --source when there is no unique installed copy.'
 else
  if [[ ${#sources[@]} -gt 1 ]];then
   printf '\n  More than one installed copy was found:\n';for path in "${sources[@]}";do printf '    %s\n' "$path";done
  else printf '\n  No installed copy was found. Finish downloading the Mac game in Steam,\n  or enter its location below.\n';fi
  while [[ -z "$source_app" ]]; do
   source_app=$(ask_path 'Where is the installed game?' '')
   [[ -n "$source_app" ]] || printf '  Enter a game path, or press Ctrl-C to cancel.\n'
  done
 fi
fi
printf '\n  %sFound Civilization %s.%s Your Steam copy stays untouched.\n' "$GREEN" "$roman" "$RESET"
step 'Choose your folders'
if [[ -z "$destination" ]];then destination=/Applications;[[ -w "$destination" ]] || destination="$HOME/Applications";fi
[[ -n "$data" ]] || data="$HOME/Documents/Games/Civilization $roman"
if [[ $unattended == no ]]; then
 printf '\n';destination=$(ask_path 'Where should the game be installed?' "$destination")
 printf '\n';data=$(ask_path 'Where should saves and mods be kept?' "$data")
 step 'Choose what to include'
 printf '\n  Single-player, installed expansions and hotseat are kept.\n  Steam online play, cloud saves and automatic updates are unavailable.\n\n'
 menus=$(ask_bool 'Hide menus for unavailable online features?' "$menus")
 printf '\n  Mods already downloaded through Steam can be copied too.\n'
 mods=$(ask_bool 'Copy your downloaded mods?' "$mods")
fi
step 'Ready to install'
printf '\n  Game          Civilization %s\n  Install in    %s\n  Saves & mods  %s\n' "$roman" "$destination" "$data"
if [[ $menus == yes ]];then printf '  Online menus  Hidden\n';else printf '  Online menus  Kept (online features remain unavailable)\n';fi
if [[ $mods == yes ]];then printf '  Existing mods Copied when supported\n';else printf '  Existing mods Not copied\n';fi
"$helper" check "$game" "$source_app" "$destination" "$data"
"$helper" verify "$game" "$ROOT" >/dev/null
target="$destination/Sid Meier's Civilization $roman.app"
if [[ -e "$target" || -L "$target" ]];then
 printf '\n  The existing shortcut or Liberator app will be backed up and replaced.\n'
fi
printf '\n  Your Steam game and existing saves stay untouched.\n'

if [[ $unattended == no ]];then
 printf '\n';confirm=$(ask_bool 'Install now?' no)
 [[ $confirm == yes ]] || { printf '\n  Cancelled. Nothing was installed.\n';exit 0; }
fi
step 'Installing'
printf '\n  This may take a few minutes.\n'
exec "$helper" build "$game" "$ROOT" "$source_app" "$destination" "$data" "$menus" "$mods"
