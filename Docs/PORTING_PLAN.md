# Native port tracking — v0.3

## Current completed engineering tasks

- Native Swift/Metal FPS scaffolding and iPhone landscape multitouch layout
- Offline training arena with basic bot combat and weapons
- Recovered deployed Cloudflare project identity and immutable build commit
- Created pinned URL downloader for split Nuketown GLB file/buffers
- Added import of glTF node matrices and material colors to Metal triangle stream
- Added native 2.5D floor + wall collision baker and runtime loader
- Added approximate map-aware player movement, bot positioning and hitscan occlusion
- Added CI pipeline that runs Python validation, optional map recovery, import,
  collision bake, Xcode build and unsigned IPA packaging

## Important unresolved blockers

- **Map asset data isn't embedded in this repository**. The build action downloads
  it at runtime. Neither network download nor Xcode compile was verified locally.
- Visuals are untextured and do not yet reproduce the published website.
- AI, collisions and animation are placeholders or approximations.
- Online multiplayer / Zombies do not exist in the native executable.
- Deployed Pages assets do not include all of the GitHub repository build tooling.
  The source repository is attached to a different GitHub account/org than the
  currently connected `kremityss` installation.

## Next technical milestones

1. Extract actual glTF metadata, check orientation, unit scaling, and ensure
   floor raster covers the 2020 map. Confirm successful CI log and IPA artifact.
2. Use an indexed GPU mesh format with material/texture IDs, proper normal
   matrices, UV coordinates, texture atlases, ASTC and LODs; split huge buffers.
3. Replace conservative raster collision with capsule sweeps on native BVH,
   floor steps, multi-level support, raycast damage and dynamic props.
4. Port authored firearm/viewmodel model/animation data and mobile HUD.
5. Rebuild state machine for player health, bots, TDM, FFA, objective modes;
   port backend networking and authoritative anti-cheat separately.
6. Restore sound effects using AVAudioEngine and scene audio attenuation.
7. Implement fully native Zombies and progression modules.
8. Hardware benchmark on iPhone: renderer frame time, memory peaks,
   map loading, sustained thermal performance, touch latency.

Do not label this project production-ready or advertise 60 FPS until a real
hardware run has been verified.
