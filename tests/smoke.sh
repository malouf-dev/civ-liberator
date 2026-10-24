#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n liberate.sh tools/build-native.sh tools/build-dependencies.sh
bash liberate.sh --help >/dev/null
if bash liberate.sh --invalid > /dev/null 2>&1; then echo 'Invalid flag accepted';exit 1;fi
dependencies/civ-liberator verify 6 "$PWD"
work=$(mktemp -d "${TMPDIR:-/tmp}/civ-liberator-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
for game in 5 6; do
 source_app=$(bash liberate.sh --game "$game" --inspect | head -1)
 if [[ -z "$source_app" ]];then printf 'SKIP Civ %s safety checks: no installed source\n' "$game";continue;fi
 roman=VI;[[ $game == 5 ]] && roman=V
 dependencies/civ-liberator check "$game" "$source_app" "$work/Applications" "$work/Data"
 if dependencies/civ-liberator check "$game" "$source_app" "$source_app" "$work/Data" >/dev/null 2>&1;then echo 'Unsafe source destination accepted';exit 1;fi
 mkdir -p "$work/Data" "$work/Outside"
 ln -s "$work/Outside" "$work/Data/Logs"
 if dependencies/civ-liberator check "$game" "$source_app" "$work/Applications" "$work/Data" >/dev/null 2>&1;then echo 'External data symlink accepted';exit 1;fi
 unlink "$work/Data/Logs"
 mkdir -p "$work/Applications/Sid Meier's Civilization $roman.app"
 printf preserved > "$work/Applications/Sid Meier's Civilization $roman.app/sentinel"
 if dependencies/civ-liberator check "$game" "$source_app" "$work/Applications" "$work/Data" >/dev/null 2>&1;then echo 'Unrelated app accepted';exit 1;fi
 [[ $(cat "$work/Applications/Sid Meier's Civilization $roman.app/sentinel") == preserved ]]
 if bash liberate.sh --game "$game" --yes --without hotseat --destination "$work/Fresh" --data "$work/FreshData" > "$work/without.log" 2>&1;then echo 'Unknown expansion accepted';exit 1;fi
 grep -q 'no installed expansion called hotseat' "$work/without.log"
 [[ ! -e "$work/Fresh" ]]
 printf 'PASS Civ %s discovery, destination safety and expansion names\n' "$game"
done
# A browser download quarantines every file; setup must still run the helper, and clear the mark.
mkdir "$work/zip"
cp liberate.sh "$work/zip/" && cp -R dependencies "$work/zip/"
find "$work/zip" -type f -exec xattr -w com.apple.quarantine "0081;$(printf '%x' "$(date +%s)");Safari;" {} \;
(cd "$work/zip" && bash liberate.sh --game 6 --inspect >/dev/null)
if xattr -p com.apple.quarantine "$work/zip/dependencies/libsteam_api.dylib" >/dev/null 2>&1;then echo 'Quarantine left on dependencies';exit 1;fi
printf 'PASS shell syntax, help, invalid arguments, dependency checks and browser downloads\n'
