#!/bin/bash
# Exercise the main-branch downloader offline with a local repository fixture.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/civ-installer-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tmp" "$work/repo/civ-liberator-main"
cp liberate.sh "$work/repo/civ-liberator-main/"
cp -R dependencies "$work/repo/civ-liberator-main/"
COPYFILE_DISABLE=1 tar -czf "$work/main.tar.gz" -C "$work/repo" civ-liberator-main
cat > "$work/curl" <<'MOCK'
#!/bin/bash
set -euo pipefail
[[ " $* " == *'https://github.com/malouf-dev/civ-liberator/archive/refs/heads/main.tar.gz'* ]] || exit 99
case ${TEST_MODE:-good} in
 fail) exit 22;;
 corrupt) printf corrupt > "${!#}";;
 *) cp "$TEST_ARCHIVE" "${!#}";;
esac
MOCK
chmod +x "$work/curl"
sed "s|/usr/bin/curl|$work/curl|" install.sh > "$work/install.sh"
export TEST_ARCHIVE="$work/main.tar.gz"
TMPDIR="$work/tmp" bash "$work/install.sh" --help > "$work/success.log"
[[ -z $(ls -A "$work/tmp") ]]
for mode in fail corrupt;do
 if TEST_MODE="$mode" TMPDIR="$work/tmp" bash "$work/install.sh" --help > "$work/$mode.log" 2>&1;then echo "Accepted $mode download";exit 1;fi
 [[ -z $(ls -A "$work/tmp") ]]
done
if TMPDIR="$work/tmp" bash "$work/install.sh" --invalid > "$work/invalid.log" 2>&1;then echo 'Swallowed setup failure';exit 1;fi
[[ -z $(ls -A "$work/tmp") ]]
# Main still verifies its bundled helper before running it.
printf broken > "$work/repo/civ-liberator-main/dependencies/civ-liberator"
COPYFILE_DISABLE=1 tar -czf "$work/main.tar.gz" -C "$work/repo" civ-liberator-main
if TMPDIR="$work/tmp" bash "$work/install.sh" --game 6 --inspect > "$work/checksum.log" 2>&1;then echo 'Accepted corrupted helper';exit 1;fi
[[ -z $(ls -A "$work/tmp") ]]
echo 'PASS main download, bad archive, dependency integrity, error propagation and cleanup'
