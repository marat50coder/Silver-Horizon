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
#
# CI (Codemagic) does not ship cargo. Two fallbacks, in order:
#   1. Use the prebuilt ios/Rust/device/libhorizon_math.a committed to git
#      (App Store archives only need the device slice).
#   2. If that file is missing, install rustup into $HOME/.cargo and
#      compile from source.

set -eo pipefail

PLATFORM="${1:-${PLATFORM_NAME:-both}}"
CONFIGURATION="${2:-${CONFIGURATION:-Release}}"

HERE="$(cd "$(dirname "$0")" && pwd)"
CRATE_DIR="$HERE/horizon_math"
IOS_OUT_ROOT="$HERE/../ios/Rust"

mkdir -p "$IOS_OUT_ROOT/device" "$IOS_OUT_ROOT/sim"

# Xcode's Run Script phase runs in a sanitised shell that does not import
# the user's dotfiles. rustup lives in ~/.cargo/bin on both local macs
# and Codemagic builders after a bootstrap.
export PATH="${HOME}/.cargo/bin:${PATH}"
if [ -f "${HOME}/.cargo/env" ]; then
    # shellcheck disable=SC1090
    . "${HOME}/.cargo/env"
fi

have_cargo() {
    command -v cargo >/dev/null 2>&1
}

bootstrap_cargo() {
    if have_cargo; then
        return 0
    fi
    echo "==> cargo not on PATH; installing rustup (Codemagic macs do not ship Rust)"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --default-toolchain stable --no-modify-path
    export PATH="${HOME}/.cargo/bin:${PATH}"
    if [ -f "${HOME}/.cargo/env" ]; then
        # shellcheck disable=SC1090
        . "${HOME}/.cargo/env"
    fi
    if ! have_cargo; then
        echo "ERROR: rustup finished but cargo is still missing from PATH=$PATH" >&2
        return 1
    fi
}

# Returns 0 if the caller should skip compiling and use the prebuilt
# artefact at $1. Returns 1 if cargo is available and a rebuild should
# happen. Exits the script if neither cargo nor the prebuilt file exist
# and rustup cannot be installed.
maybe_use_prebuilt() {
    local dest="$1"
    if have_cargo; then
        return 1
    fi
    if [ -f "$dest" ]; then
        echo "==> cargo not installed; linking prebuilt $dest"
        lipo -info "$dest" || true
        return 0
    fi
    echo "==> cargo missing and no prebuilt at $dest"
    bootstrap_cargo || {
        echo "ERROR: cannot produce $dest" >&2
        echo "Install https://rustup.rs, or commit ios/Rust/device/libhorizon_math.a" >&2
        exit 1
    }
    return 1
}

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
    rustup target add "$triple" >/dev/null
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
    local dest="$IOS_OUT_ROOT/device/libhorizon_math.a"
    if maybe_use_prebuilt "$dest"; then
        return 0
    fi
    build_one_triple aarch64-apple-ios "$dest"
    echo "==> wrote device/libhorizon_math.a"
}

# The iOS simulator must ship a universal (arm64 + x86_64) archive. On
# Apple Silicon macs Flutter picks x86_64-apple-ios13.0-simulator for the
# Clang target by default; on Intel macs it is x86_64 natively. Shipping
# both arches via `lipo -create` keeps the single `-lhorizon_math` link
# flag working against either host.
build_sim() {
    local dest="$IOS_OUT_ROOT/sim/libhorizon_math.a"
    if maybe_use_prebuilt "$dest"; then
        return 0
    fi
    build_one_triple aarch64-apple-ios-sim \
        "$IOS_OUT_ROOT/sim/libhorizon_math-arm64.a"
    build_one_triple x86_64-apple-ios \
        "$IOS_OUT_ROOT/sim/libhorizon_math-x86_64.a"
    lipo -create \
        "$IOS_OUT_ROOT/sim/libhorizon_math-arm64.a" \
        "$IOS_OUT_ROOT/sim/libhorizon_math-x86_64.a" \
        -output "$dest"
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
