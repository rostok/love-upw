# love-uwp

Package a [LÖVE](https://love2d.org) 11.5 game as a Universal Windows Platform
app (`.msix` / `.msixbundle`) for **Windows 10/11 desktop**, **Xbox (Dev Mode)**
and the **Microsoft Store**.

The player is a small UWP host that runs a fused `game.love` with a UWP build
of LÖVE. It renders through ANGLE (OpenGL ES on Direct3D 11) and takes gamepad
input through Windows.Gaming.Input. Each game gets its own package identity,
name, tiles and capabilities, all set in one `player.json`.

| Item | Value |
| --- | --- |
| LÖVE | 11.5 ([love-xbox-uwp](https://github.com/caorthann-celt/love-xbox-uwp) + [our patch](third_party/patches/love-uwp-player.patch)) |
| Minimum OS | Windows 10 version 2004 (build 19041), Xbox One / Series |
| Architectures | x64, x86 (ARM64: see [Architectures](#architectures)) |
| Build host | Windows 10/11 with Visual Studio 2022 |

Documents:

| File | Contents |
| --- | --- |
| README.md (this file) | what it is, building a game, `player.json`, testing, saves and logs, `love.progress`, platform notes |
| [PUBLISH-HOWTO.md](PUBLISH-HOWTO.md) | versions, certificates, packages, testers, Xbox Dev Mode, Microsoft Store, release checklist |
| [DEVELOPMENT.md](DEVELOPMENT.md) | how the player works inside, the patches and why, rebuilding dependencies, testing and debugging |
| [LICENSE.md](LICENSE.md) | zlib, origin, third-party licenses |
| [REQUIREMENTS.md](REQUIREMENTS.md), [TODO.md](TODO.md), [DONE.md](DONE.md) | goals, open and finished work |
## Getting it

```bat
cd /d C:\projects\lua
git clone https://github.com/rostok/love-upw.git love-uwp
```

Games find the player through their `build-uwp.bat`; keeping it next to the
game folders (`C:\projects\lua\love-uwp`) needs no configuration, otherwise
set `LOVE_UWP` to its path.
## Requirements

- Visual Studio 2022 (17.14 tested) with the **Universal Windows Platform
  development** workload and the **MSVC v143 C++ x64/x86** tools
- Windows SDK `10.0.26100.0` (any SDK from 10.0.19041 up works for packaging)
- CMake 3.24 or newer
- Git for Windows
- PowerShell 7 (`pwsh`) or Windows PowerShell 5.1
- Windows **Developer Mode** enabled, for sideloading test builds

The prebuilt dependencies for each architecture are committed under
[third_party](third_party), so a normal game build needs nothing else.

## Quick start

The player stays generic. Everything specific to one game (name, package
identity, version, icons, splash screen, the `.love` to ship) lives in a
**per-game folder**, normally inside the game's own repository:

```text
C:\projects\lua\love-uwp\        this repository (the player)
C:\games\mygame\
  src\ ...                       the game
  release\mygame.love            its build output
  uwp\                           per-game folder
    player.json
    Assets\*.png                 tiles and splash screen (optional)
    build-uwp.bat                calls love-uwp\scripts\build.ps1
```

1. Write `uwp\player.json` (all keys: [player.json](#playerjson)):

   ```json
   {
     "displayName": "My Game",
     "description": "My LÖVE game",
     "identityName": "MyCompany.MyGame",
     "publisher": "CN=LoveUwpDev",
     "publisherDisplayName": "My Company",
     "version": "1.0.0",
     "backgroundColor": "#101820",
     "game": "../release/mygame.love",
     "assets": "Assets",
     "capabilities": ["codeGeneration"]
   }
   ```

2. Create a test signing certificate once (its subject must equal
   `publisher`). It goes to `.certs\` in this repository and serves every
   game with the same publisher:

   ```powershell
   scripts\new-dev-cert.ps1 -Game C:\games\mygame\uwp
   ```

3. Build signed packages for every architecture in `third_party`:

   ```powershell
   scripts\build.ps1 -Game C:\games\mygame\uwp -OutDir C:\games\mygame\release\uwp -Sign
   ```

   ```text
   MyCompany.MyGame_1.0.0.0_x64.msix
   MyCompany.MyGame_1.0.0.0_x86.msix
   MyCompany.MyGame_1.0.0.0.msixbundle
   Dependencies\x64\Microsoft.VCLibs.x64.14.00.appx
   Dependencies\x86\Microsoft.VCLibs.x86.14.00.appx
   LoveUwpDev.cer
   ```

   Without `-OutDir` the packages go to `dist\<identityName>\` here.

A `build-uwp.bat` in the per-game folder saves typing:

```bat
@echo off
set "HERE=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%..\..\love-uwp\scripts\build.ps1" ^
    -Game "%HERE%." -OutDir "%HERE%..\release\uwp" -Sign %*
```

[games/hello](games/hello) is the example and smoke test that lives here. It
is built from source and reports the renderer, window and pixel sizes, JIT
status and gamepads: `scripts\build.ps1 -Game hello -Sign`.

## player.json

| Key | Required | Meaning |
| --- | --- | --- |
| `displayName` | yes | Name on the Start menu, tiles and title bar |
| `identityName` | yes | Package identity name (letters, digits, `.` and `-`). For the Store, copy it from Partner Center |
| `publisher` | yes | Package publisher. Must equal the signing certificate subject. For the Store, copy it from Partner Center (`CN=<GUID>`) |
| `publisherDisplayName` | yes | Publisher name shown to users |
| `description` | no | App description (defaults to `displayName`) |
| `version` | no | `X.Y.Z`, default `1.0.0`. The package version becomes `X.Y.Z.0`. `build.ps1 -Version` overrides it |
| `backgroundColor` | no | Tile and splash screen background, default `#000000` |
| `game` | no | Path to the `.love` file, relative to the game folder. Default `game.love` |
| `source` | no | A folder with `main.lua` to zip into the `.love` at build time. Used instead of `game` |
| `assets` | no | Folder with replacement images (see below) |
| `capabilities` | no | Package capabilities. Default `["internetClient", "codeGeneration"]` |
| `screenKeyboard` | no | `true` lets `love.keyboard.setTextInput(true)` open the on-screen keyboard (Xbox, touch devices). Default `false`: text input from real keyboards only, no keyboard popping up |
| `minVersion` | no | Minimum Windows build, default `10.0.19041.0` |
| `maxVersionTested` | no | Default `10.0.26100.0` |

`codeGeneration` lets LuaJIT's JIT compiler allocate executable memory; keep
it. Add `internetClientServer` or
`privateNetworkClientServer` only if the game listens for connections (for
example LAN multiplayer with lua-enet).

### Images

The defaults in [package/Assets](package/Assets) are neutral placeholders.
Replace them per game by setting `"assets": "Assets"` and adding any of these
PNGs (missing files fall back to the defaults):

| File | Size |
| --- | --- |
| `StoreLogo.png` | 50 × 50 |
| `Square44x44Logo.png` | 44 × 44 |
| `SmallTile.png` | 71 × 71 |
| `Square150x150Logo.png` | 150 × 150 |
| `WideTile.png` | 310 × 150 |
| `LargeTile.png` | 310 × 310 |
| `SplashScreen.png` | 620 × 300 |

## Testing on this PC

**Fastest: register the build folder** (Developer Mode, no certificate):

```powershell
scripts\build.ps1 -Game mygame -Arch x64
Add-AppxPackage -Register build\mygame-x64\Release\AppxManifest.xml
```

The game appears in the Start menu. Rebuilding while the game is running
fails because its files are in use, so close it first. Use Windows PowerShell
5.1 for `Add-AppxPackage`; in PowerShell 7, first run
`Import-Module Appx -UseWindowsPowerShell`.

**Like an end user: install the signed package.** Trust the test certificate
once per machine (elevated PowerShell), then install:

```powershell
Import-Certificate -FilePath dist\mygame\LoveUwpDev.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople
Add-AppxPackage -Path dist\mygame\MyCompany.MyGame_1.0.0.0.msixbundle -DependencyPath dist\mygame\Dependencies\x64\Microsoft.VCLibs.x64.14.00.appx
```

Remove the app with `Get-AppxPackage MyCompany.MyGame | Remove-AppxPackage`.
This also deletes its saves.

Step-by-step release, certificate, Xbox and Store procedures are in
[PUBLISH-HOWTO.md](PUBLISH-HOWTO.md).

## Saves, logs and crash reports

The package family name is `<identityName>_<publisher hash>`, e.g.
`MyCompany.MyGame_aj7zere7tce2t`. Look it up with
`Get-AppxPackage <identityName> | Select-Object PackageFamilyName`.

| What | Location |
| --- | --- |
| Saves (`love.filesystem.write`, `getSaveDirectory()`) | `%LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalState\<identity>`, where `<identity>` is `t.identity` from the game's `conf.lua` |
| Game's own log files | wherever the game writes them; normally the same save folder |
| `print()` output | not shown anywhere: a UWP app has no console. Write logs to a file in the save folder instead |
| LÖVE error screen | in the window; the text can be copied with Ctrl+C |
| Crashes (native) | Event Viewer → Windows Logs → Application, event ID 1000 (`LovePlayer.exe`, faulting module) |
| Installed game files (read-only) | `C:\Program Files\WindowsApps\<PackageFullName>` for installed packages; `build\<game>-<arch>\Release` for a registered build folder |
| Xbox | Device Portal → File explorer → `LocalAppData\<PackageFamilyName>\LocalState` |

Uninstalling the package deletes `LocalState`, so copy saves away first if
they matter. Upgrading to a newer version keeps them.

For crash dumps, attach
[ProcDump](https://learn.microsoft.com/sysinternals/downloads/procdump) to the
running game (`procdump -ma -e <pid>`) and open the dump with `cdb`/WinDbg from
the Windows SDK.

## Xbox (Dev Mode)

1. Switch the console to Developer Mode. In Dev Home enable remote access to
   **Xbox Device Portal** (`https://<console ip>:11443`).
2. Install with `scripts\xbox.ps1` (uses the Device Portal REST API) or by
   hand in Device Portal (**Add**, the `_x64.msix` plus
   `Dependencies\x64\Microsoft.VCLibs.x64.14.00.appx`).
3. In Dev Home select the game, press the View or Menu button, **View
   details**, and set **App type: Game**. The default type *App* is limited
   to about 1 GB of memory and a share of the CPU and GPU. The setting is kept
   when the package is updated, not when it is uninstalled.

`scripts\xbox.ps1` (console address in `-Device` or `LOVE_UWP_XBOX`):

```powershell
$env:LOVE_UWP_XBOX = '192.168.0.229'
scripts\xbox.ps1 info                                   # console model and OS
scripts\xbox.ps1 install <out>\MyCompany.MyGame_1.0.0.3_x64.msix
scripts\xbox.ps1 launch MyCompany.MyGame               # stop / uninstall likewise
scripts\xbox.ps1 ps Love                               # CPU and memory of the game process
scripts\xbox.ps1 perf                                  # console CPU / memory / GPU
scripts\xbox.ps1 screenshot shot.png
scripts\xbox.ps1 files MyCompany.MyGame \LocalState    # list save files
scripts\xbox.ps1 pull MyCompany.MyGame \LocalState\mygame\log.txt .
```

Development builds for the console:

```powershell
scripts\build.ps1 -Game <game folder> -Arch x64 -Sign -Revision auto -ExtraCapabilities privateNetworkClientServer
```

- `-Revision auto` raises the fourth version number on every build (counter
  in `<game folder>\.dev-revision`), so each build installs as an update and
  keeps saves and the app type. Store builds keep revision 0.
- `-ExtraCapabilities privateNetworkClientServer` lets a debug server inside
  the game accept connections from the LAN; without it UWP network isolation
  blocks incoming connections. Leave it out of release builds.

Dev Mode accepts unsigned or test-signed packages.
## Microsoft Store

1. In [Partner Center](https://partner.microsoft.com/dashboard), reserve the
   app name and open **Product identity**. Copy `Package/Identity/Name`,
   `Package/Identity/Publisher` and `Package/Properties/PublisherDisplayName`
   into `player.json` as `identityName`, `publisher` and
   `publisherDisplayName`.
2. Build the upload package:

   ```powershell
   scripts\build.ps1 -Game mygame -Version 1.0.0 -Store
   ```

   Upload `dist\mygame\<identity>_1.0.0.0.msixupload`. The Store signs the
   package, so no certificate is needed. Each submission needs a higher
   version.
3. Run the Windows App Certification Kit locally before submitting:

   ```powershell
   & "${env:ProgramFiles(x86)}\Windows Kits\10\App Certification Kit\appcert.exe" test -appxpackagepath dist\mygame\MyCompany.MyGame_1.0.0.0_x64.msix -reportoutputpath dist\mygame\wack.xml
   ```

4. Pick the device families in the submission. Windows desktop is open to
   everyone. Publishing a game for **Xbox** through the Store additionally
   requires acceptance into an Xbox publishing program (ID@Xbox); Dev Mode
   sideloading does not.

## Architectures

| Arch | Status |
| --- | --- |
| x64 | Supported. Windows 10/11 PCs and Xbox |
| x86 | Supported. 32-bit Windows 10 |
| ARM64 | Not built yet. The CMake preset exists; needs ARM64 builds of the dependencies (LuaJIT's ARM64 VM in `generate-luajit.ps1`, SDL2, ANGLE, vcpkg `arm64-uwp`) |

`build.ps1 -Arch x64` limits a build to some architectures. By default it
builds every architecture that has dependencies in `third_party`.

## Prebuilt or self-built dependencies

`third_party/<arch>` holds ready-to-use builds of LÖVE, LuaJIT, SDL2, ANGLE
and the runtime DLLs, so there are two ways to work:

1. **Use them as they are** (default). `scriptsuild.ps1` only needs Visual
   Studio and CMake; every build checks the files against the SHA-256 hashes
   in [third_party/deps.json](third_party/deps.json)
   (`scripts\check-deps.ps1`).
2. **Build them yourself** from the sources pinned in `deps.json`:

   ```powershell
   scriptsuild-deps.ps1 -Arch x64
   scriptsuild-deps.ps1 -Arch x86 -SkipAngle   # keep the ANGLE build already in third_party
   ```

   The script replaces `third_party/<arch>`, copies the license texts and
   records the new hashes in `deps.json`. Sources and build trees go to
   `deps\` (ignored by Git). The first ANGLE checkout is about 10 GB; allow
   30 GB of free space and an hour or more.

What is pinned and changed:

- LÖVE 11.5 from [love-xbox-uwp](https://github.com/caorthann-celt/love-xbox-uwp)
  with [love-uwp-player.patch](third_party/patches/love-uwp-player.patch):
  LuaJIT x86 build; drawable size that no longer goes stale when a desktop
  window is resized; `__stdcall` EGL function pointers (x86 crash otherwise);
  enet timers without winmm (not available to UWP apps).
- LuaJIT at the revision of the official LÖVE 11.5 desktop builds
  (2.1.1700008891), so `jit.*` modules and bytecode a game ships match.
- SDL 2.32.10, unmodified.
- vcpkg libraries with the overlay triplets in `third_party/vcpkg-triplets`
  (FreeType built with its UWP file access) and the overlay port in
  `third_party/vcpkg-ports` (OpenAL Soft x86 calling-convention fix).
- ANGLE (D3D11 back end for UWP) built with depot_tools, gn and ninja.

Behind a firewall that blocks outbound traffic by default: Git (and Git for
Windows' `curl.exe`, used for all vcpkg and ANGLE file downloads) must be
allowed, plus `deps\depot_tools\.cipd_client.exe` for the ANGLE tools.

## Repository layout

```text
host/main.cpp              UWP entry point: starts LÖVE on game.love
host/AppxManifest.xml.in   Package manifest template
cmake/PlayerConfig.cmake   Reads games/<game>/player.json
package/Assets/            Default (placeholder) tile and splash images
games/hello/               Example game and smoke test (real games keep their own uwp folder)
scripts/build.ps1          Build, bundle, sign, Store upload
scripts/new-dev-cert.ps1   Self-signed test certificate
scripts/build-deps.ps1     Build third_party/<arch> from source
scripts/check-deps.ps1     Check prebuilt files against deps.json
scripts/xbox.ps1           Xbox Device Portal: install, launch, screenshots, files, processes
scripts/LoveUwp.psm1       Helpers shared by the scripts
third_party/deps.json      Pinned sources and hashes of the prebuilt files
third_party/<arch>/        Prebuilt LÖVE, LuaJIT, SDL2, ANGLE, runtime DLLs
third_party/licenses/      Third-party license texts (shipped in the package)
third_party/patches/       Patch applied to love-xbox-uwp
third_party/vcpkg-*/       vcpkg overlay triplets and ports
```

## Loading progress: `love.progress(text, value)`

A game that loads for seconds on the main thread shows nothing, and Windows
may treat the unresponsive window as hung. The player adds one function the
game can call from inside such loops:

```lua
local progress = love.progress or function() end   -- desktop LÖVE has none

for i, file in ipairs(files) do
    progress("Loading sounds", (i - 1) / #files)
    load(file)
end
```

| `value` | Shown |
| --- | --- |
| 0..1 | text and a progress bar |
| > 1 | text and the number (a step counter) |
| `nil` | text only |

Each call (at most about 30 per second; extra calls return at once) saves the
game's graphics state, draws on the window, presents, pumps window events
and restores the state, so it is safe from `love.load` and with a Canvas
active. Look: set `love.progressStyle = { background = {r, g, b, a}, color =
{r, g, b, a}, font = someFont }` before loading. The game may also replace
`love.progress` with its own function.

## Platform notes for game code

- `love.system.getOS()` returns `"UWP"`.
- Files the game writes go to its LocalState folder. The installed package is
  read-only.
- On Xbox the window is always full screen at the console's resolution. Size
  your rendering with `love.graphics.getDimensions()` and `love.resize`, not
  with fixed numbers from `conf.lua`.
- Rendering is OpenGL ES 3.0 (through ANGLE), so shaders are compiled as
  GLSL ES, like on Android and iOS. Desktop GLSL accepts things GLSL ES
  rejects: give `extern`/`uniform` variables no initial value (set them with
  `Shader:send`), write float literals as `1.0` rather than `1`, and add
  `#pragma language glsl3` to use `gl_FragDepth`.
- The B button on Xbox is delivered to the game as a gamepad button. It does
  not close the app. Gamepad mapping on an actual Xbox is not verified yet.
- Only LÖVE 11.5 APIs are available. Native Lua C modules are not supported;
  pure Lua libraries work.

## License

zlib, like LÖVE: see [LICENSE.md](LICENSE.md), which also lists the
third-party components and their licenses (all permissive; OpenAL Soft is LGPL
and ships as a separate, replaceable DLL). Games packaged with the player keep
their own licenses.
