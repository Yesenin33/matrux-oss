# Third-party components shipped with Matrux (`ru.matrux.app`)

Matrux bundles a PC-gaming runtime: PRoot → box64 → Wine (native arm64) → DXVK/VKD3D,
plus a handful of support libraries. Several of those components are copyleft, so the
matching source code and our modifications are published here.

* **Application**: Matrux (`ru.matrux.app`), Android, distributed as an APK.
* **Repository purpose**: license compliance — publish our patches and the build
  scripts, and point at the exact upstream sources for unmodified components.
* **What is *not* here**: the Matrux application itself (proprietary Kotlin/Java code),
  signing keys, and prebuilt binaries. Only patches, scripts, license texts and docs.

---

## 1. Components

Full table with versions, licenses, upstream links and per-component notes:
**[`COMPONENTS.md`](COMPONENTS.md)**. Summary:

| Component | Version shipped | License | Upstream | Modified by us | Our patch |
|---|---|---|---|---|---|
| Wine | 11.16 (native arm64 runtime, hangover-style) | LGPL-2.1 | https://gitlab.winehq.org/wine/wine | **yes** | [`wine/0001-wineserver-tmpdir-env.patch`](wine/0001-wineserver-tmpdir-env.patch) |
| box64 | 0.4.5 (upstream commit `52db1d07`) | MIT | https://github.com/ptitSeb/box64 | **yes** | [`box64/0001…0017`](box64/) (16 patches) |
| proot | 5.1.107.102 | GPL-2.0 | https://github.com/termux/proot | no | — (unmodified, see §2) |
| DXVK | 2.4.1 (2.6 evaluated, not shipped) | zlib | https://github.com/doitsujin/dxvk | no | — |
| Mesa (Turnip / freedreno, kgsl) | mesa-25.0.7 tag | MIT | https://gitlab.freedesktop.org/mesa/mesa | **yes** — one symbol file | `scripts/build-android-deps.sh` |
| cnc-ddraw | 7.1.0.0 | MIT | https://github.com/FunkyFr3sh/cnc-ddraw | no | — |
| talloc | version not pinned (from the Ubuntu rootfs) | LGPL-3.0 | https://git.samba.org/?p=talloc.git | no | — |
| PulseAudio (libpulsecore 17.0) | 17.0 | LGPL-2.1 | https://gitlab.freedesktop.org/pulseaudio/pulseaudio | no | — |
| dbus | version not pinned (from the Ubuntu rootfs) | AFL-2.1 | https://gitlab.freedesktop.org/dbus/dbus | no | — |
| freetype | 2.13.2 | FTL | https://gitlab.freedesktop.org/freetype/freetype | no | — |
| zstd | 1.5.6 | BSD-3-Clause | https://github.com/facebook/zstd | no | — |

Also bundled but not copyleft and not modified: libwayland 1.24.0 (MIT),
libxkbcommon 1.7.0 (MIT), libxml2 v2.13.5 (MIT), libffi 3.4.6 (MIT),
d8vk / d7vk / d3d8to9 (zlib / MIT), VKD3D-Proton (LGPL-2.1, unmodified).

Versions marked "not pinned" are the ones shipped by the Ubuntu guest image; we do
not patch them, so the distribution's own source packages are the reference.

## 2. Where the exact sources are

`scripts/fetch-sources.sh` downloads the upstream trees for the pinned versions and
applies our patches (idempotent; safe to re-run):

```bash
scripts/fetch-sources.sh --all      # box64 + wine + proot into ./upstream
scripts/fetch-sources.sh --box64    # one component
```

| Component | Source fetched | Pinned by |
|---|---|---|
| box64 | `github.com/ptitSeb/box64` archive of commit `52db1d07` (v0.4.5 line) | sha256 of the tarball in the script |
| Wine | `dl.winehq.org/wine/source/11.x/wine-11.16.tar.xz` | sha256 of the tarball in the script |
| proot | `github.com/termux/proot` tag `v5.1.107.102` | sha256 of the tarball in the script |

**proot** is shipped byte-for-byte as Termux builds it (package `proot`,
Version 5.1.107.102, GPL-2.0). We did not modify it, so the complete corresponding
source is Termux's repository at the tag above — including the Termux patch series
applied by `termux-packages/packages/proot/build.sh`.

## 3. Wine changes (LGPL-2.1, §6 / §4)

`wine/0001-wineserver-tmpdir-env.patch` — **only one patch**; we do not carry a
KUSER_SHARED_DATA workaround in Wine on purpose (it is solved inside box64, see patch
0005, and a Wine-side fallback would not fix the absolute `testb $1,[0x7ffe0308]`
in `ntdll.dll`).

What it does: the wineserver socket directory can be taken from the
`WINESERVER_TMPDIR` environment variable instead of being derived from `WINEPREFIX`.

