#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Missing config.env at: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

TARGET="$DEST"

echo "⚠️  WARNING: This will remove ALL uncommitted changes from:"
echo "   $TARGET"
echo ""
echo "This action cannot be undone."
echo -n "Proceed? (Y/N): "
read answer
echo ""

case "$answer" in
    y|Y|yes|YES|Yes)
        echo "🧹 Cleaning repo..."
        git -C "$TARGET" cleanall
        echo ""
        echo "✅ Done. Repo cleaned."
        ;;
    *)
        echo "❎ Cancelled. Nothing was changed."
        ;;
esac
