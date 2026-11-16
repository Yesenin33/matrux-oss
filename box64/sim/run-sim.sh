#!/usr/bin/env bash
# Проверка box64 (ANDROID-ветки кода) без телефона: aarch64-сборка с -DANDROID=1 на
# glibc (bionic-функции — стабы из bionic_compat.*), запуск в qemu-aarch64 на x86_64 glibc
# бинарях хоста. Ловит ошибки ABI гостя (sigaction, ucontext, long double, точка входа).
# Не ловит различия самой bionic (раскладка addrinfo и т.п.) — там «нативная» libc = glibc.
#
#   apt install qemu-user-static gcc-aarch64-linux-gnu libc6-dev-arm64-cross cmake ninja-build
#   pcrt-build/box64/sim/run-sim.sh /path/to/box64-src   # исходники с наложенным патчем
set -euo pipefail
SRC=$(cd "${1:?путь к исходникам box64}" && pwd)
SIM=$(cd "$(dirname "$0")" && pwd)
B="$SRC/build-asim"

cat > "$SIM/tc-aarch64.cmake" <<'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_ASM_COMPILER aarch64-linux-gnu-gcc)
EOF
aarch64-linux-gnu-gcc -c -O2 -fPIC "$SIM/bionic_compat.c" -o "$SIM/bionic_compat.o"
cmake -S "$SRC" -B "$B" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$SIM/tc-aarch64.cmake" \
    -DARM_DYNAREC=1 -DARM64=1 -DANDROID=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_FLAGS="-include $SIM/bionic_compat.h" -DCMAKE_C_STANDARD_LIBRARIES="$SIM/bionic_compat.o"
ninja -C "$B" -k 0 box64 || true
# env.c и wrappedlibc.c объявляют свои shm_open/qsort_r/semun (их нет в bionic) — собираем отдельно
for obj in CMakeFiles/mainobj.dir/src/tools/env.c.o CMakeFiles/mainobj.dir/src/wrapped/wrappedlibc.c.o; do
    cmd=$(ninja -C "$B" -t commands "$obj" | tail -1)
    cmd=${cmd/aarch64-linux-gnu-gcc /aarch64-linux-gnu-gcc -include $SIM/pre.h }
    (cd "$B" && eval "$cmd -include $SIM/post.h")
done
(cd "$B" && eval "$(ninja -t commands box64 | tail -1)")

gcc -O1 -o "$SIM/test_libc" "$SIM/test_libc.c"
gcc -O1 -o "$SIM/test_signals" "$SIM/test_signals.c"
export QEMU_LD_PREFIX=/usr/aarch64-linux-gnu BOX64_NOBANNER=1 BOX64_SHM_DIR=/tmp
for t in /bin/true "$SIM/test_libc" "$SIM/test_signals"; do
    echo "== $t"
    qemu-aarch64-static "$B/box64" "$t" && echo "rc=0" || echo "rc=$?"
done
