#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Build tools only: Xcode command-line tools, CMake >=3.24, Ninja and Git.
for tool in cmake ninja git; do command -v "$tool" >/dev/null || { echo "Missing build tool: $tool"; exit 1; }; done
work=$(mktemp -d "${TMPDIR:-/tmp}/civ-liberator-build.XXXXXX")
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT
mkdir "$work/goldberg" "$work/protobuf"
tar -xzf dependencies/source/goldberg-2ad4a39.tar.gz -C "$work/goldberg"
tar -xzf dependencies/source/protobuf-23.1-with-abseil.tar.gz -C "$work/protobuf"
git -C "$work/goldberg" apply "$PWD/dependencies/goldberg-build.patch"
cmake -S "$work/goldberg" -B "$work/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  "-DCMAKE_C_FLAGS=-ffile-prefix-map=$work=/civ-liberator-build -fdebug-prefix-map=$work=/civ-liberator-build" \
  "-DCMAKE_CXX_FLAGS=-ffile-prefix-map=$work=/civ-liberator-build -fdebug-prefix-map=$work=/civ-liberator-build" \
  -DFETCHCONTENT_SOURCE_DIR_PROTOBUF="$work/protobuf"
cmake --build "$work/build" --target steam_api -j 8
cp "$work/build/libsteam_api.dylib" dependencies/libsteam_api.dylib
dependencies/civ-liberator manifest 6 "$PWD"
