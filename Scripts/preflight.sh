#!/bin/bash
#
# Pre-push validation script for clipMyHorseVideo
#
# Usage:
#   ./Scripts/preflight.sh          # Full: lint + build
#   ./Scripts/preflight.sh --quick  # Quick: lint only
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

QUICK=false
for arg in "$@"; do
    case $arg in
        --quick) QUICK=true ;;
    esac
done

echo "==============================================="
echo "clipMyHorseVideo Preflight"
echo "==============================================="
echo ""

ERRORS=0

# -----------------------------------------------
# SwiftLint
# -----------------------------------------------

echo "Step 1: SwiftLint..."
if command -v swiftlint &>/dev/null; then
    if ! swiftlint lint --strict --quiet --config "${PROJECT_DIR}/.swiftlint.yml" --path "${PROJECT_DIR}/clipMyHorseVideo" 2>&1; then
        echo "FAILED: SwiftLint found errors"
        ERRORS=$((ERRORS + 1))
    else
        echo "OK: SwiftLint passed"
    fi
else
    echo "SKIP: SwiftLint not installed"
fi
echo ""

# -----------------------------------------------
# MARKETING_VERSION consistency
# -----------------------------------------------

echo "Step 2: Version consistency..."
VERSIONS=$(grep 'MARKETING_VERSION' "${PROJECT_DIR}/clipMyHorseVideo.xcodeproj/project.pbxproj" | sed 's/.*= //' | sed 's/;.*//' | sort -u)
VERSION_COUNT=$(echo "$VERSIONS" | wc -l | tr -d ' ')

if [ "$VERSION_COUNT" -gt 1 ]; then
    echo "FAILED: Multiple MARKETING_VERSION values found:"
    echo "$VERSIONS"
    ERRORS=$((ERRORS + 1))
else
    echo "OK: MARKETING_VERSION consistent ($(echo "$VERSIONS" | head -1))"
fi
echo ""

# -----------------------------------------------
# Metadata limits
# -----------------------------------------------

echo "Step 3: Metadata limits..."
"${SCRIPT_DIR}/validate_metadata.sh" || ERRORS=$((ERRORS + 1))
echo ""

# -----------------------------------------------
# Build (unless --quick)
# -----------------------------------------------

if [ "$QUICK" = false ]; then
    echo "Step 4: Building..."
    if xcodebuild build \
        -project "${PROJECT_DIR}/clipMyHorseVideo.xcodeproj" \
        -scheme clipMyHorseVideo \
        -destination 'generic/platform=iOS Simulator' \
        -quiet 2>&1; then
        echo "OK: Build succeeded"
    else
        echo "FAILED: Build failed"
        ERRORS=$((ERRORS + 1))
    fi
    echo ""
fi

# -----------------------------------------------
# Summary
# -----------------------------------------------

echo "==============================================="
if [ $ERRORS -gt 0 ]; then
    echo "PREFLIGHT FAILED — ${ERRORS} check(s) failed"
    exit 1
else
    echo "PREFLIGHT PASSED"
fi
echo "==============================================="
