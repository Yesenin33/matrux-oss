#!/usr/bin/env bash
# Сборка нативных (bionic, arm64-v8a) зависимостей раздела «PC game» под Android NDK.
# Результат кладётся в app/src/main/jniLibs/arm64-v8a под именами lib*.so
# (Android распаковывает из APK только такие), версионированные имена
# (libwayland-client.so.0 и т.п.) создаёт приложение симлинками — см. WinePaths.kt.
#
# Хост: Linux x86_64 с git, cmake, ninja, meson (>=1.3), python3 (+mako, pyyaml),
#       pkg-config, bison, flex, glslang (для Mesa), wayland-scanner (хостовый, той же версии).
#   Debian/Ubuntu: apt install git cmake ninja-build meson python3-mako python3-yaml \
#                  pkg-config bison flex glslang-tools libwayland-bin
#
# Использование:
#   export ANDROID_NDK_HOME=/path/to/android-ndk-r27c
#   pcrt-build/build-android-deps.sh all            # или: box64 wayland xkbcommon turnip
set -euo pipefail

: "${ANDROID_NDK_HOME:?укажите ANDROID_NDK_HOME}"
API="${API:-30}"                       # PC-раздел: Android 11+ (memfd_create, renameat2)
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
WORK="${WORK:-$HOME/pcrt-deps}"
PREFIX="$WORK/prefix"
OUT="$REPO/app/src/main/jniLibs/arm64-v8a"

BOX64_REF="${BOX64_REF:-52db1d07}"           # тот же коммит, что в текущем libbox64.so (v0.4.5)
LIBFFI_VER="${LIBFFI_VER:-3.4.6}"        # релизный тарбол (git-дерево не собирается)
WAYLAND_REF="${WAYLAND_REF:-1.24.0}"
LIBXML2_REF="${LIBXML2_REF:-v2.13.5}"
XKB_REF="${XKB_REF:-xkbcommon-1.7.0}"
MESA_REF="${MESA_REF:-mesa-25.0.7}"           # любая 24.3+/25.x с turnip kgsl

TC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
SYSROOT="$TC/sysroot"
CC="$TC/bin/aarch64-linux-android$API-clang"
CXX="$TC/bin/aarch64-linux-android$API-clang++"
STRIP="$TC/bin/llvm-strip"

mkdir -p "$WORK/src" "$PREFIX" "$OUT"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR=
unset PKG_CONFIG_PATH

fetch() {   # fetch <url> <ref> <dir>
    local url=$1 ref=$2 dir="$WORK/src/$3"
    if [ ! -d "$dir/.git" ]; then git clone --filter=blob:none "$url" "$dir"; fi
    git -C "$dir" fetch --tags -q origin || true
    git -C "$dir" checkout -q -f "$ref"
}

cross_file() {
    cat > "$WORK/android-aarch64.ini" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$TC/bin/llvm-ar'
strip = '$STRIP'
pkg-config = 'pkg-config'
wayland-scanner = '/usr/bin/wayland-scanner'
cmake = '/usr/bin/cmake'

[built-in options]
c_args = ['-fPIC', '-I$PREFIX/include']
cpp_args = ['-fPIC', '-I$PREFIX/include']
c_link_args = ['-Wl,-z,max-page-size=16384', '-llog']
cpp_link_args = ['-Wl,-z,max-page-size=16384', '-static-libstdc++', '-llog']

[properties]
needs_exe_wrapper = true
pkg_config_libdir = '$PKG_CONFIG_LIBDIR'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF
}

install_so() {   # install_so <файл> <имя в jniLibs>
    # meson без версионных symlink-ов оставляет только libfoo.so — подхватываем и его.
    [ -e "$1" ] || set -- "${1%.so.*}.so" "$2"
    cp -L "$1" "$OUT/$2"
    # Android кладёт в APK только lib*.so и ищет DT_NEEDED по имени файла.
    # SONAME libfoo.so.N в dynstr короче не станет длиннее — обрезаем на месте.
    python3 - "$OUT/$2" <<'PY'
import sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
repls = [
    b"libwayland-client.so.0\0",
    b"libwayland-egl.so.1\0",
    b"libwayland-cursor.so.0\0",
    b"libxkbcommon.so.0\0",
    b"libxkbregistry.so.0\0",
]
n = 0
for old in repls:
    cut = old.find(b".so.")
    if cut < 0:
        continue
    new = old[: cut + 3] + b"\0" * (len(old) - (cut + 3))
    assert len(new) == len(old)
    start = 0
    while True:
        j = data.find(old, start)
        if j < 0:
            break
        data[j : j + len(old)] = new
        n += 1
        start = j + len(old)
if n:
    open(path, "wb").write(data)
    print(f"  soname/needed -> *.so ({n})")
PY
    "$STRIP" --strip-unneeded "$OUT/$2"
    echo "  -> jniLibs/arm64-v8a/$2 ($(du -h "$OUT/$2" | cut -f1))"
}

