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

TARGET="$DEST"

if [ -z "${TARGET:-}" ]; then
    die "DEST must be set in $CONFIG_FILE"
fi

if [ ! -d "$TARGET" ]; then
    die "DEST does not exist: $TARGET"
fi

if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "DEST is not a git repository: $TARGET"
fi

log "⚠️  WARNING: This will remove ALL uncommitted changes from:"
log "   $TARGET"
echo ""
echo "This action cannot be undone."
echo -n "Proceed? (Y/N): "
read answer
echo ""

case "$answer" in
    y|Y|yes|YES|Yes)
        echo "🧹 Cleaning repo..."
        git -C "$TARGET" cleanall || die "❌ Failed to clean the repository."
        echo ""
        log "✅ Done. Repo cleaned."
        ;;
    *)
        log "❎ Cancelled. Nothing was changed."
        ;;
esac
