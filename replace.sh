#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Missing config.env at: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# Ensure SKIPS is an actual bash array
eval "SKIPS=(${SKIPS[@]})"

# Get app name from argument
APP_ENV="$1"

# If no argument, show interactive menu
if [ -z "$APP_ENV" ]; then
    echo "📦 No app name provided."
    echo "📋 Available apps:"

    # List only directories (excluding files like README.md or scripts)
    OPTIONS=()
    i=1
    for d in "$BASE_DIR"/* ; do
        if [ -d "$d" ]; then
            folder=$(basename "$d")
            if [[ " ${SKIPS[@]} " =~ " $folder " ]]; then
                continue
            fi
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
fi

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