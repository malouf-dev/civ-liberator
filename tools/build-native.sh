#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/native
for arch in arm64 x86_64; do
  xcrun swiftc -O -target "$arch-apple-macosx11.0" -module-cache-path build/native/modules \
    src/Core.swift src/Main.swift -o "build/native/helper-$arch"
done
xcrun lipo -create build/native/helper-arm64 build/native/helper-x86_64 -output dependencies/civ-liberator
codesign --force --sign - dependencies/civ-liberator
shasum -a 256 dependencies/civ-liberator > dependencies/native.sha256
