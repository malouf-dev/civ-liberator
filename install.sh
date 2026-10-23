#!/bin/bash
# Download the current main branch. No release or commit is pinned.
set -euo pipefail
URL='https://github.com/malouf-dev/civ-liberator/archive/refs/heads/main.tar.gz'
[[ $(uname -s) == Darwin ]] || { echo 'This installer needs macOS.' >&2; exit 1; }
[[ $EUID -ne 0 ]] || { echo 'Run as your normal user, without sudo.' >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/civ-liberator.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '\nDownloading Civ Liberator from main…\n'
/usr/bin/curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 2 "$URL" -o "$work/main.tar.gz"
/usr/bin/tar -xzf "$work/main.tar.gz" -C "$work"
setup="$work/civ-liberator-main/liberate.sh"
[[ -f "$setup" ]] || { echo 'The download does not contain Civ Liberator setup.' >&2; exit 1; }
# Keep prompts available when the caller redirected standard input.
if ( : </dev/tty ) 2>/dev/null; then
 /bin/bash "$setup" "$@" </dev/tty
else
 /bin/bash "$setup" "$@"
fi
