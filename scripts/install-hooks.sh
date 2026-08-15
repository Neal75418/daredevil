#!/bin/bash
# Install git hooks for Daredevil development
# Run once after cloning: ./scripts/install-hooks.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(git rev-parse --show-toplevel)/.git/hooks"

for hook in pre-commit post-commit; do
  cp "$SCRIPT_DIR/$hook" "$HOOKS_DIR/$hook"
  chmod +x "$HOOKS_DIR/$hook"
  echo "  ✅ $hook"
done

echo "✅ Git hooks installed successfully"
