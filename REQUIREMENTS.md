# Requirements

## Goal
Universal LÖVE 11.5 player packaged as a UWP app; one package per game (fused `game.love`).

## Functional
- Runs any LÖVE 11.5 game unchanged where the platform allows (GLSL ES shaders, no native Lua modules).
- Per-game configuration in `games/<name>/player.json`: identity, publisher, names, version, colors, capabilities, images, `.love` path or source folder.
- Output: `.msix` per architecture, `.msixbundle`, `.msixupload` for the Store, VCLibs dependencies.
- Test signing with a self-signed certificate; Store submissions unsigned.
- LuaJIT identical to official LÖVE 11.5 desktop builds (2.1.1700008891).
- Desktop window resize and DPI handled correctly; Xbox gamepad usable through SDL's game controller API (to be verified on a console).

## Platforms
- Windows 10 2004+ (min 10.0.19041.0), tested on 10.0.19045; Windows 11.
- Xbox Dev Mode (sideload) and Microsoft Store (desktop; Xbox needs ID@Xbox).
- Architectures: x64, x86. ARM64 left open (preset exists, dependencies not built).

## Build host
- Windows, VS 2022 (UWP workload, v143 x64/x86), Windows SDK 10.0.26100, CMake 3.24+, Git for Windows, PowerShell.
- Prebuilt dependencies committed under `third_party/<arch>`: use them as-is, or rebuild them from pinned sources with `scripts/build-deps.ps1`.

## Legal
- Player licensed under zlib (LICENSE.md). Engine from love-xbox-uwp (LÖVE fork; its changes understood as zlib like LÖVE).
- All other code written independently for this project (clean-room style); no code copied from other projects. Upstream sources are only built from their pinned revisions.
- Third-party license texts shipped in every package (`licenses\`). OpenAL Soft (LGPL) stays a separate DLL.
- Games keep their own licenses; the player imposes no attribution on them.
- No Pokémon / gen1recomp code, data, names or assets.
