# DONE

Finished work, grouped by topic (state as of 2026-10-13).

## Project and license

- New repository `love-uwp`: generic UWP player for LÖVE 11.5, one package per game (fused `game.love`).
- License review: the first draft was derived from a GPL-licensed UWP port; it was replaced by an independent rewrite
  (host, CMake, manifest, scripts, deps.json), its SDL patch dropped, all binaries rebuilt from upstream sources.
  The project is zlib (LICENSE.md, with origin note and third-party table). The GPL-era state is kept only as a
  bundle outside the repository; the first commit was removed and the history purged.
- No commits yet by decision; remote <https://github.com/rostok/love-upw.git> chosen.

## Player

- Host: `host/main.cpp` (SDL WinRT entry, `game.love` from the install folder, `--fused`), manifest template,
  transparent cursor resource (id 5000) so `love.mouse.setVisible(false)` hides the cursor only over the game.
- CMake project configured by `player.json` (`cmake/PlayerConfig.cmake`): identity, names, version, colours,
  capabilities, images, `.love` path or source folder. MinVersion fixed at 10.0.19041 (MSBuild otherwise writes the
  SDK version). Presets x64/x86/arm64.
- Scripts: `build.ps1` (per-arch msix, bundle, signing, Store `.msixupload`, `-OutDir`, pack from source),
  `new-dev-cert.ps1`, `build-deps.ps1` (all dependencies from pinned sources), `check-deps.ps1` (hashes),
  `LoveUwp.psm1`. Works in PowerShell 7 and Windows PowerShell 5.1.
- `love.progress(text, value)`: loading display drawn by the player (bar / step / text), keeps the window responsive,
  safe with an active Canvas; verified in hello and Schifahren.

## LÖVE and dependencies

- LÖVE from love-xbox-uwp + own patch: x86 LuaJIT build; stale EGL surface size after resizes (wrong DPI scale,
  cropping, missing text); `__stdcall` EGL function pointers (x86 crash); enet without winmm; `love.progress`.
- LuaJIT pinned to 2.1.1700008891, the revision of official LÖVE 11.5 desktop builds (jit.* modules, bytecode).
- vcpkg overlays: FreeType UWP file access (`_WINRT_DLL`), OpenAL Soft x86 calling convention.
- SDL 2.32.10 unmodified; ANGLE x64 and x86 built from source.
- Build works behind the build PC's firewall: downloads through Git's curl, `gclient sync --nohooks`, `rc.exe` via curl.
- `third_party/x64` and `third_party/x86` committed (use as-is) and reproducible (`build-deps.ps1`).

## Verified

- Windows 10 19045, x64 and x86: `games/hello` (rendering, resize, DPI, JIT, fonts, canvases, progress) and a large
  real game (Schifahren) running from an installed signed bundle and from build folders.
- Signed x64+x86 bundle, end-user install with the test certificate in `LocalMachine\TrustedPeople`,
  Store `.msixupload` (bundle extracts cleanly).
- Shaders: GLSL ES rules documented after fixing a real game; the fixed shaders still work on desktop LÖVE.

## Documentation

- README (usage, per-game folder, player.json, testing, saves/logs, love.progress, platform notes),
  PUBLISH-HOWTO (versions, certificates, packages, testers, Xbox, Store, checklist),
  DEVELOPMENT (internals, patches, rebuilding, testing, debugging, licensing history), REQUIREMENTS, LICENSE.
- Game-specific notes live in the game's own `uwp` folder (example: `C:\projects\lua\schifahren\uwp`).
