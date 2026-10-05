#!/usr/bin/env bash
# Build the horizon_math cdylib for every Android ABI the Play Store needs
# and drop the artefacts where Gradle picks them up for packaging into the
# APK/AAB (android/app/src/main/jniLibs/<abi>/libhorizon_math.so).
#
# Invoked automatically from android/app/build.gradle.kts via the
# `buildRustMath` task before preBuild. Can also be run standalone:
#
#     ./rust/build_android.sh                 # release, all 4 ABIs
#     ./rust/build_android.sh debug           # debug profile
#     ANDROID_NDK_HOME=... ./rust/build_android.sh
#
# Requires:
#   • rustup with the android target triples installed:
#       aarch64-linux-android, armv7-linux-androideabi,
#       x86_64-linux-android, i686-linux-android
#   • cargo-ndk (`cargo install cargo-ndk`)
#   • Android NDK at $ANDROID_NDK_HOME. If unset, the script falls back to
#     the newest NDK under $ANDROID_SDK_ROOT (or ~/Library/Android/sdk on
#     macOS, ~/Android/Sdk on Linux).
#
# Everything is a one-shot build — the output is small (~200–300 KB per
# ABI), there is no stable artefact caching between runs.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CRATE_DIR="$HERE/horizon_math"
PROJECT_ROOT="$HERE/.."
JNI_LIBS_DIR="$PROJECT_ROOT/android/app/src/main/jniLibs"

# Gradle's Exec task runs this script in a sanitised shell that does NOT
# import the user's shell dotfiles. rustup / cargo live in ~/.cargo/bin
# on every mac + linux dev box and on Codemagic / Bitrise CI builders
# after a rustup bootstrap. Add it to PATH ourselves so `cargo` resolves
# regardless of the launching shell. ~/.cargo/env (written by rustup)
# also tweaks RUSTUP_HOME / CARGO_HOME when they are not the defaults.
if [ -n "${HOME:-}" ]; then
    export PATH="${HOME}/.cargo/bin:${PATH}"
    if [ -f "${HOME}/.cargo/env" ]; then
        # shellcheck disable=SC1090,SC1091
        . "${HOME}/.cargo/env"
    fi
fi

PROFILE="${1:-release}"
CARGO_FLAG=""
case "$PROFILE" in
    release) CARGO_FLAG="--release" ;;
    debug|dev) CARGO_FLAG="" ;;
    *) echo "ERROR: unknown profile '$PROFILE' (expected release|debug)" >&2; exit 1 ;;
esac

# ABIs the APK/AAB actually ships. Must match the `abiFilters` list in
# android/app/build.gradle.kts. x86 is excluded because the Flutter engine
# does not ship a 32-bit x86 libflutter.so — a Rust slice for it would be
# an orphan.
ANDROID_ABIS=(arm64-v8a armeabi-v7a x86_64)
RUST_TRIPLES=(aarch64-linux-android armv7-linux-androideabi x86_64-linux-android)

# Resolve the NDK: explicit > ANDROID_SDK_ROOT/ndk > ANDROID_HOME/ndk >
# ~/Library/Android/sdk/ndk > ~/Android/Sdk/ndk. Picks the highest version.
pick_newest_ndk() {
    local sdk="$1"
    if [ -d "$sdk/ndk" ]; then
        ls -1 "$sdk/ndk" 2>/dev/null | sort -V | tail -1 | awk -v s="$sdk" '{print s "/ndk/" $0}'
    fi
}

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
    for candidate_sdk in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" \
                         "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
        [ -n "$candidate_sdk" ] || continue
        [ -d "$candidate_sdk" ] || continue
        resolved="$(pick_newest_ndk "$candidate_sdk")"
        if [ -n "$resolved" ] && [ -d "$resolved" ]; then
            export ANDROID_NDK_HOME="$resolved"
            break
        fi
    done
fi

if [ -z "${ANDROID_NDK_HOME:-}" ] || [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "ERROR: ANDROID_NDK_HOME is not set and no NDK was discovered under"
    echo "       \$ANDROID_SDK_ROOT, \$ANDROID_HOME, or the default macOS/Linux"
    echo "       SDK locations. Install an NDK via sdkmanager, or point"
    echo "       ANDROID_NDK_HOME at an existing one." >&2
    exit 1
fi

echo "==> ANDROID_NDK_HOME=$ANDROID_NDK_HOME"

if ! command -v cargo >/dev/null 2>&1; then
    echo "ERROR: cargo not on PATH. Install Rust via https://rustup.rs." >&2
    exit 1
fi
if ! cargo ndk --version >/dev/null 2>&1; then
    echo "==> installing cargo-ndk (first run only)"
    cargo install cargo-ndk
fi

# Ensure every Rust Android target triple is installed. `rustup target
# add` is idempotent and cheap after the first run.
for triple in "${RUST_TRIPLES[@]}"; do
    rustup target add "$triple" >/dev/null
done

mkdir -p "$JNI_LIBS_DIR"

ABI_ARGS=()
for abi in "${ANDROID_ABIS[@]}"; do
    ABI_ARGS+=(-t "$abi")
done

echo "==> building horizon_math ($PROFILE) for ${ANDROID_ABIS[*]}"
cd "$CRATE_DIR"
# -o puts the .so files under <jniLibs>/<abi>/libhorizon_math.so, which is
# exactly the layout Gradle expects — no post-copy step needed.
if [ -n "$CARGO_FLAG" ]; then
    cargo ndk "${ABI_ARGS[@]}" -o "$JNI_LIBS_DIR" build "$CARGO_FLAG"
else
    cargo ndk "${ABI_ARGS[@]}" -o "$JNI_LIBS_DIR" build
fi

echo "==> wrote:"
find "$JNI_LIBS_DIR" -name 'libhorizon_math.so' -maxdepth 2 -print
