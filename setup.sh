#!/bin/bash

set -e

# Script ki directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# List of scripts to make executable
SCRIPTS_TO_CHMOD=(
  "apply.sh"
  "reset.sh"
)

# List of git aliases
declare -A GIT_ALIASES=(
  [cleanall]="!git restore . && git clean -fd"
)


# Make scripts executable
echo "🔧 Making selected scripts executable..."

for script in "${SCRIPTS_TO_CHMOD[@]}"; do
  SCRIPT_PATH="$SCRIPT_DIR/$script"

  if [[ -f "$SCRIPT_PATH" ]]; then
    chmod +x "$SCRIPT_PATH"
    echo "  ✔ chmod +x $script"
  else
    echo "  ⚠️ $script not found, skipping"
  fi
done

# Setup git aliases
echo "🔗 Setting up git aliases..."

for alias in "${!GIT_ALIASES[@]}"; do
  git config --global "alias.$alias" "${GIT_ALIASES[$alias]}"
  echo "  ✔ git $alias"
done

echo "✅ Setup done."