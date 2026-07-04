#!/usr/bin/env bash
# Build/run DB Browser for SQLite against libdoltlite so it can open DoltLite DBs.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: gc beads-doltlite sqlitebrowser [open|project|build|path] [options] [db-file]

Build or run DB Browser for SQLite linked against libdoltlite.

Subcommands:
  open     Open the generated HQ/rig DB Browser project. Default.
  project  Generate the HQ/rig DB Browser project and print its path.
  build    Configure/build a local DB Browser checkout against libdoltlite.
  path     Print the DoltLite database path that --db would open.

Options:
  --city DIR        City workspace root. Default: GC_CITY_PATH or current dir.
  --db FILE         DoltLite database file to open instead of city metadata.
  --project FILE    Generated DB Browser project path.
  --sql FILE        Generated formula-progress SQL path.
  --lib DIR         Directory containing libdoltlite.so. Default: doltlite-work/build.
  --source DIR      sqlitebrowser source checkout. Required unless --allow-network-fetch is set.
  --build-dir DIR   CMake build directory.
  --bin FILE        sqlitebrowser binary path to run.
  --repo URL        sqlitebrowser repository URL for --allow-network-fetch.
  --ref REF         sqlitebrowser tag or full commit for --allow-network-fetch/--update.
  --allow-network-fetch
                    Permit cloning --repo at --ref when --source is missing.
  --update          Fetch and checkout --ref in the source dir. Requires --allow-network-fetch.
  --jobs N          Parallel build jobs. Default: nproc or 4.
  --cmake-arg ARG   Extra argument passed to cmake configure. Repeatable.
  -h, --help        Show this help.

Examples:
  gc beads-doltlite sqlitebrowser build
  gc beads-doltlite sqlitebrowser open
  gc beads-doltlite sqlitebrowser open --city /path/to/city
  gc beads-doltlite sqlitebrowser project --city /path/to/city
  gc beads-doltlite sqlitebrowser open --db /path/to/.beads/doltlite/hq.db
EOF
}

die() {
  echo "$*" >&2
  exit 1
}

usage_error() {
  echo "$*" >&2
  usage >&2
  exit 2
}

require_value() {
  if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
    usage_error "$1 requires a value"
  fi
}

abs_dir() {
  cd "$1" && pwd
}

abs_file() {
  local dir base
  dir="$(dirname "$1")"
  base="$(basename "$1")"
  cd "$dir" && printf '%s/%s\n' "$(pwd)" "$base"
}

has_doltlite_lib() {
  [ -r "$1/libdoltlite.so" ] || [ -r "$1/libdoltlite.so.0" ] || [ -r "$1/libdoltlite.dylib" ]
}

doltlite_lib_file() {
  for name in libdoltlite.so libdoltlite.so.0 libdoltlite.dylib; do
    if [ -r "$DOLTLITE_LIB/$name" ]; then
      printf '%s/%s\n' "$DOLTLITE_LIB" "$name"
      return 0
    fi
  done
  return 1
}

find_doltlite_lib() {
  for candidate in \
    "$CITY_ROOT/doltlite-work/build" \
    "$CITY_ROOT/doltlite/build" \
    "$CITY_ROOT/../doltlite-work/build" \
    "$CITY_ROOT/../doltlite/build"; do
    if has_doltlite_lib "$candidate"; then
      abs_dir "$candidate"
      return 0
    fi
  done
  return 1
}

default_jobs() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
    return 0
  fi
  echo 4
}

json_db_name() {
  local metadata="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$metadata" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(data.get("dolt_database") or data.get("database") or "")
PY
    return 0
  fi
  awk -F\" '
    /"dolt_database"[[:space:]]*:/ { print $4; found=1; exit }
    /"database"[[:space:]]*:/ && !found { value=$4 }
    END { if (!found && value != "") print value }
  ' "$metadata"
}

database_for_city() {
  local metadata db_name candidate
  metadata="$CITY_ROOT/.beads/metadata.json"
  if [ -r "$metadata" ]; then
    db_name="$(json_db_name "$metadata" || true)"
    if [ -n "$db_name" ]; then
      candidate="$CITY_ROOT/.beads/doltlite/$db_name.db"
      if [ -r "$candidate" ]; then
        abs_file "$candidate"
        return 0
      fi
    fi
  fi

  candidate="$(find "$CITY_ROOT/.beads/doltlite" -maxdepth 1 -type f -name '*.db' 2>/dev/null | sort | head -n 1 || true)"
  if [ -n "$candidate" ]; then
    abs_file "$candidate"
    return 0
  fi
  return 1
}

