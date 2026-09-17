#!/usr/bin/bash

TARGET_ARCH="${TARGET_ARCH:-arm64-v8a}"

case "$TARGET_ARCH" in
	arm64-v8a) PLATFORM="linux/arm64/v8" ;;
	x86_64)    PLATFORM="linux/amd64" ;;
	*)         echo "Unsupported TARGET_ARCH: $TARGET_ARCH" > /dev/stderr; exit 1 ;;
esac

docker run --rm --platform=$PLATFORM -it "$@" godotengine/alpine-android:android-35-jdk17-$TARGET_ARCH /bin/bash
