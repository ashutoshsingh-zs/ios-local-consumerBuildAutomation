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

source "$CONFIG_FILE"

# Validate environment
if [ -z "${CONSUMER_APP_DIR:-}" ]; then
    die "CONSUMER_APP_DIR must be set in $CONFIG_FILE"
fi

if [ ! -d "$CONSUMER_APP_DIR" ]; then
    die "CONSUMER_APP_DIR does not exist: $CONSUMER_APP_DIR"
fi

if [ ! -w "$CONSUMER_APP_DIR" ]; then
    die "CONSUMER_APP_DIR is not writable: $CONSUMER_APP_DIR"
fi

# Everything is derived from CONSUMER_APP_DIR — the Apps/ folder is the source,
# the rest of the checkout is the destination the config gets applied into.
APPS_DIR="$CONSUMER_APP_DIR/Apps"
DEST="$CONSUMER_APP_DIR"
CONFIG_DEST="$DEST/Configuration.xcconfig"
ASSETS_XCASSETS="$DEST/Consumer/Assets/Assets.xcassets"
ASSETS_DEST="$ASSETS_XCASSETS/_Configuration"
GOOGLE_SERVICE_DEST="$DEST/Consumer/GoogleService-Info.plist"
GOOGLE_SERVICE_DEFAULT="$APPS_DIR/_default/GoogleService-Info.plist"
PBXPROJ_PATH="$DEST/Consumer.xcodeproj/project.pbxproj"

if [ ! -d "$APPS_DIR" ]; then
    die "Apps folder not found at: $APPS_DIR"
fi

# ── Collect app folder names (skip the _default scaffold) ──
APPS_RAW=()
for d in "$APPS_DIR"/*; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    [ "$name" == "_default" ] && continue
    APPS_RAW+=("$name")
done

if [ "${#APPS_RAW[@]}" -eq 0 ]; then
    die "No app folders found under $APPS_DIR"
fi

ALL_APPS=()
while IFS= read -r name; do
    ALL_APPS+=("$name")
done < <(printf '%s\n' "${APPS_RAW[@]}" | sort)

# ── Actions ──

apply_app() {
    local app="$1"
    local src="$APPS_DIR/$app"

    echo ""
    echo "🚀 Applying configuration for: $app"

    # 1. Replace xcconfig
    if [ -f "$src/config.xcconfig" ]; then
        cp -f "$src/config.xcconfig" "$CONFIG_DEST"
        echo "✅ Config applied"
    else
        die "Missing config.xcconfig for $app at $src"
    fi

    # 2. Replace GoogleService-Info.plist (fall back to Apps/_default if the app has none)
    if [ -f "$src/GoogleService-Info.plist" ]; then
        cp -f "$src/GoogleService-Info.plist" "$GOOGLE_SERVICE_DEST"
        echo "✅ GoogleService-Info applied"
    elif [ -f "$GOOGLE_SERVICE_DEFAULT" ]; then
        cp -f "$GOOGLE_SERVICE_DEFAULT" "$GOOGLE_SERVICE_DEST"
        echo "⚠️  No GoogleService-Info.plist for $app — fell back to Apps/_default"
    else
        die "Missing GoogleService-Info.plist for $app (and no Apps/_default fallback)"
    fi

    # 3. Replace assets (Assets folder -> _Configuration)
    if [ -d "$src/Assets" ]; then
        rm -rf "$ASSETS_DEST"
        cp -R "$src/Assets" "$ASSETS_DEST"
        echo "✅ Assets replaced"
    else
        die "Missing Assets folder for $app at $src"
    fi

    # Nudge Xcode into noticing the swap
    touch "$PBXPROJ_PATH" 2>/dev/null || true
    find "$ASSETS_DEST" -name "Contents.json" -exec touch {} \; 2>/dev/null || true

    echo ""
    echo "🎉 Done. $app is now active — re-open Xcode (or close/reopen the project) to pick it up."
}

reset_changes() {
    echo ""
    log "⚠️  This restores Configuration.xcconfig, Consumer/GoogleService-Info.plist,"
    log "   and Consumer/Assets/Assets.xcassets/_Configuration in:"
    log "   $DEST"
    log "   to their last committed state. Nothing else in the repo is touched."
    echo ""
    echo "This action cannot be undone."
    echo -n "Proceed? (Y/N): "
    read -r answer
    echo ""

    case "$answer" in
        y|Y|yes|YES|Yes)
            if ! git -C "$DEST" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                die "DEST is not a git repository: $DEST"
            fi
            echo "🧹 Resetting..."
            git -C "$DEST" checkout -- \
                "Configuration.xcconfig" \
                "Consumer/GoogleService-Info.plist" \
                "Consumer/Assets/Assets.xcassets/_Configuration" \
                || die "Failed to reset. Do these paths exist in the last commit?"
            git -C "$DEST" clean -fd -- "Consumer/Assets/Assets.xcassets/_Configuration" >/dev/null 2>&1 || true
            echo ""
            log "✅ Done. Repo config reset."
            ;;
        *)
            log "❎ Cancelled. Nothing was changed."
            ;;
    esac
}

# ── Step 1: letter menu (groups apps by first letter; 1 extra entry to reset) ──

LETTERS=()
prev=""
for app in "${ALL_APPS[@]}"; do
    letter="$(printf '%s' "${app:0:1}" | tr '[:lower:]' '[:upper:]')"
    if [ "$letter" != "$prev" ]; then
        LETTERS+=("$letter")
        prev="$letter"
    fi
done

echo "📋 ${#ALL_APPS[@]} apps available under $APPS_DIR"
echo ""
echo "Select a letter:"
i=1
for letter in "${LETTERS[@]}"; do
    echo "  $i) $letter"
    ((i++))
done
RESET_INDEX=$i
echo "  $RESET_INDEX) Reset changes"
echo ""
read -p "👉 Choice: " letter_choice

if ! [[ "$letter_choice" =~ ^[0-9]+$ ]]; then
    echo ""
    die "Invalid input. Please enter a number."
fi

if [ "$letter_choice" -eq "$RESET_INDEX" ]; then
    reset_changes
    exit 0
fi

if [ "$letter_choice" -lt 1 ] || [ "$letter_choice" -gt "${#LETTERS[@]}" ]; then
    echo ""
    die "Invalid choice."
fi

CHOSEN_LETTER="${LETTERS[$((letter_choice - 1))]}"

# ── Step 2: app menu for that letter ──

MATCHES=()
for app in "${ALL_APPS[@]}"; do
    letter="$(printf '%s' "${app:0:1}" | tr '[:lower:]' '[:upper:]')"
    if [ "$letter" == "$CHOSEN_LETTER" ]; then
        MATCHES+=("$app")
    fi
done

echo ""
echo "Apps starting with '$CHOSEN_LETTER':"
i=1
for app in "${MATCHES[@]}"; do
    echo "  $i) $app"
    ((i++))
done
echo ""
read -p "👉 Choice: " app_choice

if ! [[ "$app_choice" =~ ^[0-9]+$ ]] || [ "$app_choice" -lt 1 ] || [ "$app_choice" -gt "${#MATCHES[@]}" ]; then
    echo ""
    die "Invalid choice."
fi

apply_app "${MATCHES[$((app_choice - 1))]}"