resolve_browser_bin() {
  if [ -n "$SQLITEBROWSER_BIN" ]; then
    printf '%s\n' "$SQLITEBROWSER_BIN"
    return 0
  fi
  for candidate in \
    "$BUILD_DIR/sqlitebrowser" \
    "$PACK_STATE_DIR/bin/sqlitebrowser-doltlite"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

verify_browser_links_doltlite() {
  local bin="$1"
  if command -v ldd >/dev/null 2>&1; then
    if ! ldd "$bin" 2>/dev/null | grep -q 'libdoltlite'; then
      die "$bin is not linked to libdoltlite; run: gc beads-doltlite sqlitebrowser build"
    fi
  fi
}

prepare_source() {
  if [ ! -d "$SOURCE_DIR/.git" ]; then
    if [ "$ALLOW_NETWORK_FETCH" != "1" ]; then
      die "sqlitebrowser source checkout not found at $SOURCE_DIR; pass --source DIR or opt in with --allow-network-fetch --ref <tag-or-full-commit>"
    fi
    require_pinned_ref "$SQLITEBROWSER_REF"
    mkdir -p "$(dirname "$SOURCE_DIR")"
    echo "cloning DB Browser for SQLite into $SOURCE_DIR"
    git clone --depth 1 --branch "$SQLITEBROWSER_REF" "$SQLITEBROWSER_REPO" "$SOURCE_DIR" ||
      die "cloning sqlitebrowser failed"
    if [ -f "$SOURCE_DIR/.gitmodules" ]; then
      git -C "$SOURCE_DIR" submodule update --init --recursive ||
        die "initializing sqlitebrowser submodules failed"
    fi
    return 0
  fi

  if [ "$UPDATE_SOURCE" = "1" ]; then
    if [ "$ALLOW_NETWORK_FETCH" != "1" ]; then
      die "--update requires --allow-network-fetch"
    fi
    require_pinned_ref "$SQLITEBROWSER_REF"
    echo "updating DB Browser source in $SOURCE_DIR to $SQLITEBROWSER_REF"
    git -C "$SOURCE_DIR" fetch --depth 1 origin "$SQLITEBROWSER_REF" ||
      die "fetching sqlitebrowser ref failed"
    git -C "$SOURCE_DIR" checkout --detach FETCH_HEAD ||
      die "checking out sqlitebrowser ref failed"
    if [ -f "$SOURCE_DIR/.gitmodules" ]; then
      git -C "$SOURCE_DIR" submodule update --init --recursive ||
        die "updating sqlitebrowser submodules failed"
    fi
  fi
}

require_pinned_ref() {
  local ref="$1"
  case "$ref" in
    v[0-9]*.[0-9]*.[0-9]*|[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
      return 0
      ;;
  esac
  die "network fetch requires --ref to be a release tag like v3.13.1 or a full 40-character commit SHA, got: $ref"
}

build_browser() {
  command -v git >/dev/null 2>&1 || die "git is required to clone sqlitebrowser"
  command -v cmake >/dev/null 2>&1 || die "cmake is required to build sqlitebrowser"

  local lib_file browser_bin
  lib_file="$(doltlite_lib_file)" || die "could not find libdoltlite shared library under $DOLTLITE_LIB"

  prepare_source
  mkdir -p "$BUILD_DIR"

  echo "configuring DB Browser for SQLite"
  echo "source: $SOURCE_DIR"
  echo "build:  $BUILD_DIR"
  echo "lib:    $lib_file"

  cmake \
    -S "$SOURCE_DIR" \
    -B "$BUILD_DIR" \
    -Dsqlcipher=0 \
    -DENABLE_TESTING=OFF \
    -DFORCE_INTERNAL_QSCINTILLA=ON \
    -DSQLite3_INCLUDE_DIR="$DOLTLITE_LIB" \
    -DSQLite3_LIBRARY="$lib_file" \
    -DCMAKE_BUILD_RPATH="$DOLTLITE_LIB" \
    -DCMAKE_INSTALL_RPATH="$DOLTLITE_LIB" \
    "${CMAKE_ARGS[@]}"

  cmake --build "$BUILD_DIR" --target sqlitebrowser --parallel "$JOBS"

  browser_bin="$BUILD_DIR/sqlitebrowser"
  if [ ! -x "$browser_bin" ]; then
    browser_bin="$(find "$BUILD_DIR" -type f -name sqlitebrowser -perm -111 | head -n 1 || true)"
  fi
  if [ -z "$browser_bin" ] || [ ! -x "$browser_bin" ]; then
    die "sqlitebrowser build completed but no executable was found under $BUILD_DIR"
  fi
  browser_bin="$(abs_file "$browser_bin")"
  verify_browser_links_doltlite "$browser_bin"

  mkdir -p "$PACK_STATE_DIR/bin"
  ln -sfn "$browser_bin" "$PACK_STATE_DIR/bin/sqlitebrowser-doltlite"
  echo "built DoltLite-linked sqlitebrowser: $browser_bin"
  echo "launcher symlink: $PACK_STATE_DIR/bin/sqlitebrowser-doltlite"
}

open_browser() {
  local db_file browser_bin
  if [ -n "$DB_FILE" ]; then
    [ -r "$DB_FILE" ] || die "database file does not exist or is not readable: $DB_FILE"
    db_file="$(abs_file "$DB_FILE")"
  else
    db_file="$(generate_browser_project)"
  fi

  browser_bin="$(resolve_browser_bin || true)"
  if [ -z "$browser_bin" ] || [ ! -x "$browser_bin" ]; then
    die "DoltLite-linked sqlitebrowser is not built; run: gc beads-doltlite sqlitebrowser build"
  fi
  browser_bin="$(abs_file "$browser_bin")"
  verify_browser_links_doltlite "$browser_bin"

  if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${QT_QPA_PLATFORM:-}" ]; then
    die "DISPLAY, WAYLAND_DISPLAY, or QT_QPA_PLATFORM is required to launch sqlitebrowser"
  fi

  export LD_LIBRARY_PATH="$DOLTLITE_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  echo "opening $db_file with $browser_bin"
  exec "$browser_bin" "$db_file" "${BROWSER_ARGS[@]}"
}

generate_browser_project() {
  command -v python3 >/dev/null 2>&1 || die "python3 is required to generate a DB Browser project"

  local generator project_file sql_file project_dir
  generator="$PACK_DIR/examples/formula-progress/generate-formula-progress-sql.py"
  [ -r "$generator" ] || die "formula progress generator not found: $generator"

  project_dir="$PACK_STATE_DIR/sqlitebrowser"
  project_file="${PROJECT_FILE:-$project_dir/doltlite-city.sqbpro}"
  sql_file="${SQL_FILE:-$project_dir/formula-progress-no-attach.sql}"

  python3 "$generator" \
    --city "$CITY_ROOT" \
    --attach-mode none \
    --output "$sql_file" ||
    die "generating formula progress SQL failed"

  python3 - "$CITY_ROOT" "$project_file" "$sql_file" <<'PY'
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys
from xml.sax.saxutils import escape


SKIP_DIRS = {
    ".cache",
    ".git",
    ".gc",
    ".jj",
    "__pycache__",
    "build",
    "dist",
    "node_modules",
    "sqlitebrowser-build",
    "sqlitebrowser-src",
    "vendor",
}


def attr(value: object) -> str:
    return escape(str(value), {'"': "&quot;"})


def safe_alias(value: str, used: set[str]) -> str:
    base = re.sub(r"[^A-Za-z0-9_]+", "_", value.strip().lower()).strip("_")
    if not base:
        base = "db"
    if base[0].isdigit():
        base = "db_" + base
    alias = base
    i = 2
    while alias in used:
        alias = f"{base}_{i}"
        i += 1
    used.add(alias)
    return alias


def main_database(city: Path) -> Path:
    db_root = city / ".beads" / "doltlite"
    metadata = city / ".beads" / "metadata.json"
    if metadata.exists():
        try:
            data = json.loads(metadata.read_text(encoding="utf-8"))
            name = data.get("dolt_database") or data.get("database")
        except Exception:
            name = None
        if name:
            candidate = db_root / f"{name}.db"
            if candidate.exists():
                return candidate.resolve()

    matches = sorted(db_root.glob("*.db")) if db_root.exists() else []
    if matches:
        return matches[0].resolve()
    raise SystemExit(f"could not find a DoltLite database under {db_root}")


def discover_attachments(city: Path, main: Path) -> list[tuple[str, Path]]:
    found: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(city):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        current = Path(dirpath)
        if current.name != "doltlite" or current.parent.name != ".beads":
            continue
        for filename in filenames:
            if filename.endswith(".db"):
                found.append((current / filename).resolve())

    used = {"main"}
    attached: list[tuple[str, Path]] = []
    for path in sorted(found):
        if path == main:
            continue
        attached.append((safe_alias(f"rig_{path.stem}", used), path))
    return attached


city = Path(sys.argv[1]).expanduser().resolve()
project = Path(sys.argv[2]).expanduser().resolve()
sql = Path(sys.argv[3]).expanduser().resolve()
main = main_database(city)
attached = discover_attachments(city, main)

project.parent.mkdir(parents=True, exist_ok=True)
attachments = "".join(
    f'<db schema="{attr(alias)}" path="{attr(path)}"/>'
    for alias, path in attached
)
project.write_text(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<sqlb_project>'
    f'<db path="{attr(main)}" readonly="1" foreign_keys="1" case_sensitive_like="0" temp_store="0" wal_autocheckpoint="1000" synchronous="2"/>'
    f'<attached>{attachments}</attached>'
    '<window><main_tabs open="structure browse pragma sql plot" current="3"/></window>'
    '<tab_sql>'
    f'<sql name="Formula progress" filename="{attr(sql)}">'
    f'-- Reference to file "{attr(sql)}" --'
    '</sql>'
    '<current_tab id="0"/>'
    '</tab_sql>'
    '</sqlb_project>\n',
    encoding="utf-8",
)
print(project)
PY
}

ACTION="open"
CITY_ROOT="${GC_CITY_PATH:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACK_STATE_DIR="${GC_PACK_STATE_DIR:-$CITY_ROOT/.gc/runtime/packs/beads-doltlite}"
DOLTLITE_LIB="${DOLTLITE_LIB:-${GC_DOLTLITE_LIB:-}}"
SOURCE_DIR="${GC_DOLTLITE_SQLITEBROWSER_SOURCE:-$PACK_STATE_DIR/sqlitebrowser-src}"
BUILD_DIR="${GC_DOLTLITE_SQLITEBROWSER_BUILD_DIR:-$PACK_STATE_DIR/sqlitebrowser-build}"
SOURCE_DIR_SET=0
BUILD_DIR_SET=0
SQLITEBROWSER_BIN="${GC_DOLTLITE_SQLITEBROWSER_BIN:-}"
SQLITEBROWSER_REPO="${GC_DOLTLITE_SQLITEBROWSER_REPO:-https://github.com/sqlitebrowser/sqlitebrowser.git}"
SQLITEBROWSER_REF="${GC_DOLTLITE_SQLITEBROWSER_REF:-}"
ALLOW_NETWORK_FETCH="${GC_DOLTLITE_SQLITEBROWSER_ALLOW_NETWORK_FETCH:-0}"
UPDATE_SOURCE=0
JOBS="${GC_DOLTLITE_SQLITEBROWSER_JOBS:-$(default_jobs)}"
DB_FILE=""
PROJECT_FILE=""
SQL_FILE=""
CMAKE_ARGS=()
BROWSER_ARGS=()

if [ "$#" -gt 0 ]; then
  case "$1" in
    open|project|build|path)
      ACTION="$1"
      shift
      ;;
  esac
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --city)
      require_value "$1" "${2:-}"
      CITY_ROOT="$2"
      shift 2
      ;;
    --city=*)
      CITY_ROOT="${1#*=}"
      shift
      ;;
    --db)
      require_value "$1" "${2:-}"
      DB_FILE="$2"
      shift 2
      ;;
    --db=*)
      DB_FILE="${1#*=}"
      shift
      ;;
    --project)
      require_value "$1" "${2:-}"
      PROJECT_FILE="$2"
      shift 2
      ;;
    --project=*)
      PROJECT_FILE="${1#*=}"
      shift
      ;;
    --sql)
      require_value "$1" "${2:-}"
      SQL_FILE="$2"
      shift 2
      ;;
    --sql=*)
      SQL_FILE="${1#*=}"
      shift
      ;;
    --lib)
      require_value "$1" "${2:-}"
      DOLTLITE_LIB="$2"
      shift 2
      ;;
    --lib=*)
      DOLTLITE_LIB="${1#*=}"
      shift
      ;;
    --source)
      require_value "$1" "${2:-}"
      SOURCE_DIR="$2"
      SOURCE_DIR_SET=1
      shift 2
      ;;
    --source=*)
      SOURCE_DIR="${1#*=}"
      SOURCE_DIR_SET=1
      shift
      ;;
    --build-dir)
      require_value "$1" "${2:-}"
      BUILD_DIR="$2"
      BUILD_DIR_SET=1
      shift 2
      ;;
    --build-dir=*)
      BUILD_DIR="${1#*=}"
      BUILD_DIR_SET=1
      shift
      ;;
    --bin)
      require_value "$1" "${2:-}"
      SQLITEBROWSER_BIN="$2"
      shift 2
      ;;
    --bin=*)
      SQLITEBROWSER_BIN="${1#*=}"
      shift
      ;;
    --repo)
      require_value "$1" "${2:-}"
      SQLITEBROWSER_REPO="$2"
      shift 2
      ;;
    --repo=*)
      SQLITEBROWSER_REPO="${1#*=}"
      shift
      ;;
    --ref)
      require_value "$1" "${2:-}"
      SQLITEBROWSER_REF="$2"
      shift 2
      ;;
    --ref=*)
      SQLITEBROWSER_REF="${1#*=}"
      shift
      ;;
    --allow-network-fetch)
      ALLOW_NETWORK_FETCH=1
      shift
      ;;
    --update)
      UPDATE_SOURCE=1
      shift
      ;;
    --jobs)
      require_value "$1" "${2:-}"
      JOBS="$2"
      shift 2
      ;;
    --jobs=*)
      JOBS="${1#*=}"
      shift
      ;;
    --cmake-arg)
      require_value "$1" "${2:-}"
      CMAKE_ARGS+=("$2")
      shift 2
      ;;
    --cmake-arg=*)
      CMAKE_ARGS+=("${1#*=}")
      shift
      ;;
    --)
      shift
      BROWSER_ARGS+=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      usage_error "unknown argument: $1"
      ;;
    *)
      if [ "$ACTION" = "open" ] && [ -z "$DB_FILE" ]; then
        DB_FILE="$1"
        shift
      else
        BROWSER_ARGS+=("$1")
        shift
      fi
      ;;
  esac
