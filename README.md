# Merk of Duty — Native iOS / Metal (v0.4.0)

**Native Swift/Metal foundation — not a completed Black Ops II port.**

This project runs **without a WebView, browser game engine, or JIT**. It contains
original Swift gameplay logic, a native Metal renderer, and iPhone touch controls.
The test build can use its procedural offline combat arena; the opt-in pipeline
can download and import map geometry from your pinned Cloudflare Pages deployment.

## Verified project origin

- Cloudflare Pages: `merk-of-duty`
- Production: https://merk-of-duty.pages.dev
- Pinned deployment: https://56538cf3.merk-of-duty.pages.dev
- Repository referenced by Cloudflare: `KremCheats/claude-of-duty2.0`
- Deployed Git commit: `c74da1a91275869214ffab6e64a7c0186e959d40`
- Deployment date: September 22, 2026
- Manifest: 1,374 files (including JavaScript gameplay modules, map GLBs, split
  map buffers, weapon models, textures, sounds, and navigation/collision files)

## Gameplay already in Swift

- First-person camera rendered through Metal at a requested 60 FPS
- Left thumbstick and right-area touch look, fire, aim-down-sights, sprint,
  jump, slide, reload, and weapon swap
- Native firearm state, recoil, reloading, ammo, hitscan, targets, and simple bots
- Weapon stats: M27, AN-94, DSR 50, Five-seven (selected values recovered from
  `weapons.js`; tuning such as reload duration remains provisional)
- Basic bot AI, offline kills/deaths, health and respawn
- Optional imported **textured map** geometry (MERKMAP2) and native rasterized floor/wall collision
- Optional M27, AN-94, DSR 50 and Five-seven **static weapon viewmodels** with per-weapon texture atlases and untextured fallback
- Simple line-of-sight testing against baked map walls

## Build an IPA with GitHub Actions (no local Mac required)

1. Put all files from this ZIP in a **new or authorized GitHub repository**.
2. Open **Actions → Build native Metal iOS IPA → Run workflow**.
3. Keep **bundle_nuketown = true** to retrieve the pinned GLB, its two
   external binary buffers and referenced textures (when accessible). Use
   **bundle_weapon_models = true** to import four static gun meshes, or disable
   either option to build with original fallback primitives.
4. If the action succeeds, download the `MerkOfDutyNative-unsigned-ipa` artifact.
5. Sign the IPA using your own valid iOS signing method before installing it.

**A signed or installable IPA is not included in this ZIP.** Xcode, iPhone
performance and the exact production geometry have not been tested in this
workspace. GitHub Actions can fail on SDK errors or inaccessible map files;
those results must be inspected before claiming an actual working IPA.

### Build yourself on macOS

