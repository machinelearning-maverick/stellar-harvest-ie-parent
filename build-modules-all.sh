#!/bin/bash
# Run this once after cloning all repos:
#   bash stellar-harvest-insight-engine/stellar-harvest-ie-parent/build-modules-all.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Copying workspace pyproject.toml to $PARENT_DIR"
cp "$SCRIPT_DIR/pyproject.toml" "$PARENT_DIR/pyproject.toml"

cd "$PARENT_DIR"
pwd

echo "Running uv sync..."
uv sync