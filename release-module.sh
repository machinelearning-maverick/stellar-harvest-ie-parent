#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# stellar-harvest-ie-parent/release-module.sh
# ------------------------------------------------------------
# Usage:
#   ./release-module.sh <module-name> <patch|minor|major>
#
# Example:
#   ./release-module.sh stellar-harvest-ie-consumers patch
#
# What it does:
#   1. Bumps version in <module>/pyproject.toml
#   2. Publishes to devpi (via the module's publish-module.sh)
#   3. Updates the matching *_VERSION var in deployment/.env
#
# After this, run:
#   cd stellar-harvest-ie-deployment && docker compose up -d --build
# ------------------------------------------------------------

MODULE="${1:?Usage: $0 <module-name> <patch|minor|major>}"
BUMP="${2:?Usage: $0 <module-name> <patch|minor|major>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
MODULE_DIR="$PARENT_DIR/$MODULE"
ENV_FILE="$PARENT_DIR/stellar-harvest-ie-deployment/.env"

[[ -d "$MODULE_DIR" ]]   || { echo "Module dir not found: $MODULE_DIR" >&2; exit 1; }
[[ -f "$ENV_FILE"   ]]   || { echo ".env not found: $ENV_FILE"        >&2; exit 1; }

# Map module name → .env var name
# stellar-harvest-ie-consumers → CONSUMERS_VERSION
SUFFIX="${MODULE#stellar-harvest-ie-}"
ENV_VAR="$(echo "$SUFFIX" | tr '[:lower:]-' '[:upper:]_')_VERSION"

# --- 1. Bump version in pyproject.toml --------------------------------
NEW_VERSION=$(python3 - <<EOF
import re, sys, tomllib
from pathlib import Path

pyproject = Path("$MODULE_DIR/pyproject.toml")
text = pyproject.read_text()
data = tomllib.loads(text)
current = data["project"]["version"]
major, minor, patch = (int(x) for x in current.split("."))

bump = "$BUMP"
if   bump == "patch": patch += 1
elif bump == "minor": minor, patch = minor + 1, 0
elif bump == "major": major, minor, patch = major + 1, 0, 0
else: sys.exit(f"Unknown bump: {bump}")

new = f"{major}.{minor}.{patch}"
# Surgical replacement — only the version line, not transitive deps
new_text = re.sub(
    r'(^version\s*=\s*")[^"]+(")',
    rf'\g<1>{new}\g<2>',
    text,
    count=1,
    flags=re.MULTILINE,
)
pyproject.write_text(new_text)
print(new)
EOF
)

echo "Bumped $MODULE: → $NEW_VERSION"

# --- 2. Publish --------------------------------------------------------
PUBLISH_SCRIPT="$MODULE_DIR/publish-module.sh"
[[ -f "$PUBLISH_SCRIPT" ]] || { echo "publish-module.sh missing" >&2; exit 1; }
bash "$PUBLISH_SCRIPT" "$MODULE_DIR"

# --- 3. Update .env ----------------------------------------------------
# Works whether the line exists or not.
if grep -q "^${ENV_VAR}=" "$ENV_FILE"; then
  # macOS/BSD sed compatibility: use a temp file rather than -i ''
  sed "s|^${ENV_VAR}=.*|${ENV_VAR}=${NEW_VERSION}|" "$ENV_FILE" > "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"
else
  echo "${ENV_VAR}=${NEW_VERSION}" >> "$ENV_FILE"
fi

echo ""
echo "Done: ${ENV_VAR}=${NEW_VERSION} in $ENV_FILE"
echo ""
echo "Next step:"
echo "  cd stellar-harvest-ie-deployment && docker compose up -d --build"