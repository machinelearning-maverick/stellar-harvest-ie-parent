#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# stellar-harvest-ie-parent/publish-modules-all.sh
# ------------------------------------------------------------
# Publishes modules to devpi, skipping any whose current version
# (as declared in their pyproject.toml) already exists on devpi.
#
# Usage:
#   ./publish-modules-all.sh                          # all modules, in dep order
#   ./publish-modules-all.sh stellar-harvest-ie-models stellar-harvest-ie-consumers
#   ./publish-modules-all.sh --dry-run                # show what would happen
#   ./publish-modules-all.sh --force                  # publish even if version exists (rarely needed)
#
# Notes:
#   - Version is read from each module's pyproject.toml (single source of truth).
#   - A module is SKIPPED if its current version is already on devpi.
#   - A module FAILS if its version is on devpi AND --force is passed AND devpi
#     rejects the re-upload (which is the normal, correct behavior).
#   - Requires credentials in EACH module's .env (TWINE_REPOSITORY_URL/USERNAME/PASSWORD).
# ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# ------------------------------------------------------------
# Dependency-ordered list — DO NOT reorder
# ------------------------------------------------------------
ALL_MODULES=(
  "stellar-harvest-ie-config"
  "stellar-harvest-ie-models"
  "stellar-harvest-ie-stream"
  "stellar-harvest-ie-store"
  "stellar-harvest-ie-producers"
  "stellar-harvest-ie-consumers"
  "stellar-harvest-ie-ml-stellar"
  "stellar-harvest-ie-ui"
)

# ------------------------------------------------------------
# Parse args
# ------------------------------------------------------------
DRY_RUN=false
FORCE=false
SELECTED_MODULES=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      ;;
    --force)
      FORCE=true
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--dry-run] [--force] [<module> ...]" >&2
      exit 1
      ;;
    *)
      SELECTED_MODULES+=("$1")
      ;;
  esac
  shift
done

# Resolve final module list with dependency ordering preserved
if [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
  SELECTED_MODULES=("${ALL_MODULES[@]}")
else
  for requested in "${SELECTED_MODULES[@]}"; do
    found=false
    for known in "${ALL_MODULES[@]}"; do
      [[ "$requested" == "$known" ]] && found=true && break
    done
    if [[ "$found" == false ]]; then
      echo "Unknown module: '$requested'" >&2
      echo "Known modules: ${ALL_MODULES[*]}" >&2
      exit 1
    fi
  done

  ORDERED=()
  for known in "${ALL_MODULES[@]}"; do
    for selected in "${SELECTED_MODULES[@]}"; do
      [[ "$known" == "$selected" ]] && ORDERED+=("$known") && break
    done
  done
  SELECTED_MODULES=("${ORDERED[@]}")
fi

# ------------------------------------------------------------
# Helper: extract value from a module's pyproject.toml
# ------------------------------------------------------------
read_pyproject_field() {
  local module_dir="$1"
  local field="$2"    # "name" or "version"
  python3 - <<EOF
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
try:
    with open("$module_dir/pyproject.toml", "rb") as f:
        data = tomllib.load(f)
    print(data["project"]["$field"])
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# ------------------------------------------------------------
# Helper: load TWINE_* creds from module .env (for the devpi check only)
# ------------------------------------------------------------
load_module_env() {
  local module_dir="$1"
  local env_file="$module_dir/.env"
  if [[ ! -f "$env_file" ]]; then
    return 1
  fi
  # shellcheck disable=SC1090
  set -a
  source "$env_file"
  set +a
  [[ -n "${TWINE_REPOSITORY_URL:-}" && -n "${TWINE_USERNAME:-}" && -n "${TWINE_PASSWORD:-}" ]]
}

# ------------------------------------------------------------
# Helper: check whether a specific version exists on devpi
# Returns: 0 if exists, 1 if not, 2 on error
# ------------------------------------------------------------
version_exists_on_devpi() {
  local name="$1"
  local version="$2"
  local url="${TWINE_REPOSITORY_URL%/}/${name}/${version}/"
  local code
  code=$(curl -sS -L -o /dev/null -w "%{http_code}" \
    -u "$TWINE_USERNAME:$TWINE_PASSWORD" \
    -H "Accept: application/json" \
    "$url" 2>/dev/null || echo "000")

  case "$code" in
    200) return 0 ;;
    404) return 1 ;;
    *)
      echo "  WARN: devpi check returned HTTP $code for $name==$version" >&2
      return 2
      ;;
  esac
}

# ------------------------------------------------------------
# Pre-flight: decide which modules to publish, skip, or flag as error
# ------------------------------------------------------------
echo "Pre-flight check across ${#SELECTED_MODULES[@]} module(s)..."
echo ""

