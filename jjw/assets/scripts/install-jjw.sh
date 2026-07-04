#!/bin/sh
set -eu

VERSION="${GC_JJW_VERSION:-latest}"
INSTALL_DIR="${GC_JJW_INSTALL_DIR:-${HOME:-}/.local/bin}"

if command -v jjw >/dev/null 2>&1; then
    exit 0
fi

if [ -z "$INSTALL_DIR" ]; then
    echo "jjw install: HOME is unset and GC_JJW_INSTALL_DIR was not provided" >&2
    exit 1
fi

if ! command -v go >/dev/null 2>&1; then
    echo "jjw install: jjw is missing and go is not available for installation" >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"
echo "jjw install: installing github.com/aranw/jjw/cmd/jjw@$VERSION into $INSTALL_DIR" >&2
GOBIN="$INSTALL_DIR" go install "github.com/aranw/jjw/cmd/jjw@$VERSION"

if [ ! -x "$INSTALL_DIR/jjw" ]; then
    echo "jjw install: expected $INSTALL_DIR/jjw after go install" >&2
    exit 1
fi

case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *) echo "jjw install: installed to $INSTALL_DIR; add it to PATH for future shells" >&2 ;;
esac

