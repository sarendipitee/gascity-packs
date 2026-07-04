#!/usr/bin/env python3
"""List sparse-checkout patterns for local pack.toml imports.

Usage: list-import-patterns.py <rig-root> <pack-pattern> <pack-toml>

Emits one directory sparse pattern per valid local import, skipping remote/URL
imports, malformed entries, and any path that resolves outside the rig root or
does not name an existing directory.
"""
import os
import sys
import tomllib


def is_url_like(value: str) -> bool:
    """Return True for remote-looking import sources."""
    if "://" in value:
        return True
    if value.startswith("git@"):
        return True
    return False


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: list-import-patterns.py <rig-root> <pack-pattern> <pack-toml>",
            file=sys.stderr,
        )
        return 2

    rig_root = sys.argv[1]
    pack_pattern = sys.argv[2].rstrip("/")
    pack_toml = sys.argv[3]
    pack_dir = os.path.dirname(os.path.abspath(pack_toml))
    rig_root_abs = os.path.abspath(rig_root)

    try:
        with open(pack_toml, "rb") as f:
            data = tomllib.load(f)
    except Exception as exc:
        print(f"packer workspace setup: warning: could not read {pack_toml}: {exc}", file=sys.stderr)
        return 0

    imports = data.get("imports", {})
    if not isinstance(imports, dict):
        print("packer workspace setup: warning: [imports] is not a table; skipping imports", file=sys.stderr)
        return 0

    for key, val in imports.items():
        if isinstance(val, dict):
            source = val.get("source", "")
        elif isinstance(val, str):
            source = val
        else:
            print(
                f"packer workspace setup: warning: import {key!r} has malformed source; skipping",
                file=sys.stderr,
            )
            continue

        if not isinstance(source, str):
            print(
                f"packer workspace setup: warning: import {key!r} has malformed source; skipping",
                file=sys.stderr,
            )
            continue

        source = source.strip()

        if not source:
            print(
                f"packer workspace setup: warning: import {key!r} missing source; skipping",
                file=sys.stderr,
            )
            continue

        if is_url_like(source):
            print(
                f"packer workspace setup: skipping remote/URL import {key!r}: {source}",
                file=sys.stderr,
            )
            continue

        if source.startswith("/"):
            abs_source = os.path.abspath(source)
        else:
            abs_source = os.path.normpath(os.path.join(pack_dir, source))

        abs_source = os.path.realpath(abs_source)

        # Skip self-references: the pack itself is already sparse-checked out.
        pack_dir_abs = os.path.realpath(pack_dir)
        if abs_source == pack_dir_abs:
            print(
                f"packer workspace setup: skipping self-reference import {key!r}",
                file=sys.stderr,
            )
            continue
        try:
            if os.path.commonpath([pack_dir_abs, abs_source]) == pack_dir_abs:
                print(
                    f"packer workspace setup: skipping self-reference import {key!r}",
                    file=sys.stderr,
                )
                continue
        except ValueError:
            pass

        try:
            rel = os.path.relpath(abs_source, rig_root_abs)
        except ValueError:
            print(
                f"packer workspace setup: warning: import {key!r} resolves outside rig root; skipping",
                file=sys.stderr,
            )
            continue

        if rel.startswith("..") or os.path.isabs(rel) or rel == ".":
            print(
                f"packer workspace setup: warning: import {key!r} resolves outside rig root; skipping",
                file=sys.stderr,
            )
            continue

        if not os.path.isdir(abs_source):
            print(
                f"packer workspace setup: warning: import {key!r} does not resolve to a directory; skipping",
                file=sys.stderr,
            )
            continue

        print(rel.rstrip("/") + "/")

    return 0


if __name__ == "__main__":
    sys.exit(main())
