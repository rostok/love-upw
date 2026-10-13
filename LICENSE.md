# License

## love-uwp

Copyright (c) 2026 rostok

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software in a
   product, an acknowledgment in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.

(zlib license, the same license as LÖVE.)

Games packaged with this player are not covered by this license; they keep
their own.

## Origin

- The LÖVE engine is built from
  [love-xbox-uwp](https://github.com/caorthann-celt/love-xbox-uwp), a fork of
  LÖVE 11.5 that adds UWP support. That repository ships LÖVE's own license
  file (zlib) and no separate license for the fork's changes, so they are
  taken to be under the same zlib license. This project applies its own patch
  on top (`third_party/patches/love-uwp-player.patch`, zlib as part of this
  project).
- Everything else here (host executable, CMake project, manifest template,
  build and packaging scripts, vcpkg overlays, patches, tests and
  documentation) was written independently for this project, in clean-room
  fashion: implemented from functional requirements and public documentation
  (LÖVE, SDL, CMake, MSIX/UWP, vcpkg, ANGLE), without copying third-party
  code.

## Third-party components

The prebuilt files in `third_party/<arch>` and the packaged player contain
the components below. Their full license texts are in
[third_party/licenses](third_party/licenses) and are installed into every
package under `licenses\`. Exact revisions are in
[third_party/deps.json](third_party/deps.json).

| Component | License |
| --- | --- |
| LÖVE 11.5 (via love-xbox-uwp) and the libraries bundled in it (Box2D, ENet, glslang, LuaSocket, PhysFS, …; see `love.txt`) | zlib and the licenses listed in `love.txt` |
| LuaJIT 2.1 | MIT |
| SDL 2.32 | zlib |
| ANGLE | BSD-3-Clause |
| FreeType | FreeType License (BSD-style) |
| libpng | libpng License |
| zlib | zlib |
| bzip2 | bzip2 License (BSD-style) |
| Brotli | MIT |
| fmt | MIT |
| libogg, libvorbis, libtheora | BSD-3-Clause |
| OpenAL Soft | LGPL-2.1-or-later |
| `d3dcompiler_47.dll` | Microsoft Windows SDK redistributable |

OpenAL Soft is LGPL. It is shipped as a separate, replaceable DLL
(`OpenAL32.dll`); its source is available at the vcpkg revision pinned in
`third_party/deps.json` (port `openal-soft`, with the overlay patch in
`third_party/vcpkg-ports/openal-soft`).