# ---------------------------------------------------------------- box64
build_box64() {
    fetch https://github.com/ptitSeb/box64 "$BOX64_REF" box64
    local src="$WORK/src/box64"
    git -C "$src" apply --check "$HERE/box64/0001-android-glibc-guests.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0001-android-glibc-guests.patch"
    git -C "$src" apply --check "$HERE/box64/0002-android-guest-exec.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0002-android-guest-exec.patch"
    git -C "$src" apply --check "$HERE/box64/0003-android-kuser-shared-data.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0003-android-kuser-shared-data.patch"
    git -C "$src" apply --check "$HERE/box64/0004-android-dlopen-and-kuser-log.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0004-android-dlopen-and-kuser-log.patch"
    git -C "$src" apply --check "$HERE/box64/0005-kuser-startup-rw.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0005-kuser-startup-rw.patch"
    # android_dlopen.c: в upstream libdl.c на Android не компилируется, реализация в отдельном файле
    git -C "$src" apply --check "$HERE/box64/0006-android-dlopen-obj.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0006-android-dlopen-obj.patch"
    git -C "$src" apply --check "$HERE/box64/0007-android-kuser-range-syscalls.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0007-android-kuser-range-syscalls.patch"
    git -C "$src" apply --check "$HERE/box64/0008-mmap-fail-log.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0008-mmap-fail-log.patch"
    # 0010: недостающие glibc-символы для Android (bionic их не экспортирует):
    # __getdelim (alias на getdelim), strverscmp/explicit_bzero/__explicit_bzero_chk/__uflow (my_-реализации).
    git -C "$src" apply --check "$HERE/box64/0010-android-glibc-symbols.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0010-android-glibc-symbols.patch"
    # 0011: R_X86_64_TLSDESC — всегда пишем полный дескриптор {resolver,arg} (локальный / реальный
    # символ / неразрешённый), убрана ложная ветка else; неразрешённый weak-символ (TLSDESC и
    # JUMP_SLOT/GLOB_DAT) резолвится в 0 как в glibc — иначе libLLVM прыгает по мусорному линк-тайм
    # адресу PLT и виснет в futex_wait при инициализации.
    git -C "$src" apply --check "$HERE/box64/0011-tlsdesc-fallback.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0011-tlsdesc-fallback.patch"
    # 0012: ещё недостающие glibc-символы для Android. bionic не экспортирует НИ eaccess,
    # НИ euidaccess (только access/faccessat) — из-за неразрешённого GLOBAL JUMP_SLOT eaccess
    # не грузился libxkbcommon/libxkbregistry (dlopen winewayland.so падал, Wine уходил в
    # null-драйвер). my_eaccess/my_euidaccess → faccessat(AT_EACCESS) с фолбэком на access().
    # Плюс заглушка _dl_find_object (glibc >= 2.35, нужна libgcc-разворачивателю) → -1, чтобы
    # сорвался на dl_iterate_phdr, а не на сбойной релокации.
    git -C "$src" apply --check "$HERE/box64/0012-box64-glibc-symbols-2.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0012-box64-glibc-symbols-2.patch"
    # 0013: третья порция недостающих glibc-символов для Android (bionic их не экспортирует).
    # __*_l (locale) → bionic *_l / нелокалевые аналоги; newlocale/freelocale/duplocale/uselocale
    # → bionic-версии; __*_chk → базовые wmemset/wmemcpy/mbsrtowcs; strtof128/strfromf128 → заглушки
    # (в bionic нет _Float128); gettext/dgettext → возвращают msgid, bindtextdomain/
    # bind_textdomain_codeset → 0; ZSTD_trace_* → пустые void-заглушки. Без них libEGL (Mesa)
    # не грузится: «Symbol X not found, cannot apply R_X86_64_JUMP_SLOT».
    git -C "$src" apply --check "$HERE/box64/0013-box64-glibc-symbols-3.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0013-box64-glibc-symbols-3.patch"
    # 0014: bionic не экспортирует pthread_setaffinity_np/pthread_getaffinity_np (есть только
    # sched_{set,get}affinity). Родные my_-реализации в threads.c собираются лишь под
    # #ifndef ANDROID, поэтому GOM-регистрации box64 разрешались в NULL и Mesa libEGL не
    # грузился: «Symbol pthread_setaffinity_np not found, cannot apply R_X86_64_JUMP_SLOT».
    # Под Android переопределяем через sched_*affinity + pthread_gettid_np. Проактивный скан
    # nm -uD по всем Mesa-бинарникам (394 символа) не выявил больше ни одного нераскрытого:
    # остальные закрыты bionic, существующими my_-обёртками box64 или гостевыми .so
    # (libdrm/libwayland/libxml2/libzstd/libc++).
    git -C "$src" apply --check "$HERE/box64/0014-box64-android-pthread-affinity.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0014-box64-android-pthread-affinity.patch"
    # 0015: bionic newlocale() строже glibc: отклоняет вызов (EINVAL -> NULL), если
    # (category_mask & ~LC_ALL_MASK) != 0, а bionic-овый LC_ALL_MASK (0x1fbf) НЕ содержит
    # бит LC_ALL (1 << LC_ALL == 0x40). libstdc++ при статической инициализации зовёт
    # __newlocale(1 << LC_ALL, "C", NULL) == 0x40 -> bionic отдаёт NULL -> бросок
    # «locale::facet::_S_create_c_locale name not valid». my___newlocale санитайзит маску
    # (mask & 0x3fbf, затем только 6 ISO C категорий) и фолбэкает на newlocale(LC_ALL_MASK,
    # "C", ...); защита от locale_name==NULL. __duplocale/__freelocale/__uselocale — гарды
    # на NULL/LC_GLOBAL_LOCALE.
    git -C "$src" apply --check "$HERE/box64/0015-box64-android-locale-sanitize.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0015-box64-android-locale-sanitize.patch"
    # 0016: последняя порция glibc-символов, которые bionic не экспортирует вовсе
    # (не под __-именем). Полный `nm -uD` по ВСЕМ 194 x86_64 .so рантайма
    # (glz-repack/{glz,x86}) показал: box64 уже объявлял большинство как GO/GOW
    # (dlsym в нативную libc), но у bionic нет ни такого имени, ни функции, и
    # ГЛОБАЛЬНЫЙ импорт гостя падал «Symbol X not found, cannot apply
    # R_X86_64_JUMP_SLOT». Блокировавший libgnutls.so.30 символ — dcgettext;
    # добавлены остальные члены libintl (dcgettext/__dcgettext, ngettext,
    # dngettext, dcngettext, textdomain), glibc-овые __strtol/strtoul/strtoll/
    # strtoull_l, __stpcpy/__strtok_r/__strdup/__strcasecmp/__strcasestr,
    # rawmemchr/__rawmemchr, фортификаты __fdelt_chk/__wcsncpy_chk/
    # __mbstowcs_chk, __open64_2/__openat64_2, __xpg_strerror_r, __gmtime_r,
    # secure_getenv, index/rindex, close_range, __poll, __sbrk, getspnam_r,
    # внутренние __libc_{malloc,free,realloc,memalign} и pthread_cancel/
    # pthread_setcanceltype.
    git -C "$src" apply --check "$HERE/box64/0016-box64-android-glibc-symbols-4.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0016-box64-android-glibc-symbols-4.patch"
    # 0017: userfaultfd (323) отключён в таблице syscallwrap, поэтому гость получал
    # SIGSYS-петлю. Делаем реальный syscall(SYS_userfaultfd) и на EPERM/ENOSYS
    # отдаём гостю чистый -ENOSYS без исключения; x64Syscall больше не гонит 323
    # через SIGSYS-мост.
    git -C "$src" apply --check "$HERE/box64/0017-android-userfaultfd-nosigsys.patch" 2>/dev/null \
        && git -C "$src" apply "$HERE/box64/0017-android-userfaultfd-nosigsys.patch"
    # 0009 (эксперимент): не держим 48 МБ под 0x7f000000 — только страницу KUSER_SHARED_DATA.
    # Wine сам раздаёт адреса в этом диапазоне и упирался в наш MAP_FIXED-резерв.
    sed -i 's/{(void\*)0x7f000000, 0x03000000}/{(void*)0x7ffe0000, 0x00001000}/' "$src/src/tools/wine_tools.c"
    python3 - "$src/CMakeLists.txt" <<'PYE'
import sys
p = sys.argv[1]
t = open(p).read()
if 'android_dlopen' not in t:
    anchor = 'if(NOT ANDROID)\n    list(APPEND ELFLOADER_SRC\n        "${BOX64_ROOT}/src/libtools/obstack.c"\n    )\nendif()'
    if anchor not in t:
        sys.exit('нет якоря obstack в CMakeLists.txt')
    t = t.replace(anchor, anchor + '\n\nif(ANDROID)\n    list(APPEND ELFLOADER_SRC\n        "${BOX64_ROOT}/src/libtools/android_dlopen.c"\n    )\nendif()', 1)
    open(p, 'w').write(t)
    print('  android_dlopen -> ELFLOADER_SRC')
PYE
    cmake -S "$src" -B "$src/build-android" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM="android-$API" \
        -DANDROID=1 -DARM_DYNAREC=1 -DBAD_SIGNAL=1 \
        -DCMAKE_BUILD_TYPE=Release

    cmake --build "$src/build-android" -j"$(nproc)"
    # Release на Android = -O1 (так задано в box64), отладочную информацию срезаем: 72 МБ -> ~25 МБ
    install_so "$src/build-android/box64" libbox64.so
    # проверка: точка входа glibc должна быть экспортирована
    if "$TC/bin/llvm-nm" -D "$OUT/libbox64.so" | grep -q 'my___libc_start_main'; then
        echo "  my___libc_start_main: OK"
    else
        echo "  my___libc_start_main НЕ НАЙДЕН (не фатально)"
    fi
}