```bash
brew install xcodegen
python3 -m unittest discover -s Tests -v
python3 Tools/download_level.py --out build/recovered-map
mkdir -p MerkOfDuty/Resources
python3 Tools/convert_gltf.py build/recovered-map/nuketown_2020_optimized.glb \
  --out MerkOfDuty/Resources/MerkMap.meshbin \
  --texture-atlas MerkOfDuty/Resources/MerkAtlas.png --scale 0.01 --max-triangles 1000000
python3 Tools/bake_collision.py MerkOfDuty/Resources/MerkMap.meshbin \
  --out MerkOfDuty/Resources/MerkCollision.bin --cell-size 0.75
xcodegen generate --spec project.yml
xcodebuild -project MerkOfDutyNative.xcodeproj -scheme MerkOfDutyNative \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

When using `xcodegen`, create the files under `MerkOfDuty/Resources` **before**
generating the Xcode project so resource references are included.

### Offline training arena only

Omit the download and conversion steps. Leave `MerkOfDuty/Resources/` empty;
the native game uses its original procedural arena automatically.

## Map conversion limitations

The actual GLB assets and textures are **not bundled** with the source ZIP.
Import occurs in GitHub Actions or on a networked build machine. The new
MERKMAP2 converter preserves UV0, glTF base-color textures via a generated
RGBA atlas, transforms and baseColorFactor. It does not yet support multiple
texture coordinate sets beyond authored references, GLTF non-default samplers,
normal/roughness/metalness maps, alpha blending, rigging or animation. Images
that are inaccessible or unsupported produce a white fallback and an error
in the conversion report. Static weapon meshes are auto-centered and their
longest axis aligned to -Z; exact ADS alignment still needs calibration.

The raster uses a single coarse floor elevation per cell and conservative
wall segments; it is not precision collision. Some map areas may be blocked,
bots can spawn incorrectly, and collision may behave poorly at stairways and
multistory structures. The runtime is not at gameplay parity with the live
website.

## Work still required for a playable full native port

1. Test actual map geometry import and adjust coordinate transform/spawns.
2. Verify native textured map and weapon views on an iPhone; tune viewmodel poses and material fidelity.
3. Replace grid collision with accurate capsule sweeps and native navmesh.
4. Rebuild native gun/viewmodel animation state, particles, and audio.
5. Port multiplayer protocol and backend integration (Cloudflare D1/Functions).
6. Port Zombies, loadouts and progression with native UI.
7. Profile GPU/CPU/memory and verify 60 FPS on the intended iPhone.
8. Review licensing before publicly distributing any third-party or game assets.

## Validation performed here

- Swift sources: **syntax-parsed** with `swiftc -frontend -parse`.
- Converter/collision/viewmodel tests: **11 passing Python tests** (subject to this
  source snapshot), including split external buffers, UV atlas mapping and
  static gun-model normalization.
- GitHub Actions workflow: YAML structure parsed.
- Xcode compilation and iPhone hardware testing: **not available** here.

## v0.4 technical changes

- Native geometry format `MERKMAP2` (64 bytes per packed vertex) stores 3D
  position, normal, RGBA, UV and atlas region. `MERKMAP1` remains supported.
- Metal shaders sample a base-color atlas while keeping the original cube bot
  and training arena rendering via a white fallback material.
- Added `Tools/download_weapons.py` and four native static viewmodel import
  steps with independent atlases.
- Recover published map texture files when the embedded/external glTF texture
  references are available from the pinned Cloudflare deployment.
- Model textures, full scene shaders and weapon animations remain incomplete.
- No iPhone build or performance certification was possible in the Linux runtime.

## CI update (v0.4.1) — GitHub Actions or Codemagic

This archive is **ready to upload as a repository**. Its first objective is to
compile and preserve a reproducible **unsigned IPA** before attempting the
large remote assets. The app is not fully ported and the IPA has not yet been
compiled on a macOS runner.

### GitHub Actions

1. Create an empty repository such as `kremityss/merk-of-duty-native-ios`.
2. Upload the *contents* of this ZIP to the repository root (not the parent
   `MerkOfDuty-Native-iOS/` folder), keeping `.github/workflows/...`.
3. The initial push to `main` triggers `Merk of Duty - Native iOS IPA`.
   The `offline-ipa` job compiles the procedural native training arena.
4. In the Actions tab select `Run workflow` and optionally enable `full_assets`
   to attempt Nuketown and weapon model imports after the base IPA succeeds.
5. Open the completed run's **Artifacts** section. The base artifact is named
   `MerkOfDutyNative-offline-unsigned`; when full asset import succeeds there
   is also `MerkOfDutyNative-full-unsigned`.

Two separate jobs ensure the full-asset download/conversion failure does not
prevent delivery of a successful offline IPA. Build logs and checksums are
uploaded too. Every IPA is **unsigned** and must be signed before sideloading.

### Codemagic

Connect the same repository in Codemagic, enable YAML configuration, and choose
`native-ios-unsigned` to compile the original arena. Choose
`native-ios-nuketown` to attempt full map and weapon model imports. Download
`*.ipa` from the build's Artifacts section after a successful run.

Do not put API keys or Apple signing certificates in the repository. The CI
recipes intentionally perform only unsigned builds.

### Known CI constraints

- External downloads from the Cloudflare pinned deployment may be blocked or
  disappear; start with the offline target.
- Tests and syntax parsing can be run on Linux but a real native IPA requires
  Xcode on macOS. No signed, installable or device-tested IPA has been produced.
- The project is an evolving native shooter foundation, not a faithful finished
  port of every gameplay system of the deployed browser game.

## October 27, 2026 map integration update

- First GitHub Actions offline IPA build passed (run #40586725483).
- Imported level spawns are now selected near the recovered map's raster center.
- Movement collision no longer clamps imported maps to the small fallback arena.
- A commit containing `[full assets]` in its message requests the expensive
  map-and-weapon build; ordinary pushes still compile the offline version.
- Full asset build and iPhone runtime testing remain unverified until the
  corresponding GitHub job finishes.

### Full-assets build correction
The October 27 full map build downloaded and converted 558,120 triangles, but a
very large sky/environment mesh made the collision bounds exceed the raster
limit. The map converter now applies an explicit 50,000-source-unit cutoff **for
the map only**, logging the number of excluded triangles. This is not applied
to weapon assets. Imported terrain collisions are still approximate.

## v0.5 — Instanced Nuketown scenery and diagnostics

- The Cloudflare deployment's `nuketown_2020_optimized.glb` uses
  `EXT_mesh_gpu_instancing`: **198 node groups, 2,989 placements**.
- A new `--instances-out MerkOfDuty/Resources/MerkInstances.bin` switch
  converts repeated geometry into a separate `MERKINS1` stream with a single
  local mesh per group and native Metal transform instances; duplicate
  prototype meshes are removed from the base map export.
- `NativeInstancedMap.swift` parses the stream with size checks. The renderer
  submits instanced Metal draws using the same albedo atlas as the map.
- The HUD shows approximate rendered FPS and whether the Nuketown assets
  and scenery groups loaded, making the first on-device test easier to diagnose.
- Unlike the static environment mesh, **instanced objects are visual-only**.
  Their collision is not yet integrated into the 2.5D floor/wall grid.
- The loaded map still lacks complete gameplay parity (native multiplayer,
  Zombies, original skeletal animation, audio, and advanced navigation).
  Do not treat a compiled IPA as a fully tested game.
