#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

# Small helpers
log() { echo "🔧 $*"; }
die() { echo "❌ $*" >&2; exit 1; }

if [ ! -f "$CONFIG_FILE" ]; then
    die "Missing config.env at: $CONFIG_FILE"
fi

# Interactive menu
source "$CONFIG_FILE"

# Validate environment
: "Checking required variables"
if [ -z "${BASE_DIR:-}" ] || [ -z "${DEST:-}" ]; then
    die "BASE_DIR and DEST must be set in $CONFIG_FILE"
fi

if [ ! -d "$BASE_DIR" ]; then
    die "BASE_DIR does not exist: $BASE_DIR"
fi

if [ ! -d "$DEST" ]; then
    die "DEST does not exist: $DEST"
fi

if [ ! -w "$DEST" ]; then
    die "DEST is not writable: $DEST"
fi

echo "📋 Available apps:"

# List only directories (excluding files like README.md or scripts)
OPTIONS=()
i=1
for d in "$BASE_DIR"/* ; do
    if [ -d "$d" ]; then
        folder=$(basename "$d")
        OPTIONS+=("$folder")
        echo "  $i) $folder"
        ((i++))
    fi
done

echo ""
read -p "👉 Choose an app number: " choice

if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo ""
    echo "❌ Invalid input. Please enter a number."
    exit 1
fi

if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#OPTIONS[@]}" ]; then
    echo ""
    echo "❌ Invalid choice."
    exit 1
fi

APP_ENV="${OPTIONS[$choice-1]}"
echo "🟢 Selected: $APP_ENV"
echo ""

# Now proceed normally
SRC="$BASE_DIR/$APP_ENV"

echo "🚀 Applying configs for: $APP_ENV"

# 1. Replace xcconfig
if [ -f "$SRC/Configuration.xcconfig" ]; then
    cp -f "$SRC/Configuration.xcconfig" "$DEST/Configuration.xcconfig"
    echo "✅ Config applied"
else
    echo "❌ Missing Configuration.xcconfig for $APP_ENV"
    echo "Suggestion: run ./reset.sh to restore default config."
    exit 1
fi

# 2. Replace GoogleService-Info.plist
if [ -f "$SRC/GoogleService-Info.plist" ]; then
    cp -f "$SRC/GoogleService-Info.plist" "$DEST/Consumer/GoogleService-Info.plist"
    echo "✅ GoogleService-Info applied"
else
    echo "❌ Missing GoogleService-Info.plist for $APP_ENV"
    echo "Suggestion: run ./reset.sh to restore default config."
    exit 1
fi

# 3. Replace assets (_Configuration folder)
if [ -d "$SRC/_Configuration" ]; then
    rm -rf "$DEST/Consumer/Assets/Assets.xcassets/_Configuration"
    cp -R "$SRC/_Configuration" "$DEST/Consumer/Assets/Assets.xcassets/"
    echo "✅ Assets replaced"
else
    echo "❌ Missing _Configuration for $APP_ENV"
    echo "Suggestion: run ./reset.sh to restore default config."
    exit 1
fi

echo ""
echo "🎉 Done. Build kar de boss."