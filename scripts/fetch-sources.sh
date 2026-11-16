#!/usr/bin/env bash
# Fetch the exact upstream sources of the third-party components shipped with
# Matrux (ru.matrux.app) and apply our patches to them.
#
#   scripts/fetch-sources.sh --all        # default: box64 + wine + proot
#   scripts/fetch-sources.sh --box64      # only box64
#   scripts/fetch-sources.sh --wine --proot
#
# Environment:
#   SRC_DIR   where the trees are unpacked   (default: <repo>/upstream)
#   CACHE     where tarballs are kept        (default: <repo>/.cache)
#
# Idempotent: existing tarballs are checksum-verified and reused, already applied
# patches are detected and skipped.  Re-running is a no-op.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SRC_DIR="${SRC_DIR:-$ROOT/upstream}"
CACHE="${CACHE:-$ROOT/.cache}"

# Pinned versions and their tarball checksums.
BOX64_REF="52db1d07ac8f198fd0bbef7e28f677116a688f3f"   # v0.4.5 line, the commit we build
BOX64_URL="https://github.com/ptitSeb/box64/archive/$BOX64_REF.tar.gz"
BOX64_SHA="435a63efa57ca1d3f1328d6ce9730559e6a90be4a82e5ddeb5bbd3a36eafdedc"

WINE_VER="11.16"
WINE_URL="https://dl.winehq.org/wine/source/11.x/wine-$WINE_VER.tar.xz"
WINE_SHA="c66e2090343dcd727f7f7fd2f87ee0bfb0b118790c1d745ab7b8a4c3a4197f2f"

PROOT_TAG="v5.1.107.102"                                # Termux proot build we ship
PROOT_URL="https://github.com/termux/proot/archive/refs/tags/$PROOT_TAG.tar.gz"
PROOT_SHA="36fb68838d86e491bc577064e23d365ea936e03ded4e90f62dc540907c04f385"

WANT_BOX64=0 WANT_WINE=0 WANT_PROOT=0

usage() {
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
    case "$arg" in
        --all)    WANT_BOX64=1; WANT_WINE=1; WANT_PROOT=1 ;;
        --box64)  WANT_BOX64=1 ;;
        --wine)   WANT_WINE=1 ;;
        --proot)  WANT_PROOT=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $arg (try --help)" >&2; exit 2 ;;
    esac
done

if [ $((WANT_BOX64 + WANT_WINE + WANT_PROOT)) -eq 0 ]; then
    WANT_BOX64=1; WANT_WINE=1; WANT_PROOT=1
fi

mkdir -p "$CACHE" "$SRC_DIR"

need() {
    command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1" >&2; exit 1; }
}
need curl
need tar
need sha256sum
need patch

# download <url> <file> <sha256>
download() {
    local url="$1" file="$2" want="$3" got
    if [ -f "$CACHE/$file" ]; then
        got="$(sha256sum "$CACHE/$file" | cut -d' ' -f1)"
        if [ "$got" = "$want" ]; then
            echo "cached   $file"
            return 0
        fi
        echo "checksum mismatch for cached $file, re-downloading" >&2
        rm -f "$CACHE/$file"
    fi
    echo "download $url"
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$CACHE/$file.part" "$url"
    got="$(sha256sum "$CACHE/$file.part" | cut -d' ' -f1)"
    if [ "$got" != "$want" ]; then
        rm -f "$CACHE/$file.part"
        echo "checksum mismatch for $url" >&2
        echo "  expected $want" >&2
        echo "  got      $got" >&2
        exit 1
    fi
    mv "$CACHE/$file.part" "$CACHE/$file"
    echo "ok       $file"
}

# unpack <tarball> <dest-dir>: strips the single top-level directory
unpack() {
    local file="$1" dest="$2"
    if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
        echo "exists   $dest"
        return 0
    fi
    mkdir -p "$dest"
    echo "unpack   $file -> $dest"
    tar -xf "$CACHE/$file" -C "$dest" --strip-components=1
}

# apply_patch <src-dir> <patch-file>: idempotent, p1.
# A stamp in <src>/.matrux-patches/ records that we applied a patch, because
# later patches in a series touch the same regions and a reverse dry-run of an
# earlier one cannot succeed on the fully patched tree.
apply_patch() {
    local src="$1" p="$2" name stamp
    name="$(basename "$p")"
    stamp="$src/.matrux-patches/$name.done"
    if [ -f "$stamp" ]; then
        echo "  already applied $name"
        return 0
    fi
    mkdir -p "$src/.matrux-patches"
    if patch -d "$src" -p1 --forward --dry-run < "$p" >/dev/null 2>&1; then
        patch -d "$src" -p1 --forward --no-backup-if-mismatch < "$p" >/dev/null
        : > "$stamp"
        echo "  applied $name"
    elif patch -d "$src" -p1 --reverse --dry-run < "$p" >/dev/null 2>&1; then
        : > "$stamp"
        echo "  already applied $name"
    else
        echo "  FAILED $name — the tree does not match the patch context" >&2
        exit 1
    fi
}

if [ "$WANT_BOX64" -eq 1 ]; then
    echo "== box64 $BOX64_REF (v0.4.5)"
    download "$BOX64_URL" "box64-$BOX64_REF.tar.gz" "$BOX64_SHA"
    unpack "box64-$BOX64_REF.tar.gz" "$SRC_DIR/box64"
    n=0
    for p in "$ROOT"/box64/*.patch; do
        apply_patch "$SRC_DIR/box64" "$p"
        n=$((n + 1))
    done
    echo "   $n patches processed -> $SRC_DIR/box64"
fi

if [ "$WANT_WINE" -eq 1 ]; then
    echo "== wine $WINE_VER (LGPL-2.1)"
    download "$WINE_URL" "wine-$WINE_VER.tar.xz" "$WINE_SHA"
    unpack "wine-$WINE_VER.tar.xz" "$SRC_DIR/wine"
    apply_patch "$SRC_DIR/wine" "$ROOT/wine/0001-wineserver-tmpdir-env.patch"
    echo "   source ready -> $SRC_DIR/wine"
    echo "   build: WINE_SRC=$SRC_DIR/wine scripts/make-wine.sh"
fi

if [ "$WANT_PROOT" -eq 1 ]; then
    echo "== proot $PROOT_TAG (GPL-2.0, unmodified)"
    download "$PROOT_URL" "proot-$PROOT_TAG.tar.gz" "$PROOT_SHA"
    unpack "proot-$PROOT_TAG.tar.gz" "$SRC_DIR/proot"
    echo "   upstream source -> $SRC_DIR/proot (no Matrux patches by design)"
fi

echo
echo "done. sources in $SRC_DIR, tarballs in $CACHE"
