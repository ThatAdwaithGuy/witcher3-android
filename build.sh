#!/usr/bin/env bash
# ==============================================================================
# The Witcher 3: Wild Hunt - Android Port Build Script
# ==============================================================================
# Builds the native host library (libdmhost.so), adrenotools driver hooks,
# and packages the final signed APK.
# ==============================================================================

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"

# Defaults
GAME_ID="0100E67012924000"
APP_NAME="The Witcher 3: Wild Hunt"
PKG_NAME="org.nx2a.t0100e67012924000"
VERSION_CODE="8"
VERSION_NAME="3.7"
JOBS=$(nproc 2>/dev/null || echo 8)
BUILD_TYPE="debug"
OUT_DIR="$HERE/build"
HOST_OUT="$OUT_DIR/host"
APK_OUT="$OUT_DIR/TheWitcher3WildHunt.apk"
KEY_FILE="${SIGNING_KEY:-$HOME/.config/nx2android/signing-key.json}"
CUSTOM_DRIVER=""
CLEAN=0

# Detect NDK
NDK_PATH="${ANDROID_NDK_HOME:-${NDK_HOME:-}}"
if [ -z "$NDK_PATH" ] || [ ! -d "$NDK_PATH" ]; then
    NDK_PATH=""
    for cand in \
        "$HOME/Android/Sdk/ndk/27.2.12479018" \
        "$HOME/Android/Sdk/ndk/29.0.14206865" \
        "$HOME/Android/Sdk/ndk/27.1.12297006" \
        "$HOME/Android/Sdk/ndk/26.3.11579264" \
        "/opt/android-ndk" \
        "/opt/android-sdk/ndk-bundle"; do
        if [ -d "$cand" ]; then
            NDK_PATH="$cand"
            break
        fi
    done
fi

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ndk)
            NDK_PATH="$2"
            shift 2
            ;;
        --release)
            BUILD_TYPE="release"
            shift
            ;;
        --debug)
            BUILD_TYPE="debug"
            shift
            ;;
        --version-code)
            VERSION_CODE="$2"
            shift 2
            ;;
        --version-name)
            VERSION_NAME="$2"
            shift 2
            ;;
        --jobs|-j)
            JOBS="$2"
            shift 2
            ;;
        --key)
            KEY_FILE="$2"
            shift 2
            ;;
        --driver)
            CUSTOM_DRIVER="$2"
            shift 2
            ;;
        --out)
            APK_OUT="$2"
            shift 2
            ;;
        --clean)
            CLEAN=1
            shift
            ;;
        -h|--help)
            echo "Usage: ./build.sh [options]"
            echo ""
            echo "Options:"
            echo "  --ndk <path>            Path to Android NDK (r27 recommended)"
            echo "  --release               Build release binaries (DM_RELEASE, stripped)"
            echo "  --debug                 Build debug binaries (default)"
            echo "  --version-code <N>      Android versionCode (default: 8)"
            echo "  --version-name <str>    Android versionName (default: 3.7)"
            echo "  --jobs <N>              Parallel compile jobs (default: nproc)"
            echo "  --driver <path>         Include a custom Vulkan driver in APK (e.g. libvulkan_radeon.so)"
            echo "  --key <path>            Path to signing-key.json"
            echo "  --out <path>            Output APK destination (default: build/TheWitcher3WildHunt.apk)"
            echo "  --clean                 Clean build directory before building"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

echo "=========================================================="
echo "    The Witcher 3: Wild Hunt - Android Port Builder      "
echo "=========================================================="
echo "Game ID:        $GAME_ID"
echo "Package:        $PKG_NAME"
echo "Build Type:     $BUILD_TYPE"
echo "Version:        $VERSION_NAME (code $VERSION_CODE)"
echo "Parallel Jobs:  $JOBS"
echo "Output APK:     $APK_OUT"

if [ -z "$NDK_PATH" ] || [ ! -d "$NDK_PATH" ]; then
    echo "Error: Android NDK not found. Specify with --ndk <path> or export ANDROID_NDK_HOME." >&2
    exit 1
fi
echo "Using NDK:      $NDK_PATH"
echo ""

