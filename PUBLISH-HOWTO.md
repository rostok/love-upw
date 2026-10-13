# Publishing how-to

Every step from a game's `.love` to a package on a tester's PC, an Xbox in
Dev Mode, or the Microsoft Store.

Each section is marked:

- **Verified**: done and checked on the build PC (Windows 10 19045, VS 2022 17.14).
- **Not verified yet**: based on Microsoft documentation and common practice,
  to be confirmed on the first real run (tracked in [TODO.md](TODO.md)).

Examples use a game folder `C:\games\mygame\uwp` (with `player.json`, see the README) and the package identity `MyCompany.MyGame`. Run every command from the love-uwp repository root in
PowerShell.

---

## 1. Package and version numbers  *(verified)*

| What | Where | Format |
| --- | --- | --- |
| Game package version | `version` in `games\<game>\player.json`, or `build.ps1 -Version` (overrides it) | `X.Y.Z` |
| MSIX package version | generated: `X.Y.Z.0` | the fourth number is reserved by the Store and is always `0` |
| Player (engine) version | the Git commit of this repository plus `third_party\deps.json` | — |

Rules:

- Each number must be ≤ 65535.
- A package can only be **upgraded** to a higher version. Windows refuses to
  install a lower or equal version over an installed one (uninstall first when
  testing a downgrade).
- The Store requires every new submission to have a **higher version than any
  package already submitted** for that product.

Bumping the version for a release:

1. Set `"version": "1.0.1"` in `games\<game>\player.json` (keep it in step with
   the game's own version string if it shows one).
2. Build (section 3). The version is written into the manifest and the file
   names, e.g. `MyCompany.MyGame_1.0.1.0_x64.msix`.

For a one-off build with a different version leave `player.json` alone and
pass `-Version 1.0.1` to `build.ps1`.

Updating the **player** itself (LÖVE patch, SDL, ANGLE, …) does not change a
game's version. Rebuild the game with a bumped game version to ship it. Record
player changes in Git (commit message) and, for dependency updates, in
`third_party\deps.json` (written by `scripts\build-deps.ps1`).

## 2. Certificates  *(verified)*

| Case | Certificate |
| --- | --- |
| Local testing by registering the build folder | none (needs Windows Developer Mode) |
| Sideloading to testers / own PCs | self-signed test certificate (`scripts\new-dev-cert.ps1`) |
| Xbox Dev Mode | none or the test certificate |
| Microsoft Store | none: upload unsigned, the Store signs the package |

The package's `Publisher` (`publisher` in `player.json`) must be **exactly**
the certificate subject, e.g. `CN=LoveUwpDev`. `build.ps1 -Sign` checks this.

### Create the test certificate

```powershell
scripts\new-dev-cert.ps1 -Game C:\games\mygame\uwp
```

- Writes `.certs\LoveUwpDev.pfx` (private key, password `love-uwp-dev`) and
  `.certs\LoveUwpDev.cer` (public part). `.certs\` is ignored by Git. Back
  up the `.pfx`: packages signed with a new certificate do not update packages
  signed with the old one without first uninstalling them on testers' machines.
- Valid for 3 years (`-Years` to change). Renewing means generating a new
  certificate with the same subject: delete the old `.pfx`/`.cer` and run the
  script again, then distribute the new `.cer`.
- One certificate can sign any number of games with the same `publisher`.

### Trust the certificate on a machine (once per machine, elevated PowerShell)

```powershell
Import-Certificate -FilePath LoveUwpDev.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople
```

To remove it later:

```powershell
Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object Subject -eq 'CN=LoveUwpDev' | Remove-Item
```

Distributing outside the Store to people who should not have to trust a
self-signed certificate needs a code-signing certificate from a public CA.
*(Not verified yet.)*

## 3. Building packages  *(verified)*

| Goal | Command | Output in `dist\<identity>\` (or `-OutDir`) |
| --- | --- | --- |
| Test build, all architectures, signed | `scripts\build.ps1 -Game C:\games\mygame\uwp -Sign` | `*_x64.msix`, `*_x86.msix`, `*.msixbundle`, `Dependencies\`, `LoveUwpDev.cer` |
| x64 only | `scripts\build.ps1 -Game C:\games\mygame\uwp -Arch x64 -Sign` | `*_x64.msix`, bundle, `Dependencies\x64\` |
| Store upload | `scripts\build.ps1 -Game C:\games\mygame\uwp -Store` | adds `*.msixupload` (unsigned bundle) |
| Both at once | `scripts\build.ps1 -Game C:\games\mygame\uwp -Sign -Store` | the `.msixupload` stays unsigned; the rest is signed |

Add `-OutDir <folder>` to put the packages elsewhere, e.g. into the game's own
release folder. Earlier packages of the same game in the output folder are
replaced; other files there are left alone.

The `.love` comes from `game` in `player.json` (a path relative to the
`player.json` folder, e.g. `../release/mygame.love`), or is zipped from
`source`. Rebuild the game's `.love` with its own build step first.

A game normally keeps its UWP folder and a small `build-uwp.bat` that calls
`build.ps1` in its own repository; see "Quick start" in the README.

Before a release build, go through the checklist in section 7.

## 4. Installing on a Windows PC

### This PC, during development  *(verified)*

```powershell
scripts\build.ps1 -Game C:\games\mygame\uwp -Arch x64
powershell -Command "Add-AppxPackage -Register build\MyCompany.MyGame-x64\Release\AppxManifest.xml"
```

Close the game before rebuilding, since the registered build folder is in use.

### A tester's PC  *(verified on the build PC)*

Hand over the contents of `<out>\` (at least the `.msixbundle` or the
`_x64.msix`, `Dependencies\` and `LoveUwpDev.cer`). On the tester's PC:

1. Trust `LoveUwpDev.cer` (section 2), elevated.
2. Install:

   ```powershell
   Add-AppxPackage -Path MyCompany.MyGame_1.0.0.0.msixbundle `
       -DependencyPath Dependencies\x64\Microsoft.VCLibs.x64.14.00.appx
   ```

   Double-clicking the `.msixbundle` (App Installer) also works once the
   certificate is trusted.
3. Uninstall: `Get-AppxPackage MyCompany.MyGame | Remove-AppxPackage`.

A one-click install script for testers is a TODO item.

## 5. Xbox in Dev Mode  *(not verified yet)*

1. **Activate Dev Mode** on the console: install *Xbox Dev Mode* from the
   Store on the console and register it with a Microsoft Partner Center
   developer account. Restart into Dev Mode from Dev Home.
2. In **Dev Home**, enable *Remote Access* (Xbox Device Portal) and set a
   username and password. The console shows its address, e.g.
   `https://192.168.1.50:11443`.
3. Build x64 (Xbox One and Series are x64):
   `scripts\build.ps1 -Game C:\games\mygame\uwp -Arch x64`. Signing is optional in Dev
   Mode.
4. In the browser open the Device Portal → **Home → My games & apps → Add**:
   - upload `MyCompany.MyGame_1.0.0.0_x64.msix`;
   - on the next page add the dependency
     `Dependencies\x64\Microsoft.VCLibs.x64.14.00.appx`;
   - start the installation.
5. In Dev Home, select the app → **View details** → set **App type: Game**,
   so it gets game resources (GPU and memory) rather than app limits.
6. Run it from Dev Home. Saves and logs are reachable through Device Portal →
   **File explorer** → `LocalAppData\<PackageFamilyName>\LocalState`.

Notes:
- On Xbox the window is always full screen; the game gets `love.resize` with
  the TV resolution.
- The gamepad should arrive as an SDL game controller with the standard
  layout (upstream SDL via Windows.Gaming.Input). Check the mapping on the
  console. The B button is passed to the game.

## 6. Microsoft Store  *(not verified yet)*

### One-time setup

1. Create a developer account in
   [Partner Center](https://partner.microsoft.com/dashboard) (individual or
   company; check the current registration fee and verification steps).
2. **Apps and games → New product → MSIX or PWA app**, reserve the name.
3. Open **Product management → Product identity** and copy:
   - `Package/Identity/Name` → `identityName`
   - `Package/Identity/Publisher` → `publisher` (looks like `CN=XXXXXXXX-...`)
   - `Package/Properties/PublisherDisplayName` → `publisherDisplayName`

   into `games\<game>\player.json`. Use the same values in every later
   release. After this change, test builds need a test certificate with the
   new subject (`scripts\new-dev-cert.ps1 -Game <game>` creates one for the
   new publisher).

### Each release

1. Bump the version (section 1).
2. Go through the release checklist (section 7).
3. Build: `scripts\build.ps1 -Game <game> -Store`.
4. Run the Windows App Certification Kit on the x64 and x86 packages
   (elevated; it installs and launches the app):

   ```powershell
   & "${env:ProgramFiles(x86)}\Windows Kits\10\App Certification Kit\appcert.exe" test `
       -appxpackagepath <out>\<identity>_X.Y.Z.0_x64.msix -reportoutputpath <out>\wack-x64.xml
   ```

   Fix every *failed* test before submitting.
5. In Partner Center create a **submission**:
   - **Packages**: upload `<out>\<identity>_X.Y.Z.0.msixupload`; choose
     device families (Windows Desktop; Xbox only with an Xbox publishing
     arrangement, see below).
   - **Pricing and availability**, **Properties** (category: Games),
     **Age ratings** (IARC questionnaire), **Store listings** (description,
     screenshots, logo; at least one screenshot is required).
   - A **privacy policy** URL is required when the app declares capabilities
     such as `internetClient`. Without network use, drop that capability.
6. Submit. Certification typically takes from hours to a few days. Fix
   anything the report lists and resubmit with a higher version.

Optional: **package flights** in Partner Center deliver a build to a list of
testers through the Store before the public release.

### Xbox through the Store

Publishing a game to Xbox consoles through the Store is not open to every
developer account; it requires an Xbox publishing program (ID@Xbox). Dev Mode
sideloading (section 5) does not.

## 7. Release checklist

- [ ] Version bumped (section 1).
- [ ] Debug features off in the game: developer console, debug server and its
      open network ports.
- [ ] Capabilities in `player.json` reduced to what the game uses
      (`internetClient` only if it really needs the network; keep
      `codeGeneration` for the LuaJIT JIT).
- [ ] Third-party notices reachable: the package ships them under
      `licenses\`; mentioning LÖVE and the libraries in the game's credits is
      good practice (zlib/MIT/BSD require the notices to travel with the
      binaries, which the package already does).
- [ ] Game images in `games\<game>\Assets` (`"assets": "Assets"` in
      `player.json`) instead of the placeholders.
- [ ] Shaders GLSL ES compatible (README, "Platform notes for game code").
- [ ] Tested: installed signed package on a clean PC (section 4); x86 if
      shipped; Xbox if targeted.
- [ ] WACK passed (Store).

## 8. Saves and logs

See the README, section "Saves, logs and crash reports".
