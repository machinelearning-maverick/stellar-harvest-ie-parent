#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# stellar-harvest-parent/publish-modules-all.sh
# ------------------------------------------------------------
# Usage:
#   ./publish-modules-all.sh                          # publish all modules in order
#   ./publish-modules-all.sh module-a module-c        # publish specific modules only
#   ./publish-modules-all.sh --version 0.2.1          # pass version to each module
#
# Prereqs:
#   - Each module has publish-module.sh at its root
#   - Each module has .env with TWINE_* vars configured
# ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# ------------------------------------------------------------
# Dependency-ordered list - DO NOT reorder
# modules that depend on others must come after their dependencies
# ------------------------------------------------------------
ALL_MODULES=(
  "stellar-harvest-ie-config"   # no internal dependencies
  "stellar-harvest-ie-models"
  "stellar-harvest-ie-stream"
  "stellar-harvest-ie-store"
  "stellar-harvest-ie-producers"
  "stellar-harvest-ie-consumers"
  "stellar-harvest-ie-ui"
)

# parse args
VERSION=""
SELECTED_MODULES=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--version)
      shift
      VERSION="$1"
      ;;
    -*)
      echo "Unknown option $1" >&2
      exit 1
      ;;
    *)
      SELECTED_MODULES+=("$1")
      ;;
  esac
  shift
done

# if no modules specified, publish all in order
if [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
  SELECTED_MODULES=("${ALL_MODULES[@]}")
else
  # validate requested modules exist in the known list
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

  # reorder selected modules to respect dependency order
  ORDERED=()
  for known in "${ALL_MODULES[@]}"; do
    for selected in "${SELECTED_MODULES[@]}"; do
      [[ "$known" == "$selected" ]] && ORDERED+=("$known") && break
    done
  done
  SELECTED_MODULES=("${ORDERED[@]}")
fi

echo "Publishing ${#SELECTED_MODULES[@]} module(s): ${SELECTED_MODULES[*]}"
[[ -n "$VERSION" ]] && echo "   – version: $VERSION"
echo ""

# track results
PASSED=()
FAILED=()

for module in "${SELECTED_MODULES[@]}"; do
  MODULE_DIR="$PARENT_DIR/$module"
  PUBLISH_SCRIPT="$MODULE_DIR/publish-module.sh"

  echo "----------------------------------------"
  echo "[$module]"

  if [[ ! -d "$MODULE_DIR" ]]; then
    echo "Directory not found: $MODULE_DIR"
    FAILED+=("$module")
    continue
  fi

  if [[ ! -f "$PUBLISH_SCRIPT" ]]; then
    echo "publish-module.sh not found in $MODULE_DIR"
    FAILED+=("$module")
    continue
  fi

  # build args to forward
  ARGS=("$MODULE_DIR")
  [[ -n "$VERSION" ]] && ARGS+=(--version "$VERSION")

  if bash "$PUBLISH_SCRIPT" "${ARGS[@]}"; then
    PASSED+=("$module")
  else
    echo "Failed: $module"
    FAILED+=("$module")
  fi

  echo ""
done

# summary
echo "----------------------------------------"
echo "Summary"
echo "  Passed (${#PASSED[@]}): ${PASSED[*]:-none}"
echo "  Failed (${#FAILED[@]}): ${FAILED[*]:-none}"

if [[ ${#FAILED[@]} -gt 0 ]]; then
  exit 1
fi

echo "----------------------------------------"
echo "All modules published successfully!"