# Developing love-uwp

How the player works inside, why each patch exists, and how to change,
rebuild, test and debug it. Usage (building games) is in the
[README](README.md); release procedures in [PUBLISH-HOWTO.md](PUBLISH-HOWTO.md).

## 1. How a package starts

```text
LovePlayer.exe (host/main.cpp)
  wWinMain
    SDL_SetHint(SDL_HINT_WINRT_HANDLE_BACK_BUTTON, "1")
    SDL_WinRTRunApp(startLove)            SDL creates the CoreApplication view
      startLove                            runs on the CoreWindow (UI) thread
        path = SDL_WinRTGetFSPathUTF8(INSTALLED_LOCATION) + "\game.love"
        SDL_main("LovePlayer", path, "--fused")   = LÖVE's main() (lovestatic.lib)
          love.dll: boot.lua, conf.lua, window (SDL + EGL/ANGLE), main.lua, love.run
```

- Everything Lua runs on the UI thread. Window events are only processed
  when the game pumps events (`love.event.pump`, normally once per frame in
  `love.run`). Long work without pumping leaves the window unresponsive.
- The window is activated (system splash screen dismissed) when SDL handles
  the app's `Activated` event, i.e. at the first event pump.
- Rendering: LÖVE's OpenGL ES 3 renderer → ANGLE (`libEGL.dll`,
  `libGLESv2.dll`) → Direct3D 11 swap chain on the CoreWindow.
  `d3dcompiler_47.dll` compiles ANGLE's HLSL.
- Audio: OpenAL Soft (WASAPI backend for UWP). Input: SDL (keyboard, mouse,
  Windows.Gaming.Input gamepads).
- Saves: PhysFS → `ApplicationData.LocalFolder` (`LocalState`).
- `host/resources.rc` links `host/blank.cur` as cursor resource 5000; SDL
  uses it for `SDL_ShowCursor(0)`. Without it SDL sets `PointerCursor = null`,
  which hides the cursor too eagerly and stops mouse-move events.

## 2. Build system

| Piece | Role |
| --- | --- |
| `CMakeLists.txt` | the host project for one game (`-DGAME_DIR`), WindowsStore target, VS generator; links `third_party/<arch>`, deploys DLLs, `game.love`, images and licences into the package |
| `cmake/PlayerConfig.cmake` | reads `player.json`, validates it, produces the `APPX_*` variables |
| `host/AppxManifest.xml.in` | manifest template |
| `scripts/build.ps1` | per-architecture CMake configure + build, picks the `.msix` that the VS packaging step produced, bundles (`makeappx`), signs (`signtool`), writes `.msixupload` |
| `scripts/build-deps.ps1` | rebuilds `third_party/<arch>` from the pins in `third_party/deps.json` |
| `scripts/check-deps.ps1` | verifies `third_party/<arch>` against the hashes (run before every package build) |
| `scripts/LoveUwp.psm1` | shared helpers |

Points that matter:

- **MinVersion.** MSBuild writes `TargetPlatformMinVersion` into the
  manifest's `MinVersion`; without `VS_WINDOWS_TARGET_PLATFORM_MIN_VERSION`
  it uses the SDK version (10.0.26100), and the package would not install on
  Windows 10. Check `MinVersion="10.0.19041.0"` in a built package.
- **PhoneIdentity** is required by the VS packaging targets (error APPX1673);
  the id is a UUID derived from the identity name.
- **Application Id** is `Game`: AUMID `<PackageFamilyName>!Game`.
- **Platform names.** VS calls x86 `Win32`; the produced file is
  `LovePlayer_<ver>_Win32.msix`. `build.ps1` renames it to `<identity>_<ver>_x86.msix`.
- **Stale packaging.** If files in `build/<identity>-<arch>/Release` are
  edited by hand (e.g. the generated `AppxManifest.xml`), MSBuild may package
  them instead of regenerating. Delete the build folder after such
  experiments.
- **Bundles** require identical `<Application>` data in all architectures.
- **PowerShell quirks** (handled in the scripts): quote `"-DX=10.0"` or
  PowerShell splits it at the dot; never splat a single destructured string
  (it splats characters); Appx cmdlets need Windows PowerShell 5.1
  (`powershell.exe`), not pwsh 7.

## 3. Dependencies and patches

Pins: `third_party/deps.json` (`sources`). Built results and hashes:
`binaries.<arch>`.

### LÖVE patch (`third_party/patches/love-uwp-player.patch`)

Applied to love-xbox-uwp (`deps/love-src`):

| File | Change | Why |
| --- | --- | --- |
| `extra/cmake/LuaJITUWP.cmake`, `extra/uwp/generate-luajit.ps1` | x86 LuaJIT: `vm_x86.dasc`, no `P64`, host tools built with the x86 compiler and libs | the fork supported x64 only; LuaJIT's build tools must have the target's pointer size |
| `src/modules/window/sdl/UWPEGL.cpp/.h`, `Window.cpp` | drawable size = SDL window size (already physical pixels on WinRT); after `SDL_GL_SwapWindow` the EGL surface size is checked once per size and a resize re-announced if it differs | ANGLE resizes the CoreWindow swap chain lazily (at the next present), so the EGL size read during a resize is stale: wrong DPI scale (1.5), cropped image, missing text |
| `UWPEGL.cpp` | EGL function pointers declared `__stdcall` | EGL is `EGLAPIENTRY` = stdcall on Windows; cdecl pointers corrupt the stack on x86 (crash in love.dll right after start) |
| `src/libraries/enet/libenet/win32.c` | `timeGetTime`/`timeBeginPeriod` → `GetTickCount64`/no-op on UWP | winmm is not available to UWP apps (link error on x86, invisible on x64) |
| `src/modules/love/love.cpp` | `love.progress(text, value)` (Lua chunk) | loading display; see README. It must `push("all")` + `reset()` before `love.event.pump`, because pump fails while a Canvas is active |

