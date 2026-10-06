#!/usr/bin/env bash
#
# Run the curlonaut.nvim test suite with plenary's busted harness.
#
# Usage:
#   ./run_tests.sh                 # run everything under tests/specs
#   ./run_tests.sh tests/specs/unit
#   ./run_tests.sh tests/specs/e2e
#
# Environment overrides:
#   PLENARY_PATH  path to a plenary.nvim checkout
#   NVIM          neovim binary to use

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLENARY_PATH="${PLENARY_PATH:-$HOME/.local/share/nvim/lazy/plenary.nvim}"
NVIM="${NVIM:-nvim}"
SPECS="${1:-$ROOT/tests/specs}"
MINIMAL_INIT="$ROOT/tests/minimal_init.lua"

export PLENARY_PATH

if ! command -v "$NVIM" >/dev/null 2>&1; then
  echo "error: neovim binary '$NVIM' not found (set NVIM=...)" >&2
  exit 127
fi

if [ ! -d "$PLENARY_PATH" ]; then
  echo "error: plenary.nvim not found at: $PLENARY_PATH" >&2
  echo "       set PLENARY_PATH=/path/to/plenary.nvim" >&2
  exit 1
fi

for bin in curl python3; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: '$bin' is required to run the test suite" >&2
    exit 1
  fi
done

echo "curlonaut.nvim test suite"
echo "  nvim:    $("$NVIM" --version | head -n1)"
echo "  specs:   $SPECS"
echo "  plenary: $PLENARY_PATH"
echo

exec "$NVIM" --headless --noplugin \
  -u "$MINIMAL_INIT" \
  -c "PlenaryBustedDirectory $SPECS { minimal_init = '$MINIMAL_INIT' }"
