#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)"
ACCOUNT="${SPARKLE_KEYCHAIN_ACCOUNT:-inmouse-istraw}"
TOOL="$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
for arch in arm64 x86_64; do
  directory="$ROOT/dist/appcast-$arch"
  mkdir -p "$directory"
  cp "$ROOT/dist/InMouse-macos-$arch.zip" "$directory/"
  "$TOOL" --account "$ACCOUNT" \
    --download-url-prefix "https://github.com/istraw/StrokeMouse/releases/download/v$VERSION/" \
    --link "https://github.com/istraw/StrokeMouse/releases/tag/v$VERSION" \
    -o "$ROOT/dist/appcast-$arch.xml" "$directory"
  xmllint --noout "$ROOT/dist/appcast-$arch.xml"
done
