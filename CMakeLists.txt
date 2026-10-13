# love-uwp: packages one LÖVE game as a UWP app (MSIX).
#
#   cmake --preset x64 -DGAME_DIR=games/hello
#   cmake --build --preset x64
#
# scripts/build.ps1 drives this for every architecture and collects the output.

cmake_minimum_required(VERSION 3.24)
project(LovePlayer LANGUAGES CXX RC)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "WindowsStore")
    message(FATAL_ERROR "Use one of the presets (x64, x86, arm64); they target WindowsStore.")
endif()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(PlayerConfig)

# --- Which game -------------------------------------------------------------

set(GAME_DIR "" CACHE PATH "Folder with player.json (e.g. games/hello)")
set(GAME_VERSION "" CACHE STRING "Override player.json \"version\" (X.Y.Z)")
set(GAME_LOVE_OVERRIDE "" CACHE FILEPATH "Package this .love instead of the one in player.json")
if(NOT GAME_DIR)
    message(FATAL_ERROR "Pass -DGAME_DIR=games/<game>")
endif()
cmake_path(ABSOLUTE_PATH GAME_DIR BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" OUTPUT_VARIABLE GAME_DIR)

love_uwp_read_config("${GAME_DIR}" "${GAME_VERSION}")
if(GAME_LOVE_OVERRIDE)
    set(GAME_ARCHIVE "${GAME_LOVE_OVERRIDE}")
endif()
if(NOT EXISTS "${GAME_ARCHIVE}")
    message(FATAL_ERROR "Game archive not found: ${GAME_ARCHIVE}")
endif()

# --- Prebuilt dependencies for this architecture ----------------------------

string(TOLOWER "${CMAKE_VS_PLATFORM_NAME}" vs_platform)
if(vs_platform STREQUAL "win32")
    set(ARCH x86)
elseif(vs_platform STREQUAL "x64" OR vs_platform STREQUAL "arm64")
    set(ARCH ${vs_platform})
else()
    message(FATAL_ERROR "Unsupported platform '${CMAKE_VS_PLATFORM_NAME}'")
endif()

set(DEPS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/${ARCH}")
set(LINK_LIBS
    "${DEPS}/love/lib/lovestatic.lib"
    "${DEPS}/love/lib/liblove.lib"
    "${DEPS}/love/lib/lua51.lib"
    "${DEPS}/sdl2/lib/SDL2.lib")
file(GLOB RUNTIME_DLLS CONFIGURE_DEPENDS
    "${DEPS}/love/bin/*.dll"
    "${DEPS}/sdl2/bin/*.dll"
    "${DEPS}/angle/bin/*.dll"
    "${DEPS}/runtime/bin/*.dll")
foreach(required IN LISTS LINK_LIBS ITEMS
        "${DEPS}/sdl2/include/SDL2/SDL.h"
        "${DEPS}/angle/bin/libGLESv2.dll"
        "${DEPS}/love/bin/love.dll")
    if(NOT EXISTS "${required}")
        message(FATAL_ERROR "Missing ${required}\nBuild the ${ARCH} dependencies: scripts\\build-deps.ps1 -Arch ${ARCH}")
    endif()
endforeach()

# --- Manifest and game payload ----------------------------------------------

configure_file(host/AppxManifest.xml.in "${CMAKE_CURRENT_BINARY_DIR}/Package.appxmanifest" @ONLY)

set(STAGED_GAME "${CMAKE_CURRENT_BINARY_DIR}/game.love")
add_custom_command(
    OUTPUT "${STAGED_GAME}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${GAME_ARCHIVE}" "${STAGED_GAME}"
    DEPENDS "${GAME_ARCHIVE}"
    COMMENT "Staging game.love"
    VERBATIM)

add_custom_target(check_deps
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass
        -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/check-deps.ps1" -Arch ${ARCH}
    COMMENT "Checking ${ARCH} dependency hashes"
    VERBATIM)

# --- Host executable --------------------------------------------------------

add_executable(LovePlayer WIN32 host/main.cpp host/resources.rc "${STAGED_GAME}")
add_dependencies(LovePlayer check_deps)
target_include_directories(LovePlayer PRIVATE "${DEPS}/sdl2/include/SDL2")
target_link_libraries(LovePlayer PRIVATE ${LINK_LIBS} WindowsApp.lib)
set_target_properties(LovePlayer PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    VS_GLOBAL_DefaultLanguage "en-US"
    VS_SDK_REFERENCES "Microsoft.VCLibs, Version=14.0"
    # Without this MSBuild writes the SDK version into MinVersion and the
    # package would refuse to install on older Windows 10 builds.
    VS_WINDOWS_TARGET_PLATFORM_MIN_VERSION "${APPX_MIN_VERSION}")

# --- Package content ----------------------------------------------------------

function(love_uwp_deploy folder)
    set_source_files_properties(${ARGN} PROPERTIES
        VS_DEPLOYMENT_CONTENT TRUE
        VS_DEPLOYMENT_LOCATION "${folder}"
        VS_COPY_TO_OUT_DIR Always)
    target_sources(LovePlayer PRIVATE ${ARGN})
endfunction()

set(MANIFEST "${CMAKE_CURRENT_BINARY_DIR}/Package.appxmanifest")
set_source_files_properties("${MANIFEST}" "${STAGED_GAME}" PROPERTIES GENERATED TRUE)
love_uwp_deploy("." "${MANIFEST}" "${STAGED_GAME}" ${RUNTIME_DLLS})

set(TILE_IMAGES "")
foreach(image StoreLogo Square44x44Logo SmallTile Square150x150Logo WideTile LargeTile SplashScreen)
    if(GAME_ASSETS_DIR AND EXISTS "${GAME_ASSETS_DIR}/${image}.png")
        list(APPEND TILE_IMAGES "${GAME_ASSETS_DIR}/${image}.png")
    else()
        list(APPEND TILE_IMAGES "${CMAKE_CURRENT_SOURCE_DIR}/package/Assets/${image}.png")
    endif()
endforeach()
love_uwp_deploy("Assets" ${TILE_IMAGES})

file(GLOB LICENSE_TEXTS CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/licenses/*.txt")
list(APPEND LICENSE_TEXTS "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE.md")
set_source_files_properties(${LICENSE_TEXTS} PROPERTIES VS_TOOL_OVERRIDE "Content")
love_uwp_deploy("licenses" ${LICENSE_TEXTS})

message(STATUS "${APPX_DISPLAY_NAME} ${APPX_VERSION} (${ARCH}) from ${GAME_ARCHIVE}")
