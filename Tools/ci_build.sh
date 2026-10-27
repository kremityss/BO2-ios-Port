#!/usr/bin/env bash
set -euo pipefail

# Valid modes: offline (no game asset download), full (pinned Pages assets).
MODE="${1:-offline}"
case "$MODE" in
  offline|full) ;;
  *) echo "Usage: $0 [offline|full]" >&2; exit 2;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p output build/logs

# Confirm our asset preparation tooling works before spending macOS build time.
python3 -m unittest discover -s Tests -v 2>&1 | tee build/logs/python-tests.log

if [ "$MODE" = full ]; then
  python3 Tools/download_level.py --out build/recovered-map
  mkdir -p MerkOfDuty/Resources
  python3 Tools/convert_gltf.py build/recovered-map/nuketown_2020_optimized.glb \
    --out MerkOfDuty/Resources/MerkMap.meshbin \
    --texture-atlas MerkOfDuty/Resources/MerkAtlas.png \
    --scale 0.01 --max-triangles 1000000
  python3 Tools/bake_collision.py MerkOfDuty/Resources/MerkMap.meshbin \
    --out MerkOfDuty/Resources/MerkCollision.bin --cell-size 0.75
  python3 Tools/download_weapons.py --out build/recovered-weapons
  for item in \
    'M27:t6_wpn_ar_hk416_view_lod0' \
    'AN94:t6_wpn_ar_an94_view_lod0' \
    'DSR50:t6_wpn_sniper_dsr50_view_lod0' \
    'FiveSeven:t6_wpn_pistol_fiveseven_view_lod0'; do
    key="${item%%:*}"
    model="${item#*:}"
    python3 Tools/convert_gltf.py "build/recovered-weapons/viewmodel/${model}.glb" \
      --out "MerkOfDuty/Resources/MerkWeapon${key}.meshbin" \
      --texture-atlas "MerkOfDuty/Resources/MerkWeapon${key}Atlas.png" \
      --weapon-length 1.05 --max-triangles 250000
  done
fi

# Generate AFTER assets so Xcodegen will include their resource files.
if ! command -v xcodegen >/dev/null 2>&1; then
  echo 'Installing XcodeGen via Homebrew'
  brew install xcodegen
fi
xcodegen generate --spec project.yml

# Do not sign an IPA with placeholder credentials. The unsigned IPA may be
# signed later using the owner's iOS certificate and provisioning profile.
set -o pipefail
xcodebuild \
  -project MerkOfDutyNative.xcodeproj \
  -scheme MerkOfDutyNative \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$ROOT/build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build/logs/xcodebuild.log

APP="$ROOT/build/DerivedData/Build/Products/Release-iphoneos/MerkOfDutyNative.app"
if [ ! -d "$APP" ]; then echo "Expected app not found: $APP" >&2; exit 1; fi
mkdir -p build/package/Payload
cp -R "$APP" build/package/Payload/
(cd build/package && zip -qry "$ROOT/output/MerkOfDutyNative-${MODE}-unsigned.ipa" Payload)
shasum -a 256 output/*.ipa | tee build/logs/sha256.txt
printf 'Unsigned IPA generated: %s\n' "$ROOT/output/MerkOfDutyNative-${MODE}-unsigned.ipa"
