// love-uwp host executable.
//
// The package carries the game as game.love in its install folder. SDL's
// WinRT backend owns the CoreApplication view; once it is ready it calls
// startLove, which hands LÖVE the archive exactly like
// `love.exe game.love --fused` on the desktop.

#include <SDL.h>

#include <string>

#include <windows.h>

// LÖVE's main() from lovestatic.lib (renamed to SDL_main by SDL_main.h).
extern "C" int SDL_main(int argc, char *argv[]);

namespace
{

int startLove(int, char **)
{
	const char *installDir = SDL_WinRTGetFSPathUTF8(SDL_WINRT_PATH_INSTALLED_LOCATION);
	std::string archive = std::string(installDir ? installDir : ".") + "\\game.love";

	char program[] = "LovePlayer";
	char fused[] = "--fused";
	char *args[] = {program, archive.data(), fused, nullptr};
	return SDL_main(3, args);
}

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
	// Deliver the Xbox B button / Windows "back" request to the game as input
	// instead of letting the system navigate away from the app.
	SDL_SetHint(SDL_HINT_WINRT_HANDLE_BACK_BUTTON, "1");
	return SDL_WinRTRunApp(startLove, nullptr);
}
