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
8. Xbox Dev Mode (Xbox One S): Schifahren działa, ale bardzo wolno (1080p kilka fps, 2160p crash).
   Log z konsoli vs PC: dźwięki 20,1 s vs 3,1 s (kod C, 6,5x), mapa 36,9 s vs 4,5 s, pathfinder (FFI) 1,38 s vs 0,21 s,
   INIT 45 s vs 5,3 s — wszystko ~6,5–8,5x, czyli JIT działa, ogranicza CPU One S (Jaguar 1,75 GHz).
   Do sprawdzenia: typ aplikacji w Dev Home = Game (App ma ~1 GB RAM i ograniczone CPU/GPU); test games\hello
   na konsoli (JIT 'trace compiled', pad); porównanie na Xbox Series S/X.
8a. Limit rozdzielczości rysowania (dla Xboksa w 2160p i słabego GPU):
   - własna łatka SDL (SDL_winrtvideo.cpp, tworzenie powierzchni EGL ~l.668): zamiast gołego CoreWindow przekazać
     do eglCreateWindowSurface PropertySet z EGLNativeWindowTypeProperty + EGLRenderResolutionScaleProperty
     = maxHeight / wysokość okna, gdy okno jest wyższe niż limit (hint SDL, np. "LOVE_UWP_MAX_RENDER_HEIGHT");
   - player.json `"maxRenderHeight"` (np. 1080); host ustawia hint; domyślnie 1080 tylko na Xboksie
     (SDL_WinRTGetDeviceFamily), na PC bez limitu;
   - łatka LÖVE (getSurfacePixelSize / shouldReannounceSurfaceSize) powinna przyjąć mniejszy bufor (DPI scale < 1) —
     sprawdzić współrzędne myszy i układ;
   - ograniczenie: ANGLE ustala skalę przy tworzeniu powierzchni (na PC po resize zostaje stara skala);
   - test na PC z małym limitem (np. 300 px w games\hello), potem build-deps x64/x86 (SDL), paczka Schifahren na Xbox;
   - opisać w README (player.json) i DEVELOPMENT.md (nowa łatka SDL).
   Nie przyspieszy logiki gry — tylko pamięć/GPU (crash w 2160p).
9. `love.progress`: opcja w player.json na domyślny styl (kolory/czcionka), żeby gra nie musiała ustawiać `love.progressStyle`.
10. Opcjonalnie: poprosić autora love-xbox-uwp (Caorthann) o jawne potwierdzenie licencji zlib dla zmian w forku.
11. ARM64 (furtka): LuaJIT arm64 w generate-luajit.ps1 (love-src), SDL2/ANGLE/vcpkg arm64-uwp.
