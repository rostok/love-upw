# TODO

## Stan (2026-10-13)

- Player działa (x64, x86; Windows 10 19045 i nowsze), licencja zlib. Szczegóły techniczne: DEVELOPMENT.md.
- Repo bez commitów (decyzja: na razie nie commitować). Remote docelowy: <https://github.com/rostok/love-upw.git>.
- Kopia stanu sprzed przepisania (z kodem gen1recomp, GPL — nie używać): C:\projects\lua\love-uwp-backup\pre-cleanroom.bundle.
- Gry trzymają swój folder UWP u siebie (np. C:\projects\lua\schifahren\uwp); tutaj tylko games\hello.

## Do zrobienia

1. Pierwszy commit + push na remote; ewentualnie zmiana nazwy projektu (robocza: love-uwp, exe: LovePlayer).
2. Splash systemowy do pierwszej klatki: opóźnić aktywację okna (SDL/LÖVE), żeby do pierwszego narysowanego kadru
   było widać SplashScreen.png gry; sprawdzić limity czasu aktywacji UWP.
3. Skrypt instalacyjny dla testerów w paczce (import cert + Add-AppxPackage z zależnością), np. install.ps1/.bat w katalogu wyjściowym.
4. Pad na Xboksie: sprawdzić mapowanie pada na konsoli (upstream SDL 2.32 / WGI); jeśli złe — własna poprawka.
5. x86 ~3x wolniejsze przy starcie dużej gry (16 s vs 5 s) — zbadać (GC/pamięć 32-bit, JIT); opisać zalecenie,
   czy publikować x86.
6. PUBLISH-HOWTO.md — doszczegółowić po pierwszym przejściu:
   - Xbox Dev Mode (sekcja 5): aktywacja konsoli, upload przez Device Portal, typ "Game", ścieżki plików;
   - Microsoft Store (sekcja 6): konto Partner Center, product identity, WACK, submission, IARC, privacy policy, flighty;
   - instalacja u testera na czystym PC (sekcja 4) — sprawdzić też podwójny klik w .msixbundle;
   - certyfikat z publicznego CA dla dystrybucji poza Store (sekcja 2), jeśli potrzebne.
7. Windows App Certification Kit (appcert.exe) na .msix — czy player przechodzi testy Store.
8. Xbox Dev Mode: test przez Device Portal.
9. `love.progress`: opcja w player.json na domyślny styl (kolory/czcionka), żeby gra nie musiała ustawiać `love.progressStyle`.
10. Opcjonalnie: poprosić autora love-xbox-uwp (Caorthann) o jawne potwierdzenie licencji zlib dla zmian w forku.
11. ARM64 (furtka): LuaJIT arm64 w generate-luajit.ps1 (love-src), SDL2/ANGLE/vcpkg arm64-uwp.
