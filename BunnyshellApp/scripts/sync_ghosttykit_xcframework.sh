#!/usr/bin/env bash
set -euo pipefail

# Sync Ghostty's locally-built GhosttyKit.xcframework into this repo.
#
# Source of truth: /Users/bunnypro/ghostty/macos/GhosttyKit.xcframework
# Destination used by this project: BunnyshellApp/Frameworks/ghostty-internal-fat.xcframework
#
# If you want to rebuild GhosttyKit first, do it in the ghostty repo:
#   cd /Users/bunnypro/ghostty
#   zig build -Demit-xcframework=true

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SRC="/Users/bunnypro/ghostty/macos/GhosttyKit.xcframework"
DST="${ROOT_DIR}/Frameworks/ghostty-internal-fat.xcframework"

if [[ ! -d "${SRC}" ]]; then
  echo "Missing source xcframework: ${SRC}" >&2
  exit 1
fi

rm -rf "${DST}"
cp -R "${SRC}" "${DST}"

echo "Synced:"
echo "  ${SRC}"
echo "→ ${DST}"