# ---------------------------------------------------------------- libffi (статически, для wayland)
build_libffi() {
    # Build from the release tarball: the git tree has no generated configure and its
    # autoreconf fails on LT_SYS_SYMBOL_USCORE. Wayland 1.24 links libffi, so it is required.
    local tar="$WORK/src/libffi-$LIBFFI_VER.tar.gz" src="$WORK/src/libffi-$LIBFFI_VER"
    [ -f "$tar" ] || curl -fsSL -o "$tar" "https://github.com/libffi/libffi/releases/download/v$LIBFFI_VER/libffi-$LIBFFI_VER.tar.gz" || return 1
    [ -d "$src" ] || tar xzf "$tar" -C "$WORK/src"
    rm -rf "$src/build-android" && mkdir -p "$src/build-android" && cd "$src/build-android"
    CC="$CC" AR="$TC/bin/llvm-ar" RANLIB="$TC/bin/llvm-ranlib" CFLAGS="-fPIC -O2" ../configure --host=aarch64-linux-android --prefix="$PREFIX" \
        --disable-shared --enable-static --disable-docs --disable-multi-os-directory
    make -j"$(nproc)" && make install
}

# ---------------------------------------------------------------- wayland (client, egl, cursor)
build_wayland() {
    # Wayland 1.24 does not link libffi; keep the build going if it fails on old tarballs.
    build_libffi || echo "libffi: пропущен (wayland его не линкует)"
    cross_file
    # Host scanner: meson wants a `wayland-scanner` .pc, and our cross pkg_config_libdir
    # only looks inside the NDK prefix, so provide one that points at the host binary.
    mkdir -p "$PREFIX/share/pkgconfig"
    cat > "$PREFIX/share/pkgconfig/wayland-scanner.pc" <<'PC'
wayland_scanner=/usr/bin/wayland-scanner
Name: wayland-scanner
Description: Wayland scanner (host tool)
Version: 1.24.0
PC
    fetch https://gitlab.freedesktop.org/wayland/wayland.git "$WAYLAND_REF" wayland
    local src="$WORK/src/wayland"
    meson setup --reconfigure "$src/build-android" "$src" --cross-file "$WORK/android-aarch64.ini" \
        --prefix="$PREFIX" --buildtype=release -Ddefault_library=shared \
        -Dlibraries=true -Dscanner=false -Dtests=false -Ddocumentation=false -Ddtd_validation=false
    ninja -C "$src/build-android" install
    install_so "$PREFIX/lib/libwayland-client.so.0" libwayland-client.so
    install_so "$PREFIX/lib/libwayland-egl.so.1"    libwayland-egl.so
    install_so "$PREFIX/lib/libwayland-cursor.so.0" libwayland-cursor.so
}

