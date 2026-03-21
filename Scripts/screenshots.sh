#!/bin/bash
#
# clipMyHorseVideo - simctl-based App Store Screenshot Pipeline
# =============================================================
#
# Captures screenshots by launching the app with --screenshot-mode --screenshot-screen <name>.
# Each screen launch: demo data → target screen → capture → terminate.
#
# Usage:
#   ./Scripts/screenshots.sh
#   ./Scripts/screenshots.sh --keep-simulators
#
# Output: fastlane/screenshots/en-GB/ (copied to en-US/)
#

set -euo pipefail

# -----------------------------------------------
# Configuration
# -----------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SHARED_LIB="${HOME}/.claude/shared/screenshot-lib.sh"

if [ ! -f "$SHARED_LIB" ]; then
    echo "Error: Shared screenshot library not found at ${SHARED_LIB}"
    exit 1
fi
source "$SHARED_LIB"

BUNDLE_ID="dev.dreamfold.clipMyHorseVideo"
PROJECT="${PROJECT_DIR}/clipMyHorseVideo.xcodeproj"
SCHEME="clipMyHorseVideo"
DERIVED_DATA="/tmp/clipMyHorseVideoScreenshotBuild"
OUTPUT_DIR="${PROJECT_DIR}/fastlane/screenshots"
SETTLE_TIME=4

# Device configurations
IPHONE_67_NAME="Screenshot_iPhone_6.7"
IPHONE_67_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"

IPHONE_61_NAME="Screenshot_iPhone_6.1"
IPHONE_61_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"

# Screens to capture
SCREENS=(
    "picker"
    "timeline"
    "trim"
    "export-settings"
)

FILENAMES=(
    "01_Build_Your_Round"
    "02_Timeline"
    "03_Trim_Editor"
    "04_Export_Settings"
)

# -----------------------------------------------
# Parse Arguments
# -----------------------------------------------

KEEP_SIMULATORS=false

for arg in "$@"; do
    case $arg in
        --keep-simulators) KEEP_SIMULATORS=true ;;
    esac
done

echo "==============================================="
echo "clipMyHorseVideo Screenshot Pipeline (simctl)"
echo "==============================================="
echo ""

# -----------------------------------------------
# Build Once
# -----------------------------------------------

echo "Step 1: Building app..."
screenshot_build_app "$PROJECT" "$SCHEME" "$DERIVED_DATA"

APP_BUNDLE=$(screenshot_find_app_bundle "$DERIVED_DATA" "clipMyHorseVideo")
if [ -z "$APP_BUNDLE" ]; then
    echo "Error: Could not find clipMyHorseVideo.app in derived data"
    exit 1
fi
echo "App bundle: ${APP_BUNDLE}"
echo ""

# -----------------------------------------------
# Capture Function
# -----------------------------------------------

capture_device() {
    local sim_name="$1"
    local sim_type="$2"
    local label="$3"
    local output_subdir="$4"

    local dest="${OUTPUT_DIR}/${output_subdir}"
    mkdir -p "$dest"

    echo "[$label] Creating simulator: ${sim_name}..."
    local udid
    udid=$(screenshot_create_simulator "$sim_name" "$sim_type")
    echo "[$label] Simulator UDID: ${udid}"

    echo "[$label] Booting simulator..."
    screenshot_boot_simulator "$udid"
    screenshot_override_status_bar "$udid"

    echo "[$label] Installing app..."
    screenshot_install_app "$udid" "$APP_BUNDLE"

    echo "[$label] Capturing ${#SCREENS[@]} screens..."
    for i in "${!SCREENS[@]}"; do
        local screen="${SCREENS[$i]}"
        local filename="${FILENAMES[$i]}"
        local output_path="${dest}/${filename}.png"
        screenshot_capture_screen "$udid" "$BUNDLE_ID" "$screen" "$output_path" "$SETTLE_TIME"
    done

    if [ "$KEEP_SIMULATORS" = false ]; then
        echo "[$label] Cleaning up simulator..."
        screenshot_delete_simulator "$udid"
    else
        echo "[$label] Keeping simulator (UDID: ${udid})"
    fi

    echo "[$label] Done — ${#SCREENS[@]} screenshots captured"
    echo ""
}

# -----------------------------------------------
# Capture Screenshots
# -----------------------------------------------

echo "Step 2: Capturing screenshots..."
echo ""

# 6.7" (required by App Store)
capture_device "$IPHONE_67_NAME" "$IPHONE_67_TYPE" "iPhone 6.7\"" "en-GB"

# 6.1" (secondary)
capture_device "$IPHONE_61_NAME" "$IPHONE_61_TYPE" "iPhone 6.1\"" "en-GB/6.1"

# -----------------------------------------------
# Copy Locale
# -----------------------------------------------

echo "Step 3: Copying en-GB to en-US..."
screenshot_copy_locale "${OUTPUT_DIR}/en-GB" "${OUTPUT_DIR}/en-US"
if [ -d "${OUTPUT_DIR}/en-GB/6.1" ]; then
    screenshot_copy_locale "${OUTPUT_DIR}/en-GB/6.1" "${OUTPUT_DIR}/en-US/6.1"
fi
echo ""

# -----------------------------------------------
# Summary
# -----------------------------------------------

echo "==============================================="
echo "Screenshot Pipeline Complete"
echo "==============================================="
echo ""

if [ -d "${OUTPUT_DIR}/en-GB" ]; then
    total_count=$(find "${OUTPUT_DIR}/en-GB" -maxdepth 1 -name "*.png" 2>/dev/null | wc -l | tr -d ' ')
    echo "Total: ${total_count} screenshots in en-GB/ (copied to en-US/)"
    echo ""
    find "${OUTPUT_DIR}/en-GB" -maxdepth 1 -name "*.png" -exec basename {} \; | sort | while read f; do echo "  $f"; done
    echo ""
fi

echo "Output: ${OUTPUT_DIR}/en-GB/ and ${OUTPUT_DIR}/en-US/"
echo ""
echo "Upload to App Store Connect with: fastlane upload_metadata"
