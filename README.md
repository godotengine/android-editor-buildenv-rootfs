Rootfs for Godot Android Build Environment (or GABE)
====================================================

This repo contains the Linux rootfs used by the Godot Android Build Environment (or GABE).

See https://github.com/godotengine/android-editor-buildenv-app

Build prequisites
-----------------

- Android SDK with NDK
- Docker (configured for [multi-platform builds](https://docs.docker.com/build/building/multi-platform/))
- cmake
- ninja-build
- bison
- flex

Build process
-------------

Ensure the Git submodules are checked out:

```bash
git submodule update --init --recursive
```

Build the Android SDK tools:

```bash
# If you've built before and want to get a clean build, remove the old build directory:
rm -rf ./thirdparty/android-sdk-tools/build/

# Build it (substitute the path to NDK on your system):
ANDROID_NDK_ROOT=$HOME/Android/Sdk/ndk/28.1.13356709 ./thirdparty/android-sdk-tools/build.sh
```

Build the rootfs:

```bash
./docker/build-rootfs.sh
```

You can open a shell in the rootfs via Docker by running:

```bash
./docker/test-via-docker.sh
```

The rootfs archive will be placed under `./docker/build/`

Building for other architectures
--------------------------------

By default, all the scripts above will target arm64-v8, however, you can set the `TARGET_ARCH`
variable to target other architectures.

The currently supported architectures include:

- `arm64-v8a`
- `x86_64`

Troubleshooting
---------------

### "Permission denied" when running `docker`

If you get a "permission denied" error when running Docker, it most likely means
that you need to add your user to the `docker` group:

```bash
sudo usermod -aG docker $USER
```

... and then restart your computer.

### `build-rootfs.sh` fails with "exec format error"

If running `./docker/build-rootfs.sh` fails, and there is "exec format error" somewhere in
the output (it won't be the last line, unfortunately), then it means that Docker isn't
setup to do multi-platform builds.

Per the [official documentation](https://docs.docker.com/build/building/multi-platform/)
running this command _may_ setup everything for you:

```bash
docker run --privileged --rm tonistiigi/binfmt --install all
```

However, if that doesn't work, you can try installing QEMU (with ARM64 support) and
configuring `binfmt` using system packages.

For example, on Fedora this has been known to work:

```bash
sudo dnf install qemu-user-static-aarch64
sudo systemctl restart systemd-binfmt
```