# ---------------------------------------------------------------- libxml2 (статически) + xkbcommon/xkbregistry
build_xkbcommon() {
    cross_file
    fetch https://github.com/GNOME/libxml2 "$LIBXML2_REF" libxml2
    cmake -S "$WORK/src/libxml2" -B "$WORK/src/libxml2/build-android" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM="android-$API" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_SHARED_LIBS=OFF -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_ICONV=OFF \
        -DLIBXML2_WITH_LZMA=OFF -DLIBXML2_WITH_ZLIB=OFF -DLIBXML2_WITH_TESTS=OFF \
        -DLIBXML2_WITH_PROGRAMS=OFF -DLIBXML2_WITH_ICU=OFF
    cmake --build "$WORK/src/libxml2/build-android" --target install

    fetch https://github.com/xkbcommon/libxkbcommon "$XKB_REF" libxkbcommon
    local src="$WORK/src/libxkbcommon"
    meson setup --reconfigure "$src/build-android" "$src" --cross-file "$WORK/android-aarch64.ini" \
        --prefix="$PREFIX" --buildtype=release -Ddefault_library=shared \
        -Denable-x11=false -Denable-wayland=false -Denable-docs=false -Denable-tools=false \
        -Denable-xkbregistry=true -Denable-bash-completion=false \
        -Dxkb-config-root=/system/usr/share/X11/xkb -Dx-locale-root=/system/usr/share/X11/locale
    ninja -C "$src/build-android" install
    install_so "$PREFIX/lib/libxkbcommon.so.0"   libxkbcommon.so
    install_so "$PREFIX/lib/libxkbregistry.so.0" libxkbregistry.so
}

