# MEMORY

- Firewall on build PC: outbound default Block. Allowed: git, pwsh, Git/choco curl, `.cipd_client.exe`. Blocked: vcpkg.exe, System32 curl.exe. IPv6 broken.
- SDL2 WinRT reports window size in physical pixels (`WINRT_DIPS_TO_PHYSICAL_PIXELS`), not DIPs.
- ANGLE CoreWindow resizes swap chain lazily on present → EGL size stale right after resize.
- LÖVE repo (love-xbox-uwp) has mixed CRLF/LF; patches generated with `git diff --ignore-cr-at-eol`, applied with `--ignore-whitespace`; clones use `core.autocrlf=false`.
- PowerShell: quote `-DX=10.0` args (otherwise split); `Invoke-Exe` must not destructure single args.
- Appx cmdlets need Windows PowerShell 5.1 (`powershell.exe`), not pwsh 7.
- Testing launch: app gets suspended when it starts without foreground; bring ApplicationFrameHost window to front.
- Test cert: `.certs\LoveUwpDev.pfx`, password `love-uwp-dev`, subject `CN=LoveUwpDev`.
- Remote: https://github.com/rostok/love-upw.git. User does not want commits yet (stash-like only). Backup of GPL-era state: C:\projects\lua\love-uwp-backup\pre-cleanroom.bundle.
- License: zlib; everything rewritten independently of gen1recomp (do not reintroduce gen1recomp code).
- App Id in manifest is "Game" (AUMID <PFN>!Game).
- Local package family suffix: `_aj7zere7tce2t` (hello: LoveUwp.Hello, schifahren: Rostok.Schifahren, UWP folder C:\projects\lua\schifahren\uwp).
- UWP apps crash on activation (twinapi.appcore, 0xc000027b) when the RDP window is minimized (no rendered desktop). Test only with a visible session. Screen capture fails with "handle is invalid" in that state.
- run-app.ps1 test harness (ALT keypress + SetForegroundWindow) can make a game quit; launch with Start-Process shell:AppsFolder\<PFN>!Game and screenshot the ApplicationFrameHost window instead.