if [ "$CLEAN" -eq 1 ]; then
    echo "Cleaning build directory..."
    rm -rf "$OUT_DIR"
fi

mkdir -p "$HOST_OUT"
mkdir -p "$(dirname "$APK_OUT")"

# ------------------------------------------------------------------------------
# 1. Compile Host Library & Adrenotools
# ------------------------------------------------------------------------------
echo "--- [1/2] Compiling native host library and adrenotools ---"

BUILD_PY_ARGS=(
    "$HERE/nxnative/dm/android/build.py"
    --game "$GAME_ID"
    --ndk "$NDK_PATH"
    --out "$HOST_OUT"
    --lib
    --adrenotools
    --jobs "$JOBS"
)

if [ "$BUILD_TYPE" = "release" ]; then
    BUILD_PY_ARGS+=(--release)
fi

python3 "${BUILD_PY_ARGS[@]}"

if [ ! -f "$HOST_OUT/libdmhost.so" ]; then
    echo "Error: libdmhost.so failed to build." >&2
    exit 1
fi

echo "Built: $HOST_OUT/libdmhost.so ($(du -h "$HOST_OUT/libdmhost.so" | cut -f1))"

# ------------------------------------------------------------------------------
# 2. Package APK
# ------------------------------------------------------------------------------
echo ""
echo "--- [2/2] Packaging APK ---"

MKAPK_ARGS=(
    "$HERE/nxnative/dm/android/apk/mkapk.py"
    "$HOST_OUT/libdmhost.so"
    "$APK_OUT"
)

if [ -f "$KEY_FILE" ]; then
    MKAPK_ARGS+=("$KEY_FILE")
fi

MKAPK_ARGS+=(
    --package "$PKG_NAME"
    --label "$APP_NAME"
    --lib dmhost
    --version-code "$VERSION_CODE"
    --version-name "$VERSION_NAME"
    --landscape
    --icon "$HERE/packaging/icons/icon.png"
    --icon-fg "$HERE/packaging/icons/icon_fg.png"
    --icon-bg "$HERE/packaging/icons/icon_bg.png"
    --asset "overlay/theme.tsv=$HERE/nxnative/dm/android/themes/ergo/theme.tsv"
    --asset "overlay/phone.png=$HERE/nxnative/dm/android/themes/ergo/phone.png"
    --asset "overlay/tablet.png=$HERE/nxnative/dm/android/themes/ergo/tablet.png"
)

# Bundle adrenotools hook libraries
for hook in libadrenotools.so libhook_impl.so libmain_hook.so libfile_redirect_hook.so libgsl_alloc_hook.so; do
    if [ -f "$HOST_OUT/$hook" ]; then
        MKAPK_ARGS+=(--extra-so "$HOST_OUT/$hook")
    fi
done

# Check if a custom driver should be bundled
if [ -n "$CUSTOM_DRIVER" ] && [ -f "$CUSTOM_DRIVER" ]; then
    echo "Bundling specified custom driver: $CUSTOM_DRIVER"
    MKAPK_ARGS+=(--extra-so "$CUSTOM_DRIVER")
elif [ -f "$HOST_OUT/libvulkan_radeon.so" ]; then
    echo "Bundling pre-staged driver: $HOST_OUT/libvulkan_radeon.so"
    MKAPK_ARGS+=(--extra-so "$HOST_OUT/libvulkan_radeon.so")
elif [ -f "/home/adwaith/Playground/witcher3/nsp/TheWitcher3WildHunt-data/drivers/libvulkan_radeon.so" ]; then
    echo "Bundling RADV driver from system cache: libvulkan_radeon.so"
    MKAPK_ARGS+=(--extra-so "/home/adwaith/Playground/witcher3/nsp/TheWitcher3WildHunt-data/drivers/libvulkan_radeon.so")
fi

python3 "${MKAPK_ARGS[@]}"

echo ""
echo "=========================================================="
echo "    Build Successful!                                    "
echo "=========================================================="
echo "APK Output: $APK_OUT ($(du -h "$APK_OUT" | cut -f1))"
echo ""
echo "To deploy to your device, run:"
echo "  ./deploy/deploy.sh"
echo "=========================================================="
