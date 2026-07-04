#!/bin/sh
set -eu

if command -v jjw >/dev/null 2>&1; then
    jjw version >/dev/null
    echo "jjw: available"
    exit 0
fi

if command -v go >/dev/null 2>&1; then
    echo "jjw: missing, but go is available for install"
    exit 0
fi

echo "jjw: missing and go is unavailable" >&2
exit 1

