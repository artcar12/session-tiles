#!/bin/bash
# Installs ccsessiond, the session reader from https://github.com/artcar12/ccsession, into its own
# environment so it lands at ~/.local/bin/ccsessiond. build.sh runs this first.
#   CCSESSION_SOURCE    what to install: a pip/uv requirement or a local checkout path
#                       (default: git+https://github.com/artcar12/ccsession@$CCSESSION_REF)
#   CCSESSION_REF       the ccsession release tag (default below)
#   CCSESSIOND_BIN_DIR  where ccsessiond goes (default ~/.local/bin)
#   CCSESSION_VENV      the environment used when uv isn't installed (default ~/.local/share/ccsession-venv)
set -euo pipefail

REF="${CCSESSION_REF:-v0.4.0}"
SOURCE="${CCSESSION_SOURCE:-git+https://github.com/artcar12/ccsession@$REF}"
BIN_DIR="${CCSESSIOND_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$BIN_DIR"

if command -v uv >/dev/null 2>&1; then
    UV_TOOL_BIN_DIR="$BIN_DIR" uv tool install --quiet --force --python '>=3.11' "$SOURCE"
else
    PY="${PYTHON:-python3}"
    if ! "$PY" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
        echo "install-ccsessiond: needs Python 3.11 or newer (or uv: https://docs.astral.sh/uv/)" >&2
        exit 1
    fi
    VENV="${CCSESSION_VENV:-$HOME/.local/share/ccsession-venv}"
    "$PY" -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade "$SOURCE"
    ln -sf "$VENV/bin/ccsessiond" "$VENV/bin/ccsession" "$BIN_DIR/"
fi

echo "Installed $("$BIN_DIR/ccsessiond" --version) at $BIN_DIR/ccsessiond"
