#!/usr/bin/env bash
# Build the horizon_math static library for the current iOS SDK and drop
# the artefact where Xcode expects it (see pbxproj: LIBRARY_SEARCH_PATHS).
#
# Invoked by the "Build Rust math" Run Script build phase on every Xcode
# build. Can also be run standalone from the repo root:
#
#     ./rust/build_ios.sh iphoneos         # device
#     ./rust/build_ios.sh iphonesimulator  # sim
#     ./rust/build_ios.sh both             # convenience: both at once
#
# Honours $CONFIGURATION (debug|release). Defaults to release.

set -eo pipefail

PLATFORM="${1:-${PLATFORM_NAME:-both}}"
CONFIGURATION="${2:-${CONFIGURATION:-Release}}"

HERE="$(cd "$(dirname "$0")" && pwd)"
CRATE_DIR="$HERE/horizon_math"
IOS_OUT_ROOT="$HERE/../ios/Rust"

mkdir -p "$IOS_OUT_ROOT/device" "$IOS_OUT_ROOT/sim"

if [ -f "$HOME/.cargo/env" ]; then
    # Xcode's Run Script phase runs in a sanitised shell that does not
    # import the user's shell dotfiles. Pull cargo onto PATH explicitly.
    # shellcheck disable=SC1090
    . "$HOME/.cargo/env"
fi

CARGO_FLAG=""
BUILD_SUBDIR=debug
case "${CONFIGURATION}" in
    Release|release|Profile|profile)
        CARGO_FLAG="--release"
        BUILD_SUBDIR=release
        ;;
esac

build_one_triple() {
    local triple="$1"
    local out_path="$2"
    echo "==> cargo build --manifest-path $CRATE_DIR/Cargo.toml --target $triple $CARGO_FLAG"
    if [ -n "$CARGO_FLAG" ]; then
        (cd "$CRATE_DIR" && cargo build "$CARGO_FLAG" --target "$triple")
    else
        (cd "$CRATE_DIR" && cargo build --target "$triple")
    fi
    local src="$CRATE_DIR/target/$triple/$BUILD_SUBDIR/libhorizon_math.a"
    if [ ! -f "$src" ]; then
        echo "ERROR: expected $src to exist" >&2
        exit 1
    fi
    cp -f "$src" "$out_path"
}

build_device() {
    build_one_triple aarch64-apple-ios "$IOS_OUT_ROOT/device/libhorizon_math.a"
    echo "==> wrote device/libhorizon_math.a"
}

# The iOS simulator must ship a universal (arm64 + x86_64) archive. On
# Apple Silicon macs Flutter picks x86_64-apple-ios13.0-simulator for the
# Clang target by default; on Intel macs it is x86_64 natively. Shipping
# both arches via `lipo -create` keeps the single `-lhorizon_math` link
# flag working against either host.
build_sim() {
    build_one_triple aarch64-apple-ios-sim \
        "$IOS_OUT_ROOT/sim/libhorizon_math-arm64.a"
    build_one_triple x86_64-apple-ios \
        "$IOS_OUT_ROOT/sim/libhorizon_math-x86_64.a"
    lipo -create \
        "$IOS_OUT_ROOT/sim/libhorizon_math-arm64.a" \
        "$IOS_OUT_ROOT/sim/libhorizon_math-x86_64.a" \
        -output "$IOS_OUT_ROOT/sim/libhorizon_math.a"
    rm -f "$IOS_OUT_ROOT/sim/libhorizon_math-arm64.a" \
          "$IOS_OUT_ROOT/sim/libhorizon_math-x86_64.a"
    echo "==> wrote sim/libhorizon_math.a (universal arm64 + x86_64)"
}

case "$PLATFORM" in
    iphoneos)
        build_device
        ;;
    iphonesimulator)
        build_sim
        ;;
    both|all)
        build_device
        build_sim
        ;;
    *)
        echo "Unknown platform: $PLATFORM (expected iphoneos|iphonesimulator|both)" >&2
        exit 1
        ;;
esac
