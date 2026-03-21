#!/bin/bash
#
# Validate App Store metadata character limits
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
METADATA_DIR="${PROJECT_DIR}/fastlane/metadata/en-GB"

ERRORS=0

check_limit() {
    local file="$1"
    local limit="$2"
    local label="$3"

    if [ -f "$file" ]; then
        local length
        length=$(wc -m < "$file" | tr -d ' ')
        if [ "$length" -gt "$limit" ]; then
            echo "ERROR: ${label} is ${length} chars (limit: ${limit})"
            ERRORS=$((ERRORS + 1))
        else
            echo "OK: ${label} — ${length}/${limit} chars"
        fi
    fi
}

if [ -d "$METADATA_DIR" ]; then
    echo "Checking App Store metadata limits..."
    echo ""
    check_limit "${METADATA_DIR}/name.txt" 30 "App Name"
    check_limit "${METADATA_DIR}/subtitle.txt" 30 "Subtitle"
    check_limit "${METADATA_DIR}/keywords.txt" 100 "Keywords"
    check_limit "${METADATA_DIR}/description.txt" 4000 "Description"
    check_limit "${METADATA_DIR}/promotional_text.txt" 170 "Promotional Text"
    check_limit "${METADATA_DIR}/release_notes.txt" 4000 "Release Notes"
    echo ""

    if [ $ERRORS -gt 0 ]; then
        echo "FAILED: ${ERRORS} metadata field(s) exceed limits"
        exit 1
    else
        echo "All metadata within limits"
    fi
else
    echo "No metadata directory found at ${METADATA_DIR} — skipping"
fi
