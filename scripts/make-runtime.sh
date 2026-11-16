#!/usr/bin/env bash
# Одна команда: box64 (патчи 0001–0004) + bionic wayland/xkbcommon/Turnip.
# Wine сюда не входит — см. make-wine.sh.
#
#   export ANDROID_NDK_HOME=/path/to/android-ndk-r27c
#   pcrt-build/make-runtime.sh
#
# libvulkan_matrux.so собирает Gradle из app/src/main/cpp/vkshim.c, не этот скрипт.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
OUT="$REPO/app/src/main/jniLibs/arm64-v8a"

"$HERE/build-android-deps.sh" all

required=(
    libbox64.so
    libwayland-client.so
    libwayland-egl.so
    libwayland-cursor.so
    libxkbcommon.so
    libxkbregistry.so
    libvulkan_freedreno.so
)
optional=(
    libvulkan_matrux.so
    libwayland-server.so
)

echo
echo "артефакты $OUT"
missing=0
for name in "${required[@]}" "${optional[@]}"; do
    path="$OUT/$name"
    if [ -f "$path" ]; then
        printf "  %8s  %s\n" "$(du -h "$path" | cut -f1)" "$name"
    elif printf '%s\n' "${required[@]}" | grep -qx "$name"; then
        echo "  MISSING  $name"
        missing=1
    else
        echo "  (нет, это gradle/пресборка)  $name"
    fi
done

if [ "$missing" -ne 0 ]; then
    echo "не хватает обязательных библиотек" >&2
    exit 1
fi
echo "OK"