# ---------------------------------------------------------------- android stubs для Mesa
# Mesa под DETECT_OS_ANDROID тянет заголовки платформы (cutils, log); Turnip они не нужны,
# а NDK их не даёт. Кладём минимальные стабы в $PREFIX/include.
android_stubs() {
    mkdir -p "$PREFIX/include/cutils" "$PREFIX/include/log"
    cat > "$PREFIX/include/cutils/trace.h" <<'H'
#ifndef MATRUX_STUB_CUTILS_TRACE_H
#define MATRUX_STUB_CUTILS_TRACE_H
#include <stdint.h>
#define ATRACE_TAG_GRAPHICS 0x00000004u
static inline void atrace_begin(uint64_t t, const char *n) { (void)t; (void)n; }
static inline void atrace_end(uint64_t t) { (void)t; }
static inline void atrace_async_begin(uint64_t t, const char *n, int32_t c) { (void)t; (void)n; (void)c; }
static inline void atrace_async_end(uint64_t t, const char *n, int32_t c) { (void)t; (void)n; (void)c; }
static inline void atrace_int(uint64_t t, const char *n, int32_t v) { (void)t; (void)n; (void)v; }
static inline void atrace_int64(uint64_t t, const char *n, int64_t v) { (void)t; (void)n; (void)v; }
static inline int atrace_is_tag_enabled(uint64_t t) { (void)t; return 0; }
#define ATRACE_BEGIN(n) atrace_begin(ATRACE_TAG_GRAPHICS, n)
#define ATRACE_END() atrace_end(ATRACE_TAG_GRAPHICS)
#endif
H
    cat > "$PREFIX/include/cutils/properties.h" <<'H'
#ifndef MATRUX_STUB_CUTILS_PROPERTIES_H
#define MATRUX_STUB_CUTILS_PROPERTIES_H
#include <stdint.h>
#define PROPERTY_KEY_MAX 32
#define PROPERTY_VALUE_MAX 92
#ifdef __cplusplus
extern "C" {
#endif
static inline int property_get(const char *k, char *v, const char *d) {
    int i = 0;
    (void)k;
    if (!v) return 0;
    if (d) { while (d[i]) { v[i] = d[i]; i++; } }
    v[i] = 0;
    return i;
}
static inline int property_set(const char *k, const char *v) { (void)k; (void)v; return 0; }
static inline int32_t property_get_int32(const char *k, int32_t d) { (void)k; return d; }
static inline int64_t property_get_int64(const char *k, int64_t d) { (void)k; return d; }
#ifdef __cplusplus
}
#endif
#endif
H
    cat > "$PREFIX/include/cutils/native_handle.h" <<'H'
#ifndef MATRUX_STUB_CUTILS_NATIVE_HANDLE_H
#define MATRUX_STUB_CUTILS_NATIVE_HANDLE_H
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
typedef struct native_handle {
    int version;
    int numFds;
    int numInts;
    int data[0];
} native_handle_t;
typedef const native_handle_t *buffer_handle_t;
#define native_handle_close(h) do { for (int _i = 0; _i < (h)->numFds; _i++) close((h)->data[_i]); } while (0)
static inline native_handle_t *native_handle_create(int numFds, int numInts) {
    native_handle_t *h = (native_handle_t *)malloc(sizeof(native_handle_t) + (int)sizeof(int) * (numFds + numInts));
    if (!h) return NULL;
    h->version = sizeof(native_handle_t);
    h->numFds = numFds;
    h->numInts = numInts;
    return h;
}
static inline int native_handle_delete(native_handle_t *h) { free(h); return 0; }
static inline int native_handle_init(native_handle_t *h, int numFds, int numInts) {
    h->version = sizeof(native_handle_t); h->numFds = numFds; h->numInts = numInts; return 0;
}
#endif
H
    cat > "$PREFIX/include/cutils/log.h" <<'H'
#ifndef MATRUX_STUB_CUTILS_LOG_H
#define MATRUX_STUB_CUTILS_LOG_H
#include <stdarg.h>
#include <stdint.h>
typedef enum { ANDROID_LOG_UNKNOWN=0, ANDROID_LOG_DEFAULT, ANDROID_LOG_VERBOSE, ANDROID_LOG_DEBUG,
               ANDROID_LOG_INFO, ANDROID_LOG_WARN, ANDROID_LOG_ERROR, ANDROID_LOG_FATAL, ANDROID_LOG_SILENT } android_LogPriority;
static inline int __android_log_print(int p, const char *t, const char *f, ...) { (void)p; (void)t; (void)f; return 0; }
static inline int __android_log_write(int p, const char *t, const char *s) { (void)p; (void)t; (void)s; return 0; }
static inline int __android_log_vprint(int p, const char *t, const char *f, va_list a) { (void)p; (void)t; (void)f; (void)a; return 0; }
#define LOG_PRI(prio, tag, ...) __android_log_print(prio, tag, __VA_ARGS__)
#endif
H
    cat > "$PREFIX/include/android/log.h" <<'H'
#ifndef MATRUX_STUB_ANDROID_LOG_H
#define MATRUX_STUB_ANDROID_LOG_H
#include <cutils/log.h>
#endif
H
    mkdir -p "$PREFIX/include/vndk" "$PREFIX/include/android"
    cat > "$PREFIX/include/vndk/hardware_buffer.h" <<'H'
#ifndef MATRUX_STUB_VNDK_HARDWARE_BUFFER_H
#define MATRUX_STUB_VNDK_HARDWARE_BUFFER_H
#include <stdint.h>
#include <cutils/native_handle.h>
typedef struct AHardwareBuffer AHardwareBuffer;
typedef struct AHardwareBuffer_Desc {
    uint32_t width, height, layers, format;
    uint64_t usage;
    uint32_t stride, rfu0, rfu1;
} AHardwareBuffer_Desc;
static inline int AHardwareBuffer_allocate(const AHardwareBuffer_Desc *d, AHardwareBuffer **b) { (void)d; if (b) *b = 0; return -1; }
static inline void AHardwareBuffer_release(AHardwareBuffer *b) { (void)b; }
static inline void AHardwareBuffer_describe(const AHardwareBuffer *b, AHardwareBuffer_Desc *d) { (void)b; if (d) { d->width = d->height = d->layers = d->format = 0; d->usage = 0; } }
static inline const native_handle_t *AHardwareBuffer_getNativeHandle(const AHardwareBuffer *b) { (void)b; return 0; }
static inline int AHardwareBuffer_lock(AHardwareBuffer *b, uint64_t u, int32_t t, const void *r, void **p) { (void)b; (void)u; (void)t; (void)r; (void)p; return -1; }
static inline int AHardwareBuffer_unlock(AHardwareBuffer *b, int32_t *f) { (void)b; (void)f; return -1; }
#endif
H
    printf '#include <vndk/hardware_buffer.h>\n' > "$PREFIX/include/android/hardware_buffer.h"
    cat > "$PREFIX/include/log/log.h" <<'H'
#ifndef MATRUX_STUB_LOG_LOG_H
#define MATRUX_STUB_LOG_LOG_H
#include <cutils/log.h>
#endif
H
}

