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
  # The deployed map and guns store albedo as KHR_texture_basisu/KTX2;
  # Pillow cannot decode them without the Basis Universal transcoder.
  if ! command -v basisu >/dev/null 2>&1; then
    brew install basis_universal
  fi
  python3 Tools/download_level.py --out build/recovered-map
  mkdir -p MerkOfDuty/Resources
  python3 Tools/convert_gltf.py build/recovered-map/nuketown_2020_optimized.glb \
    --out MerkOfDuty/Resources/MerkMap.meshbin \
    --texture-atlas MerkOfDuty/Resources/MerkAtlas.png \
    --scale 0.01 --max-triangles 1000000 --max-source-coordinate 50000 \
    --instances-out MerkOfDuty/Resources/MerkInstances.bin \
    --minimum-decoded-textures 1 \
    --transform-metadata build/recovered-map/native-transform.json
  python3 Tools/import_web_movement.py --out MerkOfDuty/Resources/MerkWebMovement.json
  node Tools/import_web_weapons.mjs --out MerkOfDuty/Resources/MerkWebWeapons.json
  python3 Tools/import_web_spawns.py \
    --transform build/recovered-map/native-transform.json \
    --out MerkOfDuty/Resources/MerkWebSpawns.json
  python3 Tools/bake_collision.py MerkOfDuty/Resources/MerkMap.meshbin \
    --out MerkOfDuty/Resources/MerkCollision.bin --cell-size 0.75 --playable-radius 160 \
    --web-bvh-meta build/recovered-map/nuketown_2020_collision_bvh.json \
    --web-bvh-binary build/recovered-map/nuketown_2020_collision_bvh.bin \
    --web-transform build/recovered-map/native-transform.json
  python3 Tools/clear_authored_spawn_walls.py \
    --collision MerkOfDuty/Resources/MerkCollision.bin \
    --spawns MerkOfDuty/Resources/MerkWebSpawns.json
  # Hijacked ships a real GLB, 350 Basis images, and its own original
  # 208,616-triangle collision BVH; the other three catalog maps still ship
  # with placeholder geometry and are deliberately excluded from the picker.
  python3 Tools/download_level.py --map hijacked --out build/recovered-hijacked
  python3 Tools/convert_gltf.py build/recovered-hijacked/hijacked_optimized.glb \
    --out MerkOfDuty/Resources/MerkMapHijacked.meshbin \
    --texture-atlas MerkOfDuty/Resources/MerkAtlasHijacked.png \
    --scale 0.01 --max-triangles 1000000 --max-source-coordinate 50000 \
    --instances-out MerkOfDuty/Resources/MerkInstancesHijacked.bin \
    --minimum-decoded-textures 1 --map-id mp_hijacked \
    --transform-metadata build/recovered-hijacked/native-transform.json
  python3 Tools/import_web_spawns.py --map hijacked \
    --transform build/recovered-hijacked/native-transform.json \
    --out MerkOfDuty/Resources/MerkWebSpawnsHijacked.json
  python3 Tools/bake_collision.py MerkOfDuty/Resources/MerkMapHijacked.meshbin \
    --out MerkOfDuty/Resources/MerkCollisionHijacked.bin \
    --cell-size 0.75 --playable-radius 160 \
    --web-bvh-meta build/recovered-hijacked/hijacked_collision_bvh.json \
    --web-bvh-binary build/recovered-hijacked/hijacked_collision_bvh.bin \
    --web-transform build/recovered-hijacked/native-transform.json
  python3 Tools/clear_authored_spawn_walls.py \
    --collision MerkOfDuty/Resources/MerkCollisionHijacked.bin \
    --spawns MerkOfDuty/Resources/MerkWebSpawnsHijacked.json
  # Static character LOD (temporary until native skeletal animation arrives).
  python3 Tools/download_enemy.py --out build/recovered-enemy
  python3 Tools/convert_gltf.py build/recovered-enemy/enemies/c_chn_mp_pla_assault_fb_lod2.glb \
    --out MerkOfDuty/Resources/MerkEnemyAssault.meshbin \
    --texture-atlas MerkOfDuty/Resources/MerkEnemyAssaultAtlas.png \
    --weapon-length 1.75 --max-triangles 200000 \
    --minimum-decoded-textures 1
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
      --weapon-length 1.05 --max-triangles 250000 \
      --minimum-decoded-textures 1
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
