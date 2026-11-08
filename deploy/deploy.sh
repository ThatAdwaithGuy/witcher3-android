#!/usr/bin/env bash
# ==============================================================================
# The Witcher 3: Wild Hunt - Android Deployment Script
# ==============================================================================
# Installs the APK and deploys runtime assets/configurations to the Android device.
# ==============================================================================

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$HERE/.." && pwd)
PKG="org.nx2a.t0100e67012924000"

# Default paths
APK_PATH="${APK_PATH:-}"
DATA_DIR="${DATA_DIR:-}"
INTERNAL_SHARED_DIR="/sdcard/TheWitcher3"
APP_PRIVATE_DIR="/sdcard/Android/data/$PKG/files"

echo "=========================================================="
echo "    The Witcher 3: Wild Hunt - Android Port Deployer     "
echo "=========================================================="
echo ""

# Find adb
if ! command -v adb >/dev/null 2>&1; then
    echo "Error: 'adb' not found. Please install Android platform-tools or add it to PATH." >&2
    exit 1
fi

DEVICE=$(adb devices | grep "device$" | head -n 1 | awk '{print $1}')
if [ -z "$DEVICE" ]; then
    echo "Error: No Android device detected over ADB." >&2
    echo "Please connect your phone via USB, enable USB Debugging, and authorize this PC." >&2
    exit 1
fi

echo "Connected device: $DEVICE"
MODEL=$(adb -s "$DEVICE" shell getprop ro.product.model || echo "Unknown")
SOC=$(adb -s "$DEVICE" shell getprop ro.soc.model || adb -s "$DEVICE" shell getprop ro.hardware || echo "Unknown")
echo "Device Model:     $MODEL"
echo "SoC / Hardware:   $SOC"
echo ""

# Locate APK
if [ -z "$APK_PATH" ]; then
    # Try common build output paths
    for candidate in \
        "$REPO_ROOT/TheWitcher3WildHunt.apk" \
        "$REPO_ROOT/build/TheWitcher3WildHunt.apk" \
        "$REPO_ROOT/out/TheWitcher3WildHunt.apk" \
        "/home/adwaith/Playground/witcher3/port/TheWitcher3WildHunt.apk"; do
        if [ -f "$candidate" ]; then
            APK_PATH="$candidate"
            break
        fi
    done
fi

if [ -n "$APK_PATH" ] && [ -f "$APK_PATH" ]; then
    echo "[1/4] Installing APK: $APK_PATH"
    adb -s "$DEVICE" install -r "$APK_PATH"
else
    echo "[1/4] Notice: No pre-built APK found at standard locations."
    echo "      Skipping APK installation. You can build it using ./build.sh."
fi

# Step 2: Grant Permissions
echo ""
echo "[2/4] Granting storage permissions (All Files Access)..."
adb -s "$DEVICE" shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow || true

# Step 3: Choose Destination on Internal Storage
echo ""
echo "[3/4] Game Data Destination on Internal Storage:"
echo "  Option 1: $INTERNAL_SHARED_DIR (RECOMMENDED: Visible in phone's file manager / PC MTP)"
echo "  Option 2: $APP_PRIVATE_DIR (App private directory)"
read -r -p "Choose destination [1 or 2, default: 1]: " DEST_CHOICE
DEST_CHOICE=${DEST_CHOICE:-1}

if [ "$DEST_CHOICE" = "1" ]; then
    TARGET_DIR="$INTERNAL_SHARED_DIR"
else
    TARGET_DIR="$APP_PRIVATE_DIR"
fi

echo "Target directory on device: $TARGET_DIR"
adb -s "$DEVICE" shell "mkdir -p $TARGET_DIR"

echo "Pushing configuration files..."
adb -s "$DEVICE" push "$HERE/env.txt" "$TARGET_DIR/env.txt"
adb -s "$DEVICE" push "$HERE/nx2a-data.json" "$TARGET_DIR/nx2a-data.json"
adb -s "$DEVICE" push "$HERE/nintendo_ext.ttf" "$TARGET_DIR/nintendo_ext.ttf"

# Check for additional data directory (shaders, drivers, mods, RomFS)
if [ -z "$DATA_DIR" ]; then
    for cand in "$HERE/data" "$REPO_ROOT/data" "/home/adwaith/Playground/witcher3/port/data"; do
        if [ -d "$cand" ]; then
            DATA_DIR="$cand"
            break
        fi
    done
fi

if [ -n "$DATA_DIR" ] && [ -d "$DATA_DIR" ]; then
    echo ""
    echo "Found game data directory at: $DATA_DIR"
    
    if [ -f "$DATA_DIR/shaders.dmsv" ]; then
        echo "Pushing shaders.dmsv..."
        adb -s "$DEVICE" push "$DATA_DIR/shaders.dmsv" "$TARGET_DIR/"
    fi

    if [ -d "$DATA_DIR/drivers" ]; then
        echo "Pushing drivers/..."
        adb -s "$DEVICE" push "$DATA_DIR/drivers" "$TARGET_DIR/"
    fi

    if [ -d "$DATA_DIR/mods" ]; then
        echo "Pushing mods/..."
        adb -s "$DEVICE" push "$DATA_DIR/mods" "$TARGET_DIR/"
    fi

    if [ -d "$DATA_DIR/RomFS" ]; then
        echo ""
        read -r -p "Push RomFS (14.5 GB) over ADB now? [y/N]: " PUSH_ROMFS
        if [[ "$PUSH_ROMFS" =~ ^[Yy]$ ]]; then
            echo "Pushing RomFS to $TARGET_DIR/RomFS (this may take 10-20 minutes)..."
            adb -s "$DEVICE" push "$DATA_DIR/RomFS" "$TARGET_DIR/"
        else
            echo "Skipping RomFS push."
            echo "Tip: You can manually copy the RomFS folder using USB File Transfer (MTP) to:"
            echo "     $TARGET_DIR/RomFS"
        fi
    fi
else
    echo "Note: No game data directory detected. Ensure game assets (RomFS, mods) are copied to:"
    echo "      $TARGET_DIR"
fi

# Step 4: Launch
echo ""
echo "[4/4] Deployment setup complete!"
read -r -p "Launch The Witcher 3 now? [Y/n]: " LAUNCH
if [[ ! "$LAUNCH" =~ ^[Nn]$ ]]; then
    echo "Starting app..."
    adb -s "$DEVICE" shell am start -n "$PKG/android.app.NativeActivity"
    echo ""
    echo "Streaming logs (Ctrl+C to stop)..."
    adb -s "$DEVICE" logcat -c
    adb -s "$DEVICE" logcat -s dmhost:V AndroidRuntime:E
fi