TO_PUBLISH=()
TO_SKIP=()
PREFLIGHT_ERRORS=()

# Preserve outer shell state; each module's .env is loaded in a subshell below
for module in "${SELECTED_MODULES[@]}"; do
  module_dir="$PARENT_DIR/$module"

  if [[ ! -d "$module_dir" ]]; then
    echo "  [MISSING] $module — directory not found"
    PREFLIGHT_ERRORS+=("$module (directory not found)")
    continue
  fi

  if [[ ! -f "$module_dir/pyproject.toml" ]]; then
    echo "  [MISSING] $module — no pyproject.toml"
    PREFLIGHT_ERRORS+=("$module (no pyproject.toml)")
    continue
  fi

  # Extract version & name
  name=$(read_pyproject_field "$module_dir" "name") || {
    PREFLIGHT_ERRORS+=("$module (could not parse pyproject.toml)")
    continue
  }
  version=$(read_pyproject_field "$module_dir" "version") || {
    PREFLIGHT_ERRORS+=("$module (could not parse pyproject.toml)")
    continue
  }

  # Normalize name for devpi lookup (PEP 503: hyphens, lowercase)
  normalized_name=$(echo "$name" | tr '[:upper:]_' '[:lower:]-')

  # Check devpi in a subshell so we don't pollute outer env with TWINE_* creds
  check_result=$(
    if load_module_env "$module_dir"; then
      if version_exists_on_devpi "$normalized_name" "$version"; then
        echo "EXISTS"
      else
        rc=$?
        if [[ $rc -eq 1 ]]; then
          echo "MISSING"
        else
          echo "ERROR"
        fi
      fi
    else
      echo "NOENV"
    fi
  )

  case "$check_result" in
    EXISTS)
      if [[ "$FORCE" == true ]]; then
        echo "  [FORCE]   $module ($version) — exists on devpi, will attempt re-upload"
        TO_PUBLISH+=("$module")
      else
        echo "  [SKIP]    $module ($version) — already on devpi"
        TO_SKIP+=("$module ($version)")
      fi
      ;;
    MISSING)
      echo "  [PUBLISH] $module ($version) — new version"
      TO_PUBLISH+=("$module")
      ;;
    ERROR)
      echo "  [ERROR]   $module ($version) — devpi check failed"
      PREFLIGHT_ERRORS+=("$module (devpi check failed)")
      ;;
    NOENV)
      echo "  [ERROR]   $module — .env missing or incomplete TWINE_* vars"
      PREFLIGHT_ERRORS+=("$module (bad .env)")
      ;;
  esac
done

echo ""

# Bail out if any pre-flight errors
if [[ ${#PREFLIGHT_ERRORS[@]} -gt 0 ]]; then
  echo "Pre-flight errors:" >&2
  printf "  - %s\n" "${PREFLIGHT_ERRORS[@]}" >&2
  echo "" >&2
  echo "Fix these before publishing. Nothing was uploaded." >&2
  exit 1
fi

# Summary before acting
echo "----------------------------------------"
echo "Plan:"
echo "  To publish (${#TO_PUBLISH[@]}): ${TO_PUBLISH[*]:-none}"
echo "  To skip    (${#TO_SKIP[@]}): ${TO_SKIP[*]:-none}"
echo "----------------------------------------"
echo ""

if [[ ${#TO_PUBLISH[@]} -eq 0 ]]; then
  echo "Nothing to publish — all modules are up to date on devpi."
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run — stopping here. No modules were published."
  exit 0
fi

# ------------------------------------------------------------
# Publish phase
# ------------------------------------------------------------
PASSED=()
FAILED=()

for module in "${TO_PUBLISH[@]}"; do
  MODULE_DIR="$PARENT_DIR/$module"
  PUBLISH_SCRIPT="$MODULE_DIR/publish-module.sh"

  echo "----------------------------------------"
  echo "[$module]"

  if [[ ! -f "$PUBLISH_SCRIPT" ]]; then
    echo "publish-module.sh not found in $MODULE_DIR"
    FAILED+=("$module")
    continue
  fi

  if bash "$PUBLISH_SCRIPT" "$MODULE_DIR"; then
    PASSED+=("$module")
  else
    echo "Failed: $module"
    FAILED+=("$module")
  fi

  echo ""
done

# ------------------------------------------------------------
# Final summary
# ------------------------------------------------------------
echo "----------------------------------------"
echo "Summary"
echo "  Published (${#PASSED[@]}): ${PASSED[*]:-none}"
echo "  Skipped   (${#TO_SKIP[@]}): ${TO_SKIP[*]:-none}"
echo "  Failed    (${#FAILED[@]}): ${FAILED[*]:-none}"
echo "----------------------------------------"

if [[ ${#FAILED[@]} -gt 0 ]]; then
  exit 1
fi

echo "Done."