# vcpkg's community arm64-uwp triplet plus per-port fixes for this player.
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)

set(VCPKG_CMAKE_SYSTEM_NAME WindowsStore)
set(VCPKG_CMAKE_SYSTEM_VERSION 10.0)

# FreeType only uses its CreateFile2-based file access shim for UWP when
# _WINRT_DLL is defined; otherwise it calls CreateFileA, which UWP headers
# don't declare (and which fails to link on x86).
if(PORT STREQUAL "freetype")
    set(VCPKG_C_FLAGS "/D_WINRT_DLL")
    set(VCPKG_CXX_FLAGS "/D_WINRT_DLL")
endif()
