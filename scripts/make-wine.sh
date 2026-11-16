#!/usr/bin/env bash
# Патчи и флаги своей сборки Wine 10.10 (x86_64 glibc-гость для box64).
# Сборку в 40+ минут сам не запускает: MAKE_WINE=1 ./make-wine.sh чтобы configure+make.
#
#   export WINE_SRC=/path/to/wine-10.10
#   pcrt-build/make-wine.sh
#
# Патча «перенести user_shared_data» нет и не должно быть: ntdll.dll читает
# KUSER абсолютным testb $1,[0x7ffe0308]. Фолбэк в virtual.c удалить.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${WINE_SRC:?укажите WINE_SRC — каталог исходников Wine 10.10}"
PREFIX="${WINE_PREFIX:-$HOME/pcrt-wine-prefix}"

apply_patch() {
    local patch=$1
    if patch -d "$WINE_SRC" -p1 --forward --dry-run < "$patch" >/dev/null 2>&1; then
        patch -d "$WINE_SRC" -p1 --forward < "$patch"
        echo "applied $(basename "$patch")"
    elif patch -d "$WINE_SRC" -p1 --reverse --dry-run < "$patch" >/dev/null 2>&1; then
        echo "already applied $(basename "$patch")"
    else
        echo "patch failed: $patch" >&2
        exit 1
    fi
}

apply_patch "$HERE/wine/0001-wineserver-tmpdir-env.patch"

echo
echo "configure (хостовый gcc + mingw-w64, это не NDK):"
echo "  cd $WINE_SRC"
echo "  ./configure --enable-archs=x86_64 --without-x --without-preloader --prefix=$PREFIX"
echo "wayland-клиент соберётся сам, если на хосте есть wayland-client.pc (нужен winewayland)."
echo "Фолбэк KUSER в dlls/ntdll/unix/virtual.c не добавлять."

if [ "${MAKE_WINE:-0}" != "1" ]; then
    echo "make не запущен. MAKE_WINE=1 чтобы собрать."
    exit 0
fi

cd "$WINE_SRC"
./configure --enable-archs=x86_64 --without-x --without-preloader --prefix="$PREFIX"
make -j"$(nproc)"
echo "prefix будет после: make install  ->  $PREFIX"
