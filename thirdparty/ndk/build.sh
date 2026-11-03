#!/bin/bash

NDK_VERSION="${NDK_VERSION:-29.0.14206865}"
HOST_TAG=linux-x86_64

if [ -z "$ANDROID_NDK_ROOT" ]; then
	echo "ERROR: The ANDROID_NDK_ROOT environment variable must be defined" > /dev/stderr
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/../../docker/ndk/payload"
TOOLCHAIN_DIR="toolchains/llvm/prebuilt/$HOST_TAG"

function die() {
    echo "$@" > /dev/stderr
    exit 1
}

INSTALLED_VERSION=$(sed -n 's/^Pkg.Revision *= *//p' "$ANDROID_NDK_ROOT/source.properties")
if [ "$INSTALLED_VERSION" != "$NDK_VERSION" ]; then
	die "ANDROID_NDK_ROOT contains NDK version '$INSTALLED_VERSION' but '$NDK_VERSION' is required"
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
(cd "$ANDROID_NDK_ROOT" && tar -c \
	--exclude="./$TOOLCHAIN_DIR/python3" \
	--exclude="./$TOOLCHAIN_DIR/musl" \
	--exclude="./shader-tools" \
	--exclude="./simpleperf" \
	.) | (cd "$OUTPUT_DIR" && tar -x) \
	|| die "Unable to copy the NDK"

find "$OUTPUT_DIR/$TOOLCHAIN_DIR/lib" -mindepth 1 -maxdepth 1 ! -name clang -exec rm -rf {} + \
	|| die "Unable to remove host libraries"
rm -rf "$OUTPUT_DIR/$TOOLCHAIN_DIR/lib/clang/21/include" \
	|| die "Unable to remove compiler headers"

MANIFEST="$OUTPUT_DIR/host-binaries.txt"
: > "$MANIFEST"
for dir in "$TOOLCHAIN_DIR/bin" "$TOOLCHAIN_DIR/lib/clang/21/bin" "prebuilt/$HOST_TAG/bin"; do
	for f in "$OUTPUT_DIR/$dir"/*; do
		[ -e "$f" ] || [ -L "$f" ] || continue
		if [ -L "$f" ] || file -b "$f" | grep -q '^ELF'; then
			echo "$dir/$(basename "$f")" >> "$MANIFEST"
			rm "$f" || die "Unable to remove $f"
		fi
	done
done

(cd "$OUTPUT_DIR" && patch -p1 < "$SCRIPT_DIR/patches/ndk_bin_common.sh.patch") \
	|| die "Unable to apply ndk_bin_common.sh patch"

echo "NDK payload written to $OUTPUT_DIR"
