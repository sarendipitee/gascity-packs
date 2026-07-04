#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/../../assets/scripts/install-jjw.sh"

if command -v jjw >/dev/null 2>&1; then
    jjw version
    exit 0
fi

INSTALL_DIR="${GC_JJW_INSTALL_DIR:-${HOME:-}/.local/bin}"
"$INSTALL_DIR/jjw" version