done

case "$ACTION" in
  open|project|build|path) ;;
  *) usage_error "unknown subcommand: $ACTION" ;;
esac

case "${ALLOW_NETWORK_FETCH,,}" in
  1|true|yes|on) ALLOW_NETWORK_FETCH=1 ;;
  ""|0|false|no|off) ALLOW_NETWORK_FETCH=0 ;;
  *) usage_error "GC_DOLTLITE_SQLITEBROWSER_ALLOW_NETWORK_FETCH must be true or false" ;;
esac

if [ "$ALLOW_NETWORK_FETCH" = "1" ] && [ -z "$SQLITEBROWSER_REF" ]; then
  usage_error "--allow-network-fetch requires --ref <tag-or-full-commit>"
fi

case "$JOBS" in
  ''|*[!0-9]*) usage_error "--jobs must be a positive integer" ;;
  0) usage_error "--jobs must be greater than zero" ;;
esac

CITY_ROOT="$(abs_dir "$CITY_ROOT")"
PACK_STATE_DIR="${GC_PACK_STATE_DIR:-$CITY_ROOT/.gc/runtime/packs/beads-doltlite}"
if [ "$SOURCE_DIR_SET" = "0" ] && [ -z "${GC_DOLTLITE_SQLITEBROWSER_SOURCE:-}" ]; then
  SOURCE_DIR="$PACK_STATE_DIR/sqlitebrowser-src"
fi
if [ "$BUILD_DIR_SET" = "0" ] && [ -z "${GC_DOLTLITE_SQLITEBROWSER_BUILD_DIR:-}" ]; then
  BUILD_DIR="$PACK_STATE_DIR/sqlitebrowser-build"
fi

if [ "$ACTION" = "build" ] || [ "$ACTION" = "open" ]; then
  if [ -z "$DOLTLITE_LIB" ]; then
    DOLTLITE_LIB="$(find_doltlite_lib || true)"
  fi
  if [ -z "$DOLTLITE_LIB" ] || ! has_doltlite_lib "$DOLTLITE_LIB"; then
    die "could not find libdoltlite; set DOLTLITE_LIB=/path/to/doltlite-work/build or pass --lib"
  fi
  DOLTLITE_LIB="$(abs_dir "$DOLTLITE_LIB")"
fi

case "$ACTION" in
  build)
    build_browser
    ;;
  project)
    generate_browser_project
    ;;
  path)
    if [ -n "$DB_FILE" ]; then
      abs_file "$DB_FILE"
    else
      database_for_city || die "could not find a DoltLite database under $CITY_ROOT/.beads/doltlite; pass --db"
    fi
    ;;
  open)
    open_browser
    ;;
esac
