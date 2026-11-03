#!/bin/bash

TARGET_ARCH="${TARGET_ARCH:-arm64-v8a}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALPINE_ANDROID_DIR="$SCRIPT_DIR/../thirdparty/alpine-android"
BUILD_DIR="$SCRIPT_DIR/build"

function die() {
    echo "$@" > /dev/stderr
    exit 1
}

case "$TARGET_ARCH" in
	arm64-v8a) PLATFORM="linux/arm64/v8" ;;
	x86_64)    PLATFORM="linux/amd64" ;;
	*)         die "Unsupported TARGET_ARCH: $TARGET_ARCH" ;;
esac

NDK_PAYLOAD="$SCRIPT_DIR/ndk/payload"
[ -f "$NDK_PAYLOAD/source.properties" ] \
	|| die "NDK payload not found at $NDK_PAYLOAD - run ./thirdparty/ndk/build.sh first"
NDK_VERSION=$(sed -n 's/^Pkg.Revision *= *//p' "$NDK_PAYLOAD/source.properties")

ROOTFS_NAME=alpine-android-35-jdk17-$TARGET_ARCH
BASE_IMAGE_NAME=alvrme/alpine-android-base:jdk17-$TARGET_ARCH
ANDROID_IMAGE_NAME=alvrme/alpine-android:android-35-jdk17-$TARGET_ARCH
IMAGE_NAME=godotengine/alpine-android:android-35-jdk17-$TARGET_ARCH

# Build the alpine-android images.

docker build "$ALPINE_ANDROID_DIR/docker" --platform=$PLATFORM -f "$ALPINE_ANDROID_DIR/docker/base.Dockerfile" -t $BASE_IMAGE_NAME \
	--build-arg="JDK_VERSION=17" --build-arg="CMDLINE_VERSION=latest" --build-arg="SDK_TOOLS_VERSION=13114758" \
    || die "Failed to build Docker base image"

docker build "$ALPINE_ANDROID_DIR/docker" --platform=$PLATFORM -f "$ALPINE_ANDROID_DIR/docker/android.Dockerfile" -t $ANDROID_IMAGE_NAME \
	--build-context "alvrme/alpine-android-base:jdk17=docker-image://$BASE_IMAGE_NAME" \
	--build-arg="JDK_VERSION=17" --build-arg="BUILD_TOOLS=35.0.0" --build-arg="TARGET_SDK=35" \
    || die "Failed to build Docker Android image"

docker build "$SCRIPT_DIR" --platform=$PLATFORM -f "$SCRIPT_DIR/Dockerfile.godot" -t $IMAGE_NAME \
	--build-arg="JDK_VERSION=17" --build-arg="BUILD_TOOLS=35.0.0" --build-arg="TARGET_SDK=35" --build-arg="TARGET_ARCH=$TARGET_ARCH" \
	--build-arg="NDK_VERSION=$NDK_VERSION" \
    || die "Failed to build Docker Godot image"

# Run the custom built tools to confirm they work.
docker run --rm -i --platform=$PLATFORM $IMAGE_NAME sh <<'EOF' \
	|| die "The custom built Android SDK tools or the NDK don't work in the image"
check() {
    expect="$1"
    shift
    if ! "$@" 2>&1 | grep -q "$expect"; then
        echo "FAILED: $*" >&2
        exit 1
    fi
}

check "Android Asset Packaging Tool" aapt version
check "Android Asset Packaging Tool" aapt2 version
check "AIDL Compiler" aidl --help
check "The Android Open Source Project" dexdump --help
check "Zip alignment utility" zipalign
check "Split APK" split-select --help

NDK_BIN="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
cat > /tmp/hello.cpp <<'CPP'
#include <arm_neon.h>
#include <string>
#include <cstdio>
int main() { std::string s = "hello"; printf("%s %d\n", s.c_str(), vgetq_lane_s32(vdupq_n_s32(7), 0)); return 0; }
CPP
"$NDK_BIN/aarch64-linux-android24-clang++" -fstack-protector-strong /tmp/hello.cpp -o /tmp/hello \
    || { echo "FAILED: compiling with the NDK" >&2; exit 1; }
"$NDK_BIN/llvm-strip" /tmp/hello \
    || { echo "FAILED: llvm-strip" >&2; exit 1; }
check "AArch64" "$NDK_BIN/llvm-readelf" --file-header /tmp/hello

mkdir -p /tmp/ndk-build-test/jni
cp /tmp/hello.cpp /tmp/ndk-build-test/jni/
cat > /tmp/ndk-build-test/jni/Android.mk <<'MK'
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := hello
LOCAL_SRC_FILES := hello.cpp
include $(BUILD_EXECUTABLE)
MK
"$ANDROID_NDK_ROOT/ndk-build" -C /tmp/ndk-build-test NDK_PROJECT_PATH=/tmp/ndk-build-test APP_ABI=arm64-v8a APP_PLATFORM=android-24 APP_STL=c++_static >/dev/null \
    || { echo "FAILED: ndk-build" >&2; exit 1; }
check "AArch64" "$NDK_BIN/llvm-readelf" --file-header /tmp/ndk-build-test/libs/arm64-v8a/hello
EOF

mkdir -p "$BUILD_DIR"

CONTAINER_ID=$(docker create --platform=$PLATFORM $IMAGE_NAME)
docker export --output="$BUILD_DIR/$ROOTFS_NAME.tar" $CONTAINER_ID
#docker inspect $IMAGE_NAME --format='{{json .Config.Env}}' | python -c 'import json, sys; d=json.load(sys.stdin); print(*d, sep="\n")' > "$BUILD_DIR/$ROOTFS_NAME.env"
docker rm $CONTAINER_ID

rm -f "$BUILD_DIR/$ROOTFS_NAME.tar.xz"
(cd "$BUILD_DIR" && xz -T0 $ROOTFS_NAME.tar)

echo "Build completed successfully."
