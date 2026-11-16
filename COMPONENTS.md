# Components — versions, licenses, modifications

Everything shipped in the Matrux (`ru.matrux.app`) PC-gaming runtime that carries a
license notice, with the exact version we ship, whether we modified it, and where our
changes live. Versions that are not pinned by a file in our build tree are marked
**not pinned** — they come from the Ubuntu guest image and match that distribution's
archive at build time.

## Table

| # | Component | Version shipped | License | Upstream | Modified | Our patch |
|---|---|---|---|---|---|---|
| 1 | Wine | 11.16 | LGPL-2.1 | https://gitlab.winehq.org/wine/wine | **yes** | `wine/0001-wineserver-tmpdir-env.patch` |
| 2 | box64 | 0.4.5 (commit `52db1d07`) | MIT | https://github.com/ptitSeb/box64 | **yes** | `box64/0001…0017` (16 files) |
| 3 | proot | 5.1.107.102 | GPL-2.0 | https://github.com/termux/proot | no | — |
| 4 | DXVK | 2.4.1 shipped (2.6 measured, not shipped) | zlib | https://github.com/doitsujin/dxvk | no | — |
| 5 | Mesa / Turnip (freedreno, kgsl) | tag `mesa-25.0.7` | MIT | https://gitlab.freedesktop.org/mesa/mesa | **yes** — one file, `vulkan-android.sym` | `scripts/build-android-deps.sh` (`build_turnip`) |
| 6 | cnc-ddraw | 7.1.0.0 | MIT | https://github.com/FunkyFr3sh/cnc-ddraw | no | — |
| 7 | talloc | not pinned | LGPL-3.0 | https://git.samba.org/?p=talloc.git | no | — |
| 8 | PulseAudio (`libpulsecore-17.0`) | 17.0 | LGPL-2.1 | https://gitlab.freedesktop.org/pulseaudio/pulseaudio | no | — |
| 9 | dbus | not pinned | AFL-2.1 | https://gitlab.freedesktop.org/dbus/dbus | no | — |
| 10 | freetype | 2.13.2 | FTL | https://gitlab.freedesktop.org/freetype/freetype | no | — |
| 11 | zstd | 1.5.6 | BSD-3-Clause | https://github.com/facebook/zstd | no | — |

### Shipped alongside, not copyleft

| Component | Version | License | Upstream |
|---|---|---|---|
| libwayland | 1.24.0 | MIT | https://gitlab.freedesktop.org/wayland/wayland |
| libxkbcommon | 1.7.0 | MIT | https://github.com/xkbcommon/libxkbcommon |
| libxml2 | v2.13.5 | MIT | https://gitlab.gnome.org/GNOME/libxml2 |
| libffi | 3.4.6 | MIT | https://github.com/libffi/libffi |
| d8vk | not pinned | zlib | https://github.com/WinterSnowfall/d8vk |
| d7vk | not pinned | zlib | https://github.com/WinterSnowfall/d7vk |
| d3d8to9 | not pinned | MIT | https://github.com/crosire/d3d8to9 |
| VKD3D-Proton | not pinned | LGPL-2.1 | https://github.com/HansKristian-Work/vkd3d-proton |

## Notes per component

### 1. Wine 11.16 — LGPL-2.1

Native arm64 Wine ("hangover"-style: Wine built for aarch64 with the PE side executed
by box64), plus a separate x86_64 WoW64 build for the 32-bit path.

* Modification: `WINESERVER_TMPDIR` support in `dlls/ntdll/unix/server.c`
  (`init_server_dir`) and `server/request.c` (`create_server_dir`).
* Reason: no `/tmp` on Android; the socket directory must be an app-owned short path
  that survives container restarts.
* Reproduce: `scripts/fetch-sources.sh --wine && WINE_SRC=upstream/wine scripts/make-wine.sh`.
* LGPL-2.1 §6: the patch plus the pinned upstream tarball is the complete corresponding
  source of the Wine we ship. Wine libraries are dynamically loaded, so they can be
  replaced by a user build.

### 2. box64 0.4.5 — MIT

Built with `-DANDROID=1`, but for **glibc** x86_64 guests (Wine) instead of box64's
assumed bionic guest. 16 patches, file order matters (`0009` does not exist; it was
merged into `0010`). See `README.md` §4 for the per-patch description.

* Reproduce: `scripts/fetch-sources.sh --box64 && scripts/build-android-deps.sh box64`.
* Host-side test harness for the `ANDROID` path: `box64/sim/`.

### 3. proot 5.1.107.102 — GPL-2.0

Shipped **unmodified**, byte-for-byte as the Termux build (`libproot.so`,
`libproot-loader.so`). Version string `5.1.107.102` is the Termux package version and
matches the upstream tag of the same name.

* Corresponding source: https://github.com/termux/proot/tree/v5.1.107.102
  (`scripts/fetch-sources.sh --proot` downloads it; no Matrux patches are applied).
* The Termux package recipe with its patch series:
  `termux-packages/packages/proot/build.sh`.
* Used as a separate process (fork/exec), not linked into proprietary code.

### 4. DXVK — zlib

DXVK **2.4.1** is what the asset bundle ships. 2.6 was benchmarked on Adreno 618
(~3 FPS slower than 2.4.1 on the same scene) and deliberately not shipped; `dxvk.conf`
is written against the 2.4.1 option set. Unmodified.

### 5. Mesa / Turnip — MIT

Turnip is built from the `mesa-25.0.7` tag for bionic. Build flags (from
`build_turnip()` in `scripts/build-android-deps.sh`):
`-Dplatforms=wayland,android -Dvulkan-drivers=freedreno -Dfreedreno-kmds=kgsl` —
in full: `-Dplatforms=wayland,android -Dvulkan-drivers=freedreno
-Dfreedreno-kmds=kgsl -Dgallium-drivers= -Dopengl=false -Degl=disabled
-Dglx=disabled -Dgbm=disabled -Dllvm=disabled -Dandroid-stub=true
-Dandroid-libbacktrace=disabled -Dplatform-sdk-version=30 -Dxmlconfig=disabled
-Dzstd=disabled -Dvalgrind=disabled -Dlibunwind=disabled -Dcpp_rtti=false`.

One source change: Android builds export only the HMI symbols, so the script appends
`vk_icd*;` to `src/vulkan/vulkan-android.sym` (a `sed` in `build_turnip`) to expose the
direct ICD entry point `vk_icdGetInstanceProcAddr` that `libvulkan_matrux.so` calls.
The modified tree is produced by the script from the pinned tag; no other Mesa file is
touched.

### 6. cnc-ddraw — MIT

Official release 7.1.0.0, unmodified. Used as `ddraw.dll` (`sync`/`opengl`/`gdi`
renderers) plus the official `winmm.dll` proxy; `ddraw.ini` is generated by the app.

### 7–11. Libraries from the Ubuntu guest image

talloc, PulseAudio 17.0, dbus, freetype 2.13.2 and zstd 1.5.6 are taken from the guest
rootfs packages. We do not patch them, so the corresponding source is the distribution
source package for that version (Ubuntu archive). talloc and dbus versions are whatever
that image resolved at build time — **not pinned** in our tree.

## License texts

All texts in [`licenses/`](licenses/), with source URLs and sha256 in
[`licenses/README.md`](licenses/README.md).