# ---------------------------------------------------------------- Mesa Turnip (kgsl) с wayland WSI
build_turnip() {
    [ -f "$PREFIX/lib/pkgconfig/wayland-client.pc" ] || build_wayland
    cross_file
    android_stubs
    # wayland-protocols нужен только как XML (хостовый пакет или исходники)
    fetch https://gitlab.freedesktop.org/wayland/wayland-protocols.git 1.41 wayland-protocols
    meson setup --reconfigure "$WORK/src/wayland-protocols/build" "$WORK/src/wayland-protocols" \
        --prefix="$PREFIX" -Dtests=false
    ninja -C "$WORK/src/wayland-protocols/build" install

    fetch https://gitlab.freedesktop.org/mesa/mesa.git "$MESA_REF" mesa
    local src="$WORK/src/mesa"
    # Mesa везёт собственные Android-стабы (include/android_stub): android/sync.h,
    # vndk/hardware_buffer.h, ion/ion.h, cutils/* — копируем в prefix, чтобы они были
    # в -I без переезда cross-file. Лог-заголовки потом перекрываем inline-стабами.
    cp -rf "$src/include/android_stub/." "$PREFIX/include/"
    # Android-сборка Mesa прячет все символы кроме HMI (это HAL-модель). Нам нужен
    # прямой ICD-вход: vkshim.c зовёт vk_icdGetInstanceProcAddr, поэтому открываем vk_icd*.
    sed -i 's/^\t\tHMI;$/\t\tHMI;\n\t\tvk_icd*;/' "$src/src/vulkan/vulkan-android.sym"

    android_stubs
    meson setup --reconfigure "$src/build-android" "$src" --cross-file "$WORK/android-aarch64.ini" \
        --prefix="$PREFIX" --buildtype=release -Db_ndebug=true -Db_lto=false \
        -Dplatforms=wayland,android \
        -Dvulkan-drivers=freedreno -Dfreedreno-kmds=kgsl \
        -Dgallium-drivers= -Dopengl=false -Degl=disabled -Dgles1=disabled -Dgles2=disabled \
        -Dglx=disabled -Dgbm=disabled -Dllvm=disabled \
        -Dandroid-stub=true -Dandroid-libbacktrace=disabled \
        -Dplatform-sdk-version=30 \
        -Dxmlconfig=disabled -Dzstd=disabled -Dvalgrind=disabled -Dlibunwind=disabled \
        -Dcpp_rtti=false -Dvulkan-layers=
    ninja -C "$src/build-android"
    install_so "$src/build-android/src/freedreno/vulkan/libvulkan_freedreno.so" libvulkan_freedreno.so
    # libcutils.so и libhardware.so НЕ кладём в APK: их заглушки из Mesa перекрывают
    # системные библиотеки в namespace приложения, и тогда /system/lib64/libutils.so
    # (его тянет libnativewindow) не находит atrace_update_tags/native_handle_* —
    # dlopen Turnip падает. Системные libcutils/libhardware резолвятся по NEEDED сами.
    # liblog/libnativewindow/libsync — тоже системные.
    "$TC/bin/llvm-readelf" -d "$OUT/libvulkan_freedreno.so" | grep NEEDED
}

case "${1:-all}" in
    box64)     build_box64 ;;
    wayland)   build_wayland ;;
    xkbcommon) build_xkbcommon ;;
    turnip)    build_turnip ;;
    all)       build_box64; build_wayland; build_xkbcommon; build_turnip ;;
    *) echo "цели: box64 | wayland | xkbcommon | turnip | all"; exit 1 ;;
esac
