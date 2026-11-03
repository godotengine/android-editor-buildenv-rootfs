#!/bin/sh
# Uses Alpine's LLVM, make, yasm and python with the NDK payload.

set -e

NDK_ROOT="$1"
LLVM_BIN=/usr/lib/llvm21/bin
TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64"
MANIFEST="$NDK_ROOT/host-binaries.txt"

if [ -z "$NDK_ROOT" ] || ! [ -f "$MANIFEST" ]; then
	echo "Usage: $0 <ndk root containing host-binaries.txt>" >&2
	exit 1
fi

# Hack the NDK sysroot into the clang wrapper script.
write_clang_wrapper() {
	cat > "$1" <<EOF
#!/bin/sh
toolchain_dir=\$(cd "\$(dirname "\$(readlink -f "\$0")")/.." && pwd)
if [ "\$1" = "-cc1" ]; then
    exec "$LLVM_BIN/$2" "\$@"
fi
exec "$LLVM_BIN/$2" --sysroot="\$toolchain_dir/sysroot" -resource-dir="\$toolchain_dir/lib/clang/21" "\$@"
EOF
	chmod 755 "$1"
}

while read -r entry; do
	name=$(basename "$entry")
	target="$NDK_ROOT/$entry"
	case "$name" in
		clang|clang-21) write_clang_wrapper "$target" clang ;;
		clang++)        write_clang_wrapper "$target" clang++ ;;
		ld)             ln -s /usr/bin/ld.lld "$target" ;;
		*)
			if [ -e "$LLVM_BIN/$name" ]; then
				ln -s "$LLVM_BIN/$name" "$target"
			elif [ -e "/usr/bin/$name" ]; then
				ln -s "/usr/bin/$name" "$target"
			else
				echo "Not available in rootfs, skipping: $entry"
			fi
			;;
	esac
done < "$MANIFEST"
rm "$MANIFEST"

mkdir -p "$TOOLCHAIN/python3/bin"
ln -s /usr/bin/python3 "$TOOLCHAIN/python3/bin/python3"

ln -s /usr/lib/llvm21/lib/clang/21/include "$TOOLCHAIN/lib/clang/21/include"

# Alpine's clang unconditionally links -lssp_nonshared, which Bionic doesn't have.
for libdir in "$TOOLCHAIN"/sysroot/usr/lib/*-linux-android*; do
	"$LLVM_BIN/llvm-ar" rc "$libdir/libssp_nonshared.a"
done