LuaJIT is pinned to `43d0a191` (2.1.1700008891), the revision of official
LÖVE 11.5 desktop builds, so games that ship `jit/*.lua` (e.g. the profiler,
whose `vmdef.lua` checks the exact version) and bytecode keep working. On x64
LuaJIT is built with GC64 (no 2 GB Lua heap limit); x86 is a 32-bit process
with 2–4 GB of address space for everything.

### vcpkg overlays

- `third_party/vcpkg-triplets/*-uwp.cmake`: FreeType with `/D_WINRT_DLL`,
  which enables its `CreateFile2` file access for UWP (otherwise `CreateFileA`
  is undeclared; links by accident on x64, fails on x86).
- `third_party/vcpkg-ports/openal-soft`: `uwp-x86-stdcall.diff` adds
  `STDMETHODIMP` to `ActivateCompleted` (x86 calling convention).

### SDL

SDL 2.32.10, unmodified. The Xbox gamepad mapping on a console is not verified
yet (TODO).

### Changing the LÖVE patch

```powershell
scripts\build-deps.ps1 -Arch x64 -SkipAngle      # creates deps\love-src with the patch applied
# edit files in deps\love-src
cd deps\love-src
git diff --ignore-cr-at-eol -- <every patched file> > ..\..\third_party\patches\love-uwp-player.patch
git stash; git apply --check --ignore-whitespace ..\..\third_party\patches\love-uwp-player.patch; git stash pop
cd ..\..
scripts\build-deps.ps1 -Arch x64 -SkipAngle; scripts\build-deps.ps1 -Arch x86 -SkipAngle
```

- love-xbox-uwp has mixed CRLF/LF line endings. Checkouts use
  `core.autocrlf=false`; the patch is made with `--ignore-cr-at-eol` and
  applied with `--ignore-whitespace`. A plain `git diff` produces whole-file
  diffs.
- List *all* patched files in the `git diff` command, or earlier changes drop
  out of the patch.
- `build-deps.ps1` records the applied patch hash in
  `deps\love-src\.love-uwp-patch`; a changed patch resets the checkout and
  re-applies it.
- `.patch` and `.diff` files are `-text` in `.gitattributes`: they must stay
  byte-identical.

### Network during `build-deps.ps1`

All downloads go through Git and Git for Windows' `curl.exe` (vcpkg via
`X_VCPKG_ASSET_SOURCES`, ANGLE's `rc.exe` from Google Storage). ANGLE is
synced with `gclient sync --nohooks`, so depot_tools' Python needs no network;
only `deps\depot_tools\.cipd_client.exe` must be allowed (it fetches gn, ninja
and Python). On the build PC the firewall blocks outbound traffic by default,
`vcpkg.exe` and `System32\curl.exe` are blocked, and IPv6 is broken; the
system curl fails, Git's curl works. Parallel `gclient` clones of
chromium.googlesource.com fail now and then; `--jobs 4` and re-running resume.

## 4. Testing

- `games/hello`: diagnostics game. Writes `diag.txt` to its save folder
  (renderer, window and pixel sizes, DPI scale, JIT, font and canvas checks,
  resize events with frame numbers) and shows a 3 s `love.progress` demo.
- Local install of a build folder (no certificate):
  `powershell -Command "Add-AppxPackage -Register build\<identity>-<arch>\Release\AppxManifest.xml"`.
  Remove the package first when its Application Id changed. Close the game
  before rebuilding (its files are in use).
- Start: `Start-Process "shell:AppsFolder\<PackageFamilyName>!Game"`.
- The session must show a desktop. Over Remote Desktop with the RDP window
  minimized (or a locked screen) nothing is rendered, and UWP activation
  crashes in `twinapi.appcore.dll` (`0xc000027b`) or the app is suspended.
  Screen capture then fails with "handle is invalid".
- An app launched while another window keeps the foreground starts suspended
  until its window is brought to the front. `PrintWindow(hwnd, dc, 2)` on the
  `ApplicationFrameHost` window titled with the display name captures it
  without changing focus.
- Faking key presses (e.g. ALT to steal the foreground) can make games react;
  avoid it in tests.
- A game that blocks for seconds in `love.load` shows an empty window; users
  close it as hung (event 1002 "stopped interacting with Windows"). Use
  `love.progress`.

## 5. Debugging crashes

- Event Viewer → Application: event 1000 (crash, faulting module + offset),
  1002 (hang, closed).
- Dump: `procdump -accepteula -ma -e <pid> <folder>` (attach by PID; `-w`
  sees two processes during UWP start). First-chance `E24C4A02` exceptions are
  LuaJIT's internal error unwinding (normal), so do not use `-e 1`.
- Analyse: `"C:\Program Files (x86)\Windows Kits\10\Debuggers\<x86|x64>\cdb.exe" -z <dump> -c ".ecxr;kv 30;qd"`;
  `!analyze -v` for stowed (WinRT) exceptions.
- Symbols for LÖVE: `cmake --build deps\build\<arch>\love --config RelWithDebInfo`
  (output named `liblove.dll` + `.pdb`; copy as `love.dll` into the build
  folder layout for the test).

## 6. Licensing history

The first version of this player was derived from the GPL-licensed UWP port
of another project. Before publication it was replaced completely: the host,
CMake project, manifest, scripts and dependency manifest were rewritten
independently, the SDL patch from that project was dropped, and every binary
in `third_party` was rebuilt from upstream sources by `build-deps.ps1`. The
project is zlib licensed (see [LICENSE.md](LICENSE.md)). Do not bring code
from that project back.