* `dlls/ntdll/unix/server.c` — `init_server_dir()`: if `WINESERVER_TMPDIR` is an
  absolute path, use `$WINESERVER_TMPDIR/.wine-<uid>/server-<dev>-<ino>`.
* `server/request.c` — `create_server_dir()`: same override, and create the directory
  with the right mode before `chdir`.

Why: on Android there is no `/tmp`, and the prefix lives under the app's private
`filesDir`, whose path length and permissions make the default
`<prefix>/.wine-<uid>/server-*` socket unreliable across container restarts. The app
already exports `WINESERVER_TMPDIR` pointing at a short, app-owned directory.

Build flags (unchanged upstream options):
`./configure --enable-archs=x86_64 --without-x --without-preloader`.
See `scripts/make-wine.sh`.

## 4. box64 changes (MIT)

box64 is built with `-DANDROID=1` for arm64 Android, but our guests are **glibc**
x86_64 (Wine), not bionic x86_64 — box64's `ANDROID` path assumes the latter. The
16 patches (numbered `0001`–`0017`, there is no `0009`; it was folded into `0010`)
fix the guest ABI and the Android-specific runtime gaps:

| Patch | Files | What it changes |
|---|---|---|
| `0001-android-glibc-guests` | `CMakeLists.txt`, `rebuild_wrappers.py`, `src/emu/entrypoint.c`, `wrappedlibc*` | Builds `my___libc_start_main` under `ANDROID`; glibc-only symbols (`__errno_location`, `__ctype_*_loc`, `__assert_fail`, `__h_errno_location`, `__xpg_basename`, `__res_state/__res_init`); `shm_open`/`shm_unlink` via `$BOX64_SHM_DIR` (no `/dev/shm` on Android); `nl_langinfo`/`sysconf` constant translation; `getaddrinfo` family with different `AI_*/NI_*/EAI_*` and swapped `ai_addr`/`ai_canonname`. Adds `ANDROID_GLIBC_GUEST` guest-ABI mode (`x64_sigaction_t`, `x64_sigset_t`, `x64_ucontext_t` in glibc layout, 80-bit x87 `long double`). |
| `0002-android-guest-exec` | `src/wrapped/wrappedlibc.c` | targetSdk ≥ 29: when SELinux denies `PROT_EXEC` on a file mapping (`EACCES`/`EPERM`), retry without `PROT_EXEC` (dynarec executes from its own anonymous cache). |
| `0003-android-kuser-shared-data` | `src/core.c`, `src/tools/wine_tools.*` | Reserves the `KUSER_SHARED_DATA` page (`0x7ffe0000`) before Wine starts, and repeats the guest's `MAP_FIXED_NOREPLACE` as `MAP_FIXED` inside box64's prereserve range. |
| `0004-android-dlopen-and-kuser-log` | `src/core.c`, `src/libtools/libdl.c` | Refreshes `LD_LIBRARY_PATH` from `dirname(/proc/self/exe)` after loading env, and falls back to absolute paths under `nativeLibraryDir` for `libxkbcommon.so.0`, `libwayland-client.so.0`, `libvulkan.so.1`; drops the stack-relocation branch from 0003 (moving `[stack]` breaks `argv`/`env`). |
| `0005-kuser-startup-rw` | `src/core.c`, `src/tools/wine_tools.*` | Makes `0x7ffe0000` readable/writable (`SystemCall = 1`) *before* the guest ELF runs, so `ntdll.dll`'s `testb $1,[0x7ffe0308]` does not fault on a `PROT_NONE` prereserve page. |
| `0006-android-dlopen-obj` | `src/libtools/android_dlopen.c` | Object-name resolution for the fallback `dlopen` above (name → `/proc/self/maps` lookup). |
| `0007-android-kuser-range-syscalls` | `src/tools/wine_tools.c`, `src/emu/x64syscall.c` | Treats `mmap`/`mprotect`/`munmap` targeting the KUSER range as belonging to Wine, so the range handling applies to syscalls, not only to wrapped libc calls. |
| `0008-mmap-fail-log` | `src/custommem.c` | Diagnostic logging of failed `mmap` under Wine (kept for bug reports). |
| `0010`–`0013`, `0016` | `src/wrapped/wrappedlibc*`, `wrappedlibpthread.c` | The remaining glibc-vs-bionic surface: more `wrappedlibc` symbols and `_private.h` prototypes, ctype/locale tables, `stdio`/`strftime`/`iconv`-adjacent entry points, `pthread` variants, `__libc_*` internals used by Wine's unix libs. |
| `0011-tlsdesc-fallback` | `src/elfs/elfloader.c` | `R_X86_64_TLSDESC` resolution fallback for glibc guests when bionic's resolver is absent. |
| `0014-android-pthread-affinity` | `src/libtools/threads.c` | Android forbids setting arbitrary CPU affinity; clamp instead of failing. |
| `0015-android-locale-sanitize` | `src/wrapped/wrappedlibc.c` | Sanitises the locale name bionic rejects (`C.UTF-8` vs Android's set) so `setlocale` succeeds. |
| `0017-android-userfaultfd-nosigsys` | `src/emu/x64syscall.c` | `userfaultfd` (323) has no NT counterpart; run the real syscall and return `ENOSYS` instead of routing it through the SIGSYS PE↔unix bridge. |

Patch series is ordered: apply `0001` … `0017` in filename order (`0009` absent).

`scripts/build-android-deps.sh` builds box64 (and, unchanged, wayland, xkbcommon and
Mesa/Turnip) with the Android NDK. `box64/sim/` contains the host-side harness used to
test the `ANDROID` code path without a device (aarch64 glibc build + `qemu-aarch64`).

## 5. Reproducing the build

Requirements: Linux x86_64 host, Android NDK r27c (`ANDROID_NDK_HOME`), plus
`git cmake ninja-build meson python3-mako python3-yaml pkg-config bison flex
glslang-tools libwayland-bin`, `mingw-w64` and `wayland-client` dev files for Wine.

```bash
# 1. fetch upstream sources and apply our patches
scripts/fetch-sources.sh --all

# 2. box64 + wayland + xkbcommon + Turnip (bionic, arm64-v8a)
export ANDROID_NDK_HOME=/path/to/android-ndk-r27c
scripts/build-android-deps.sh all

# 3. Wine (x86_64, mingw-w64 cross build)
export WINE_SRC=$PWD/upstream/wine
scripts/make-wine.sh            # patches + prints configure line
MAKE_WINE=1 scripts/make-wine.sh   # also configure + make (long)

# 4. artefact check
scripts/make-runtime.sh
```

`build-android-deps.sh` writes to `<repo>/app/src/main/jniLibs/arm64-v8a` and
`make-runtime.sh` checks that directory — that is the layout of the private
application tree these scripts were written for. Set `OUT`/`WORK` or copy the
artefacts if you build outside it.

## 6. License obligations

* **LGPL-2.1 (Wine, PulseAudio, VKD3D)** — we modify Wine, so the modified source is
  published: the patch in `wine/`, applied to the pinned upstream tarball by
  `scripts/fetch-sources.sh`, yields exactly the Wine sources we build. Wine is
  dynamically linked; users may replace the Wine libraries in the app's runtime
  directory with their own builds.
* **GPL-2.0 (proot)** — shipped unmodified, as a separate executable invoked by the
  app; full corresponding source is the Termux repository at tag `v5.1.107.102`
  (see §2). No linking with proprietary code takes place.
* **MIT / zlib / BSD-3 / AFL-2.1 / FTL** — attribution only; license texts are in
  [`licenses/`](licenses/) and the components are unmodified.
* Full license texts, with the source each was taken from, are in
  [`licenses/README.md`](licenses/README.md).

## 7. Trademarks

Wine, box64, proot, DXVK, Mesa, cnc-ddraw, PulseAudio, dbus, FreeType, zlib and the
names of their authors are trademarks or project names of their respective owners.
This repository is not affiliated with, endorsed by, or sponsored by any of them.
Component names are used only to identify the software. "Matrux" is the name of the
application; no third-party project endorses it.

## 8. Contact

Issues and questions about these sources: open an issue in this repository.

---

## Кратко по-русски

Здесь лежат патчи и скрипты сборки сторонних компонентов, которые входят в
приложение Matrux (`ru.matrux.app`): Wine 11.16 (LGPL-2.1), box64 0.4.5 (MIT),
proot 5.1.107.102 (GPL-2.0), DXVK, Mesa/Turnip, cnc-ddraw и библиотеки окружения.

* Мы патчим **Wine** (один патч: каталог сокета wineserver из `WINESERVER_TMPDIR`)
  и **box64** (16 патчей: гостевой ABI glibc вместо bionic, `KUSER_SHARED_DATA`,
  `dlopen` из `nativeLibraryDir`, недостающие glibc-символы). По LGPL-2.1 изменённый
  исходный код опубликован — это и есть содержимое `wine/` и `box64/`.
* **proot** мы не меняли; исходники — репозиторий `termux/proot`, тег `v5.1.107.102`
  (GPL-2.0). Скачать всё и применить патчи: `scripts/fetch-sources.sh --all`.
* Проприетарный код приложения, ключи и готовые бинарники сюда не входят.
* Тексты лицензий — в `licenses/`, состав и версии — в таблице выше.


## Гостевые системы Linux

Приложение также раздаёт пять корневых файловых систем Linux (`alpine-xfce`, `debian-xfce`, `ubuntu-xfce`,
`arch-xfce`, `dev-xfce`). Пакеты внутри не патчились, менялся состав файлов (удалены прошивки, модули ядра,
загрузчик), добавлен наш скрипт сессии. Что именно изменено, где исходники и какие уведомления обязательны —
[`guests/README.md`](guests/README.md), перечни пакетов с версиями — [`guests/`](guests/).

Вопросы — через issues.
