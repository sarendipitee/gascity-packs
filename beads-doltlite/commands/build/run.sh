#!/usr/bin/env bash
# Build DoltLite-linked binaries with CGO/libsqlite3.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: gc beads-doltlite build [gc|bd|client|all] [options]

Builds or installs DoltLite-linked binaries for Gas City and beads-doltlite.
The default target is gc.

Targets:
  gc      Normal init path. Installs the released DoltLite-linked gc binary by
          default; rebuild only after Gas City source or build-tag changes.
  bd      Installs the released bd-doltlite binary by default; rebuild only
          after beads-doltlite source or bd link inputs change.
  client  Rebuild the DoltLite diagnostic client only when that tool changes.
  all     Coordinated rebuild. Builds bd, doltlite-client, then gc.
          Use after changing optional diagnostic client/link inputs. It does
          not skip unchanged targets.

Examples:
  gc beads-doltlite build gc --install --no-restart
  gc beads-doltlite build all --install --no-restart

Options:
  --source DIR       Source checkout for the selected single target.
  --gc-source DIR    Gas City source checkout. Default: ./gascity, current dir,
                     script checkout, or pack runtime source cache.
  --bd-source DIR    beads-doltlite source checkout. Default: ./beads-doltlite,
                     adjacent checkout, or pack runtime source cache.
  --skip-local-source
                     Skip automatic local source checkout discovery and fetch
                     the default remote source unless explicit source paths are
                     provided. Alias: --no-local-source.
  --build-bd-from-source
                     Build bd from source instead of installing the released
                     bd-doltlite binary.
  --build-gc-from-source
                     Build gc from source instead of installing the released
                     DoltLite-linked gc binary.
  --skip-local-lib  Skip automatic local libdoltlite discovery and use the
                     pinned DoltLite release library unless --lib or
                     DOLTLITE_LIB/GC_DOLTLITE_LIB is provided.
  --lib DIR          Directory containing doltlite.h and libdoltlite.
                     Default: standard install locations or downloaded release
                     library under the pack runtime cache.
  --output FILE      Build output path for the selected single target.
  --gc-output FILE   Build output path for gc. Default: <gc-source>/bin/gc.
  --bd-output FILE   Build output path for bd. Default: <bd-source>/bin/bd.
  --client-output FILE
                     Build output path for doltlite-client.
                     Default: <build-details-dir>/bin/doltlite-client.
  --install          Install built binaries after link verification.
  --install-dir DIR  Install directory for both binaries.
                     Default for gc: install to the running supervisor path,
                     supervisor unit path, and active controller path when
                     they are distinct home-owned paths; otherwise
                     $HOME/.local/bin. Default for bd: active bd under $HOME,
                     otherwise $HOME/.local/bin.
  --gc-install FILE  Install path for gc.
  --bd-install FILE  Install path for bd.
  --build-details-dir DIR
                     Directory for last-build-*.json.
                     Default: runtime pack state dir.
  --restart          Stop supervisor/city before building gc, then start after install. Default.
  --no-restart       Do not restart supervisor/city after installing gc.
  --version VALUE    Version string embedded in gc. Default: dev.
  --bd-build VALUE   Build string embedded in bd. Default: dev.

Environment overrides:
  GASCITY_SRC, GC_GASCITY_SRC
  BD_SRC, BEADS_DOLTLITE_SRC, GC_BEADS_DOLTLITE_SRC
  DOLTLITE_LIB, GC_DOLTLITE_LIB
  OUTPUT, GC_DOLTLITE_GC_OUTPUT, BD_OUTPUT, GC_DOLTLITE_BD_OUTPUT
  GC_DOLTLITE_INSTALL, GC_DOLTLITE_INSTALL_DIR
  GC_DOLTLITE_GC_INSTALL, GC_DOLTLITE_BD_INSTALL
  GC_DOLTLITE_CLIENT_OUTPUT
  GC_DOLTLITE_BUILD_DETAILS_DIR
  GC_DOLTLITE_VERSION
  GC_DOLTLITE_DOWNLOAD_BASE
  GC_DOLTLITE_GC_RELEASE_VERSION, GC_DOLTLITE_GC_RELEASE_BASE
  GC_DOLTLITE_GC_RELEASE_API
  GC_DOLTLITE_BD_RELEASE_VERSION, GC_DOLTLITE_BD_RELEASE_BASE
  GC_DOLTLITE_BUILD_GC_FROM_SOURCE
  GC_DOLTLITE_BUILD_BD_FROM_SOURCE
  GC_DOLTLITE_SKIP_LOCAL_SOURCE
  GC_DOLTLITE_SKIP_LOCAL_LIB
  GC_DOLTLITE_GASCITY_REPO, GC_DOLTLITE_GASCITY_REF
  GC_DOLTLITE_BD_REPO, GC_DOLTLITE_BD_REF
  GC_DOLTLITE_GO_CACHE_ROOT, GOCACHE, GOMODCACHE, GOTMPDIR
  GC_DOLTLITE_RESTART_AFTER_INSTALL, GC_DOLTLITE_RESTART_WAIT_SECONDS
  GC_VERSION, GC_COMMIT, GC_BUILD_DATE
  BD_BUILD, BD_COMMIT, BD_BRANCH
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

has_gascity_source() {
  [ -f "$1/go.mod" ] && [ -d "$1/cmd/gc" ]
}

has_bd_source() {
  [ -f "$1/go.mod" ] && [ -d "$1/cmd/bd" ]
}

has_doltlite_lib() {
  [ -r "$1/doltlite.h" ] || return 1
  [ -r "$1/libdoltlite.a" ] || [ -r "$1/libdoltlite.so" ] || [ -r "$1/libdoltlite.so.0" ] || [ -r "$1/libdoltlite.dylib" ]
}

pack_state_dir() {
  echo "${GC_PACK_STATE_DIR:-$CITY_ROOT/.gc/runtime/packs/beads-doltlite}"
}

host_os() {
  case "$(uname -s)" in
    Linux) echo "linux" ;;
    Darwin) echo "osx" ;;
    MINGW*|MSYS*|CYGWIN*) echo "win" ;;
    *) die "unsupported OS for DoltLite release download: $(uname -s)" ;;
  esac
}

host_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "unsupported architecture for DoltLite release download: $(uname -m)" ;;
  esac
}

bd_release_platform() {
  case "$(uname -s):$(uname -m)" in
    Linux:x86_64|Linux:amd64) echo "linux-amd64" ;;
    *) die "unsupported OS/architecture for bd-doltlite release download: $(uname -s)/$(uname -m); use --build-bd-from-source" ;;
  esac
}

gc_release_platform() {
  case "$(uname -s):$(uname -m)" in
    Linux:x86_64|Linux:amd64) echo "linux_amd64" ;;
    *) die "unsupported OS/architecture for DoltLite-linked gc release download: $(uname -s)/$(uname -m); use --build-gc-from-source" ;;
  esac
}

download_file() {
  local url="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$url" "$dest" <<'PY'
import os
import sys
import tempfile
import urllib.request

url, dest = sys.argv[1], sys.argv[2]
directory = os.path.dirname(dest) or "."
fd, tmp = tempfile.mkstemp(prefix=".download-", dir=directory)
os.close(fd)
try:
    with urllib.request.urlopen(url, timeout=120) as response:
        with open(tmp, "wb") as out:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                out.write(chunk)
    os.replace(tmp, dest)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PY
    return $?
  fi
  die "python3 is required to download DoltLite release artifacts"
}

latest_gc_release_version() {
  local api_url
  api_url="${GC_DOLTLITE_GC_RELEASE_API:-https://api.github.com/repos/duncan4123/gascity/releases}"
  python3 - "$api_url" <<'PY'
import json
import re
import sys
import urllib.request

api_url = sys.argv[1]
pattern = re.compile(r"^v\d+\.\d+\.\d+-doltlite\.workflow\.\d+$")
with urllib.request.urlopen(api_url, timeout=120) as response:
    releases = json.load(response)

candidates = [
    release for release in releases
    if not release.get("draft") and pattern.match(release.get("tag_name", ""))
]
if not candidates:
    raise SystemExit(f"no DoltLite workflow gc releases found at {api_url}")

candidates.sort(key=lambda release: release.get("published_at") or release.get("created_at") or "", reverse=True)
print(candidates[0]["tag_name"])
PY
}

default_gc_release_version() {
  if [ -n "${GC_DOLTLITE_GC_RELEASE_VERSION:-}" ]; then
    echo "$GC_DOLTLITE_GC_RELEASE_VERSION"
    return 0
  fi
  latest_gc_release_version
}

verify_checksum_file() {
  local checksums="$1"
  local file="$2"
  local name
  name="$(basename "$file")"
  python3 - "$checksums" "$file" "$name" <<'PY'
import hashlib
import sys

checksums, path, name = sys.argv[1], sys.argv[2], sys.argv[3]
expected = None
with open(checksums, "r", encoding="utf-8") as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) >= 2 and parts[1].lstrip("*") == name:
            expected = parts[0].lower()
            break
if not expected:
    raise SystemExit(f"no checksum entry for {name} in {checksums}")
h = hashlib.sha256()
with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        h.update(chunk)
actual = h.hexdigest().lower()
if actual != expected:
    raise SystemExit(f"checksum mismatch for {name}: got {actual}, want {expected}")
PY
}

extract_zip_strip_one() {
  local zip_path="$1"
  local dest="$2"
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/doltlite-release.XXXXXX")"
  python3 - "$zip_path" "$tmp" "$dest" <<'PY'
import os
import shutil
import sys
import zipfile

zip_path, tmp, dest = sys.argv[1], sys.argv[2], sys.argv[3]
with zipfile.ZipFile(zip_path) as archive:
    archive.extractall(tmp)
entries = [os.path.join(tmp, name) for name in os.listdir(tmp)]
src = entries[0] if len(entries) == 1 and os.path.isdir(entries[0]) else tmp
if os.path.exists(dest):
    shutil.rmtree(dest)
os.makedirs(os.path.dirname(dest), exist_ok=True)
shutil.copytree(src, dest)
PY
  rm -rf "$tmp"
}

extract_tar_binary() {
  local archive_path="$1"
  local binary_name="$2"
  local dest="$3"
  python3 - "$archive_path" "$binary_name" "$dest" <<'PY'
import os
import shutil
import stat
import sys
import tarfile
import tempfile

archive_path, binary_name, dest = sys.argv[1], sys.argv[2], sys.argv[3]
tmp = tempfile.mkdtemp(prefix="gascity-release-")
try:
    with tarfile.open(archive_path, "r:gz") as archive:
        archive.extractall(tmp)
    found = None
    for root, _, files in os.walk(tmp):
        if binary_name in files:
            found = os.path.join(root, binary_name)
            break
    if not found:
        raise SystemExit(f"{binary_name} not found in {archive_path}")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.copy2(found, dest)
    mode = os.stat(dest).st_mode
    os.chmod(dest, mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
finally:
    shutil.rmtree(tmp, ignore_errors=True)
PY
}

ensure_doltlite_release_lib() {
  local version os_name arch_name state_dir dest zip_name zip_path base url
  version="${GC_DOLTLITE_VERSION:-0.11.23}"
  os_name="$(host_os)"
  arch_name="$(host_arch)"
  state_dir="$(pack_state_dir)"
  dest="$state_dir/doltlite/$version/${os_name}-${arch_name}"
  if has_doltlite_lib "$dest"; then
    echo "$dest"
    return 0
  fi

  zip_name="doltlite-lib-${os_name}-${arch_name}-${version}.zip"
  zip_path="$state_dir/downloads/$zip_name"
  base="${GC_DOLTLITE_DOWNLOAD_BASE:-https://github.com/dolthub/doltlite/releases/download/v${version}}"
  url="${base%/}/$zip_name"
  if [ ! -s "$zip_path" ]; then
    echo "downloading DoltLite $version library: $url" >&2
    download_file "$url" "$zip_path"
  fi
  extract_zip_strip_one "$zip_path" "$dest"
  if ! has_doltlite_lib "$dest"; then
    die "downloaded DoltLite library is missing doltlite.h or libdoltlite: $dest"
  fi
  echo "$dest"
}

ensure_bd_release_binary() {
  local version platform state_dir asset checksum_name base bin_path checksum_path asset_url checksum_url
  version="${GC_DOLTLITE_BD_RELEASE_VERSION:-v1.0.5-doltlite.1}"
  platform="$(bd_release_platform)"
  state_dir="$(pack_state_dir)"
  asset="bd-doltlite-${platform}"
  checksum_name="checksums.txt"
  bin_path="$state_dir/bd-release/$version/$asset"
  checksum_path="$state_dir/bd-release/$version/$checksum_name"
  base="${GC_DOLTLITE_BD_RELEASE_BASE:-https://github.com/duncan4123/beads-doltlite/releases/download/${version}}"
  asset_url="${base%/}/$asset"
  checksum_url="${base%/}/$checksum_name"

  if [ ! -s "$bin_path" ]; then
    echo "downloading bd DoltLite release binary: $asset_url" >&2
    download_file "$asset_url" "$bin_path"
  fi
  if [ ! -s "$checksum_path" ]; then
    echo "downloading bd DoltLite release checksums: $checksum_url" >&2
    download_file "$checksum_url" "$checksum_path"
  fi
  verify_checksum_file "$checksum_path" "$bin_path"
  chmod +x "$bin_path"
  echo "$bin_path"
}

ensure_gc_release_binary() {
  local version platform state_dir asset checksum_name base archive_path checksum_path bin_path asset_url checksum_url binary_name
  version="$(default_gc_release_version)" || return $?
  platform="$(gc_release_platform)"
  state_dir="$(pack_state_dir)"
  checksum_name="gascity_${version#v}_checksums.txt"
  binary_name="gc"
  bin_path="$state_dir/gc-release/$version/$platform/$binary_name"

  if [ "$version" = "edge" ]; then
    asset="gascity_doltlite_edge_linux_amd64.tar.gz"
    checksum_name="gascity_edge_checksums.txt"
    base="${GC_DOLTLITE_GC_RELEASE_BASE:-https://github.com/gastownhall/gascity/releases/download/edge}"
  else
    asset="gascity-doltlite_${version#v}_${platform}.tar.gz"
    base="${GC_DOLTLITE_GC_RELEASE_BASE:-https://github.com/duncan4123/gascity/releases/download/${version}}"
  fi

  archive_path="$state_dir/gc-release/$version/$asset"
  checksum_path="$state_dir/gc-release/$version/$checksum_name"
  asset_url="${base%/}/$asset"
  checksum_url="${base%/}/$checksum_name"

  if [ ! -s "$archive_path" ]; then
    echo "downloading DoltLite-linked gc release archive: $asset_url" >&2
    download_file "$asset_url" "$archive_path" || return $?
  fi
  if [ ! -s "$checksum_path" ]; then
    echo "downloading DoltLite-linked gc release checksums: $checksum_url" >&2
    download_file "$checksum_url" "$checksum_path" || return $?
  fi
  verify_checksum_file "$checksum_path" "$archive_path" || return $?
  extract_tar_binary "$archive_path" "$binary_name" "$bin_path" || return $?
  echo "$bin_path"
}

ensure_git_source() {
  local name="$1"
  local repo="$2"
  local ref="$3"
  local dest="$4"
  if has_gascity_source "$dest" || has_bd_source "$dest"; then
    echo "$dest"
    return 0
  fi
  if ! command -v git >/dev/null 2>&1; then
    die "git is required to fetch $name source; install git or pass --${name}-source"
  fi
  mkdir -p "$(dirname "$dest")"
  if [ -d "$dest/.git" ]; then
    git -C "$dest" fetch --depth 1 origin "$ref" >&2
    git -C "$dest" checkout -q FETCH_HEAD
  else
    rm -rf "$dest"
    git clone --depth 1 --branch "$ref" "$repo" "$dest" >&2
  fi
  echo "$dest"
}

find_gascity_source() {
  for candidate in \
    "$CITY_ROOT/gascity" \
    "$CITY_ROOT/../gascity" \
    "$(pwd)" \
    "$SCRIPT_CHECKOUT"; do
    if has_gascity_source "$candidate"; then
      abs_dir "$candidate"
      return 0
    fi
  done
  return 1
}

fetch_gascity_source() {
  ensure_git_source \
    "gc" \
    "${GC_DOLTLITE_GASCITY_REPO:-https://github.com/duncan4123/gascity.git}" \
    "${GC_DOLTLITE_GASCITY_REF:-pr/doltlite-init-external-pack-release}" \
    "$(pack_state_dir)/src/gascity"
}

find_bd_source() {
  for candidate in \
    "$CITY_ROOT/beads-doltlite" \
    "$CITY_ROOT/../beads-doltlite" \
    "$SCRIPT_CHECKOUT/../beads-doltlite" \
    "$(pwd)"; do
    if has_bd_source "$candidate"; then
      abs_dir "$candidate"
      return 0
    fi
  done
  return 1
}

fetch_bd_source() {
  ensure_git_source \
    "bd" \
    "${GC_DOLTLITE_BD_REPO:-https://github.com/duncan4123/beads-doltlite.git}" \
    "${GC_DOLTLITE_BD_REF:-beads-doltlite}" \
    "$(pack_state_dir)/src/beads-doltlite"
}

find_doltlite_lib() {
  if [ "$SKIP_LOCAL_LIB" = "1" ]; then
    ensure_doltlite_release_lib
    return 0
  fi
  for candidate in \
    "$(pack_state_dir)/doltlite/${GC_DOLTLITE_VERSION:-0.11.23}/$(host_os)-$(host_arch)" \
    "/usr/local/lib" \
    "/usr/lib" \
    "/usr/lib/$(uname -m)-linux-gnu" \
    "$CITY_ROOT/doltlite-work/build" \
    "$CITY_ROOT/doltlite/build" \
    "$CITY_ROOT/../doltlite-work/build" \
    "$CITY_ROOT/../doltlite/build"; do
    if has_doltlite_lib "$candidate"; then
      abs_dir "$candidate"
      return 0
    fi
  done
  ensure_doltlite_release_lib
}

revision_for() {
  local source_dir="$1"
  if command -v jj >/dev/null 2>&1 && [ -d "$source_dir/.jj" ]; then
    (cd "$source_dir" && jj log --no-graph -r @ -T 'commit_id.short()' 2>/dev/null | tr -d '\n' || true)
    return 0
  fi
  if command -v git >/dev/null 2>&1; then
    git -C "$source_dir" rev-parse --short HEAD 2>/dev/null || true
  fi
}

branch_for() {
  local source_dir="$1"
  if command -v git >/dev/null 2>&1; then
    git -C "$source_dir" symbolic-ref --short HEAD 2>/dev/null || true
  fi
}

common_env_prefix() {
  local tags="$1"
  export CGO_ENABLED=1
  export GOFLAGS="${BASE_GOFLAGS:+$BASE_GOFLAGS }-tags=${tags}"
  export CGO_CFLAGS="${BASE_CGO_CFLAGS:+$BASE_CGO_CFLAGS }-I${DOLTLITE_LIB}"
  if [ -r "$DOLTLITE_LIB/libdoltlite.a" ]; then
    export CGO_LDFLAGS="${BASE_CGO_LDFLAGS:+$BASE_CGO_LDFLAGS }-L${DOLTLITE_LIB} ${DOLTLITE_LIB}/libdoltlite.a -lz -lpthread -lm"
  else
    export CGO_LDFLAGS="${BASE_CGO_LDFLAGS:+$BASE_CGO_LDFLAGS }-L${DOLTLITE_LIB} -Wl,-rpath,${DOLTLITE_LIB} -ldoltlite -lm"
  fi
  export LD_LIBRARY_PATH="${DOLTLITE_LIB}${BASE_LD_LIBRARY_PATH:+:${BASE_LD_LIBRARY_PATH}}"
}

verify_linked_binary() {
  local output="$1"
  local name="$2"
  if ! go version -m "$output" 2>/dev/null | grep -q 'CGO_ENABLED=1'; then
    die "built $name binary does not report CGO_ENABLED=1"
  fi
  if [ -r "$DOLTLITE_LIB/libdoltlite.a" ]; then
    if ! grep -aiq 'doltlite' "$output" 2>/dev/null; then
      die "built $name binary does not appear to contain DoltLite symbols"
    fi
    return 0
  fi
  if command -v ldd >/dev/null 2>&1; then
    local ldd_out resolved_lib resolved_dir
    ldd_out="$(LD_LIBRARY_PATH="$DOLTLITE_LIB${BASE_LD_LIBRARY_PATH:+:${BASE_LD_LIBRARY_PATH}}" ldd "$output" 2>/dev/null || true)"
    if ! grep -q 'libdoltlite' <<<"$ldd_out"; then
      die "built $name binary does not appear to link libdoltlite"
    fi
    if grep -q 'libdoltlite.*not found' <<<"$ldd_out"; then
      die "built $name binary links libdoltlite but the runtime loader cannot find it"
    fi
    resolved_lib="$(awk '/libdoltlite/ { for (i = 1; i <= NF; i++) if ($i == "=>") { print $(i+1); exit } }' <<<"$ldd_out")"
    if [ -z "$resolved_lib" ]; then
      resolved_lib="$(awk '/libdoltlite/ { print $1; exit }' <<<"$ldd_out")"
    fi
    resolved_dir="$(dirname "$resolved_lib" 2>/dev/null || true)"
    if [ -n "$resolved_lib" ] && [ -e "$resolved_lib" ] && ! [[ "$resolved_dir" -ef "$DOLTLITE_LIB" ]]; then
      die "built $name binary resolves libdoltlite from $resolved_dir, want $DOLTLITE_LIB"
    fi
  fi
}

binary_has_go_build_tag() {
  local output="$1"
  local tag="$2"
  go version -m "$output" 2>/dev/null |
    grep -E '^[[:space:]]*build[[:space:]]+-tags=' |
    grep -Eq "(^|[=,[:space:]])${tag}($|[,[:space:]])"
}

verify_gc_binary() {
  local output="$1"
  verify_linked_binary "$output" "gc"
  if ! binary_has_go_build_tag "$output" "gascity_doltlite_lib"; then
    die "built gc binary does not report -tags including gascity_doltlite_lib"
  fi
  local nm_out
  nm_out="$(go tool nm "$output" 2>&1 || true)"
  if grep -Fq 'github.com/gastownhall/gascity/internal/beads.(*DoltliteReadStore)' <<<"$nm_out"; then
    return 0
  fi
  if grep -Eq 'no symbol section|no symbols' <<<"$nm_out"; then
    return 0
  fi
  if [ -n "$nm_out" ]; then
    die "built gc binary is missing native DoltLite read-store symbols"
  fi
}

path_under_home() {
  local path="$1"
  [ -n "$path" ] && [ -n "${HOME:-}" ] && [[ "$path" == "$HOME"/* ]]
}

supervisor_gc_path() {
  local unit="gascity-supervisor.service"
  local value path candidate

  for candidate in \
    "${XDG_CONFIG_HOME:-${HOME:-}/.config}/systemd/user/$unit" \
    "${HOME:-}/.local/share/systemd/user/$unit"; do
    if [ -r "$candidate" ]; then
      value="$(awk -F= '$1 == "ExecStart" { print substr($0, index($0, "=") + 1); exit }' "$candidate")"
      if [ -n "$value" ]; then
        case "$value" in
          \"*) path="${value#\"}"; path="${path%%\"*}" ;;
          *) path="${value%% *}" ;;
        esac
        if [ -n "$path" ]; then
          echo "$path"
          return 0
        fi
      fi
    fi
  done

  if command -v systemctl >/dev/null 2>&1; then
    value="$(systemctl --user show "$unit" -p ExecStart --value 2>/dev/null || true)"
    if [ -n "$value" ]; then
      path="${value#*path=}"
      if [ "$path" != "$value" ]; then
        path="${path%% ;*}"
        path="${path%%;*}"
        if [ -n "$path" ]; then
          echo "$path"
          return 0
        fi
      fi
    fi
  fi

  return 1
}

controller_json_field() {
  local field="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$field" <<'PY'
import json
import sys

field = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
value = (data.get("controller") or {}).get(field, "")
if value is None:
    value = ""
print(value)
PY
    return 0
  fi
  awk -v want="$field" '
    /"controller"[[:space:]]*:/ { in_controller=1; next }
    in_controller && /^[[:space:]]*}/ { exit }
    in_controller && $0 ~ "\"" want "\"" {
      value=$0
      sub("^[^:]*:[[:space:]]*", "", value)
      gsub("[,\"]", "", value)
      gsub("^[[:space:]]+|[[:space:]]+$", "", value)
      print value
      exit
    }
  '
}

running_supervisor_gc_path() {
  local current mode path pid
  pid="$(pgrep -f '(^|/)gc supervisor run($| )' 2>/dev/null | head -n 1 || true)"
  if [ -n "$pid" ] && [ -e "/proc/$pid/exe" ]; then
    path="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
    path="${path% (deleted)}"
    if [ -n "$path" ]; then
      echo "$path"
      return 0
    fi
  fi

  current="$(command -v gc 2>/dev/null || true)"
  if [ -z "$current" ]; then
    return 1
  fi
  if command -v timeout >/dev/null 2>&1; then
    mode="$(timeout 10s "$current" status --json "$CITY_ROOT" 2>/dev/null | controller_json_field mode || true)"
  else
    mode="$(controller_mode_for_city "$current" || true)"
  fi
  if [ "$mode" != "supervisor" ]; then
    return 1
  fi
  if command -v timeout >/dev/null 2>&1; then
    path="$(timeout 10s "$current" status --json "$CITY_ROOT" 2>/dev/null | controller_json_field binary || true)"
  else
    path="$(controller_field_for_city "$current" "binary" || true)"
  fi
  if [ -n "$path" ]; then
    echo "$path"
    return 0
  fi
  return 1
}

default_install_path() {
  local name="$1"
  local current=""
  if [ -n "$INSTALL_DIR" ]; then
    echo "$INSTALL_DIR/$name"
    return 0
  fi
  if [ "$name" = "gc" ]; then
    current="$(running_supervisor_gc_path || true)"
    if path_under_home "$current"; then
      echo "$current"
      return 0
    fi
    current="$(supervisor_gc_path || true)"
    if path_under_home "$current"; then
      echo "$current"
      return 0
    fi
  fi
  current="$(command -v "$name" 2>/dev/null || true)"
  if path_under_home "$current"; then
    echo "$current"
    return 0
  fi
  if [ -n "${HOME:-}" ]; then
    echo "$HOME/.local/bin/$name"
    return 0
  fi
  die "could not choose install path for $name; set --install-dir or --${name}-install"
}

install_binary() {
  local source="$1"
  local dest="$2"
  local name="$3"
  local requested_dest dest_dir tmp current resolved

  requested_dest="$dest"
  if [ -L "$dest" ]; then
    resolved="$(readlink -f "$dest" 2>/dev/null || true)"
    if [ -z "$resolved" ]; then
      die "installing $name refused to replace unresolved symlink: $dest"
    fi
    dest="$resolved"
    echo "resolved $name install symlink: $requested_dest -> $dest"
  fi
  dest_dir="$(dirname "$dest")"
  mkdir -p "$dest_dir"
  tmp="$dest_dir/.${name}.tmp.$$"
  rm -f "$tmp"
  if ! install -m 0755 "$source" "$tmp"; then
    rm -f "$tmp"
    die "installing $name to temporary path failed: $tmp"
  fi
  if ! mv -f "$tmp" "$dest"; then
    rm -f "$tmp"
    die "installing $name failed: $dest"
  fi
  if ! cmp -s "$source" "$dest"; then
    die "installed $name does not match built binary: $dest"
  fi
  LAST_INSTALLED_PATH="$dest"
  echo "installed $name: $dest"

  current="$(command -v "$name" 2>/dev/null || true)"
  if [ -n "$current" ] && [ "$current" != "$dest" ] && ! [[ "$current" -ef "$dest" ]]; then
    echo "note: current $name resolves to $current; ensure $dest is earlier on PATH"
  fi
}

install_bd_release_wrapper() {
  local source="$1"
  local dest="$2"
  local name="bd"
  local requested_dest dest_dir real_dest wrapper_tmp resolved current

  requested_dest="$dest"
  if [ -L "$dest" ]; then
    resolved="$(readlink -f "$dest" 2>/dev/null || true)"
    if [ -z "$resolved" ]; then
      die "installing $name refused to replace unresolved symlink: $dest"
    fi
    dest="$resolved"
    echo "resolved $name install symlink: $requested_dest -> $dest"
  fi
  dest_dir="$(dirname "$dest")"
  mkdir -p "$dest_dir"
  real_dest="$dest.doltlite-release-${GC_DOLTLITE_BD_RELEASE_VERSION:-v1.0.5-doltlite.1}"
  install_binary "$source" "$real_dest" "$name"

  wrapper_tmp="$dest_dir/.${name}.wrapper.$$"
  rm -f "$wrapper_tmp"
  cat >"$wrapper_tmp" <<EOF
#!/usr/bin/env bash
set -euo pipefail
lib_dir='${DOLTLITE_LIB}'
real_bd='${real_dest}'
export LD_LIBRARY_PATH="\${lib_dir}\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
exec "\${real_bd}" "\$@"
EOF
  chmod 0755 "$wrapper_tmp"
  if ! mv -f "$wrapper_tmp" "$dest"; then
    rm -f "$wrapper_tmp"
    die "installing $name wrapper failed: $dest"
  fi
  if ! "$dest" version >/dev/null 2>&1; then
    die "installed $name wrapper could not execute release binary with libdoltlite from $DOLTLITE_LIB"
  fi
  LAST_INSTALLED_PATH="$dest"
  echo "installed $name wrapper: $dest"

  current="$(command -v "$name" 2>/dev/null || true)"
  if [ -n "$current" ] && [ "$current" != "$dest" ] && ! [[ "$current" -ef "$dest" ]]; then
    echo "note: current $name resolves to $current; ensure $dest is earlier on PATH"
  fi
}

append_unique_path() {
  local list="$1"
  local path="$2"
  local existing
  [ -n "$path" ] || return 0
  while IFS= read -r existing; do
    [ -n "$existing" ] || continue
    if [ "$existing" = "$path" ]; then
      printf '%s' "$list"
      return 0
    fi
    if [ -e "$existing" ] && [ -e "$path" ] && [[ "$existing" -ef "$path" ]]; then
      printf '%s' "$list"
      return 0
    fi
  done <<<"$list"
  if [ -n "$list" ]; then
    printf '%s\n%s' "$list" "$path"
  else
    printf '%s' "$path"
  fi
}

gc_install_paths() {
  local primary="$1"
  local paths="" current
  paths="$(append_unique_path "$paths" "$primary")"
  if [ "$GC_INSTALL_EXPLICIT" != "1" ] && [ -z "$INSTALL_DIR" ]; then
    current="$(running_supervisor_gc_path || true)"
    if path_under_home "$current"; then
      paths="$(append_unique_path "$paths" "$current")"
    fi
    current="$(supervisor_gc_path || true)"
    if path_under_home "$current"; then
      paths="$(append_unique_path "$paths" "$current")"
    fi
    current="$(command -v gc 2>/dev/null || true)"
    if path_under_home "$current"; then
      paths="$(append_unique_path "$paths" "$current")"
    fi
  fi
  printf '%s\n' "$paths"
}

artifact_path_for_source() {
  local source_dir="$1"
  local output="$2"
  case "$output" in
    /*) echo "$output" ;;
    *) echo "$source_dir/$output" ;;
  esac
}

sha256_for() {
  local path="$1"
  local sum rest
  if command -v sha256sum >/dev/null 2>&1; then
    read -r sum rest < <(sha256sum "$path")
    echo "$sum"
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    read -r sum rest < <(shasum -a 256 "$path")
    echo "$sum"
    return 0
  fi
  die "sha256sum or shasum is required to write build details"
}

json_escape() {
  local value="${1-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

write_build_details() {
  local name="$1"
  local source_dir="$2"
  local output="$3"
  local installed_to="$4"
  local commit="$5"
  local version="$6"
  local branch="$7"
  local tags="$8"
  local built_at="$9"
  local output_path output_sha binary_path binary_sha install_sha stamp tmp go_version go_version_m

  output_path="$(artifact_path_for_source "$source_dir" "$output")"
  output_sha="$(sha256_for "$output_path")"
  binary_path="$output_path"
  binary_sha="$output_sha"
  install_sha=""
  if [ -n "$installed_to" ]; then
    binary_path="$installed_to"
    install_sha="$(sha256_for "$installed_to")"
    binary_sha="$install_sha"
  fi

  go_version="$(go version 2>/dev/null || true)"
  go_version_m="$(go version -m "$binary_path" 2>/dev/null || true)"
  if [ -z "$go_version_m" ] && [ "$binary_path" != "$output_path" ]; then
    go_version_m="$(go version -m "$output_path" 2>/dev/null || true)"
  fi

  mkdir -p "$BUILD_DETAILS_DIR"
  stamp="$BUILD_DETAILS_DIR/last-build-${name}.json"
  tmp="$stamp.tmp.$$"
  rm -f "$tmp"
  {
    printf '{\n'
    printf '  "schema_version": "1",\n'
    printf '  "pack": "beads-doltlite",\n'
    printf '  "target": "%s",\n' "$(json_escape "$name")"
    printf '  "built_at": "%s",\n' "$(json_escape "$built_at")"
    printf '  "source": "%s",\n' "$(json_escape "$source_dir")"
    printf '  "output": "%s",\n' "$(json_escape "$output_path")"
    printf '  "installed_to": "%s",\n' "$(json_escape "$installed_to")"
    printf '  "binary_path": "%s",\n' "$(json_escape "$binary_path")"
    printf '  "sha256": "%s",\n' "$(json_escape "$binary_sha")"
    printf '  "output_sha256": "%s",\n' "$(json_escape "$output_sha")"
    printf '  "install_sha256": "%s",\n' "$(json_escape "$install_sha")"
    printf '  "commit": "%s",\n' "$(json_escape "$commit")"
    printf '  "branch": "%s",\n' "$(json_escape "$branch")"
    printf '  "version": "%s",\n' "$(json_escape "$version")"
    printf '  "tags": "%s",\n' "$(json_escape "$tags")"
    printf '  "doltlite_lib": "%s",\n' "$(json_escape "$DOLTLITE_LIB")"
    printf '  "gocache": "%s",\n' "$(json_escape "${GOCACHE:-}")"
    printf '  "gomodcache": "%s",\n' "$(json_escape "${GOMODCACHE:-}")"
    printf '  "gotmpdir": "%s",\n' "$(json_escape "${GOTMPDIR:-}")"
    printf '  "go_version": "%s",\n' "$(json_escape "$go_version")"
    printf '  "goflags": "%s",\n' "$(json_escape "${GOFLAGS:-}")"
    printf '  "cgo_ldflags": "%s",\n' "$(json_escape "${CGO_LDFLAGS:-}")"
    printf '  "go_version_m": "%s"\n' "$(json_escape "$go_version_m")"
    printf '}\n'
  } >"$tmp"
  mv -f "$tmp" "$stamp"
  echo "wrote $name build details: $stamp"
}

controller_field_for_city() {
  local gc_bin="$1"
  local field="$2"
  local status_file
  status_file="$(mktemp "${TMPDIR:-/tmp}/gc-status.XXXXXX")"
  if ! "$gc_bin" status --json "$CITY_ROOT" >"$status_file" 2>/dev/null && [ ! -s "$status_file" ]; then
    rm -f "$status_file"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$field" "$status_file" <<'PY'
import json
import sys

field, path = sys.argv[1], sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
value = (data.get("controller") or {}).get(field, "")
if value is None:
    value = ""
print(value)
PY
    rm -f "$status_file"
    return 0
  fi
  awk -v want="$field" '
    /"controller"[[:space:]]*:/ { in_controller=1; next }
    in_controller && /^[[:space:]]*}/ { exit }
    in_controller && $0 ~ "\"" want "\"" {
      value=$0
      sub("^[^:]*:[[:space:]]*", "", value)
      gsub("[,\"]", "", value)
      gsub("^[[:space:]]+|[[:space:]]+$", "", value)
      print value
      exit
    }
  ' "$status_file"
  rm -f "$status_file"
}

controller_mode_for_city() {
  controller_field_for_city "$1" "mode"
}

controller_pid_for_city() {
  controller_field_for_city "$1" "pid"
}

process_alive() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

wait_for_pid_exit() {
  local pid="$1"
  local remaining="$RESTART_WAIT_SECONDS"
  while [ "$remaining" -gt 0 ]; do
    if ! process_alive "$pid"; then
      return 0
    fi
    sleep 1
    remaining=$((remaining - 1))
  done
  ! process_alive "$pid"
}

terminate_controller_pid() {
  local pid="$1"
  if ! process_alive "$pid"; then
    return 0
  fi
  echo "stopping leftover city controller PID $pid"
  kill "$pid" >/dev/null 2>&1 || true
  if wait_for_pid_exit "$pid"; then
    return 0
  fi
  echo "force-stopping leftover city controller PID $pid"
  kill -KILL "$pid" >/dev/null 2>&1 || true
  wait_for_pid_exit "$pid" || die "city controller PID $pid did not stop"
}

stop_standalone_controller_if_running() {
  local gc_bin="$1"
  local mode pid
  mode="$(controller_mode_for_city "$gc_bin" || true)"
  if [ "$mode" != "standalone" ]; then
    return 0
  fi
  pid="$(controller_pid_for_city "$gc_bin" || true)"
  echo "stopping standalone city controller${pid:+ PID $pid}"
  "$gc_bin" stop "$CITY_ROOT" --force --timeout "${RESTART_WAIT_SECONDS}s" || die "stopping standalone city controller failed"
  if [ -n "$pid" ]; then
    terminate_controller_pid "$pid"
  fi
}

stop_supervisor_if_running() {
  local gc_bin="$1"
  if ! "$gc_bin" supervisor status >/dev/null 2>&1; then
    echo "supervisor already stopped"
    return 0
  fi
  echo "stopping supervisor"
  "$gc_bin" supervisor stop --wait --wait-timeout "${RESTART_WAIT_SECONDS}s" || die "stopping supervisor failed"
  if "$gc_bin" supervisor status >/dev/null 2>&1; then
    die "supervisor still running after stop"
  fi
}

stop_leftover_controller_if_running() {
  local gc_bin="$1"
  local pid
  pid="$(controller_pid_for_city "$gc_bin" || true)"
  if [ -z "$pid" ]; then
    return 0
  fi
  terminate_controller_pid "$pid"
}

current_gc_for_stop() {
  if [ -n "$GC_INSTALL" ] && [ -x "$GC_INSTALL" ]; then
    echo "$GC_INSTALL"
    return 0
  fi
  if command -v gc >/dev/null 2>&1; then
    command -v gc
    return 0
  fi
  return 1
}

target_includes_gc() {
  [ "$TARGET" = "gc" ] || [ "$TARGET" = "all" ]
}

prepare_gc_install_path() {
  if [ "$INSTALL_BUILT" != "1" ] || [ "$RESTART_AFTER_INSTALL" != "1" ] || ! target_includes_gc; then
    return 0
  fi
  if [ -z "$GC_INSTALL" ]; then
    GC_INSTALL="$(default_install_path gc)"
  fi
}

stop_before_gc_build() {
  if [ "$INSTALL_BUILT" != "1" ] || [ "$RESTART_AFTER_INSTALL" != "1" ] || ! target_includes_gc; then
    return 0
  fi
  local gc_bin
  gc_bin="$(current_gc_for_stop || true)"
  if [ -z "$gc_bin" ]; then
    die "restart requires an existing gc binary to stop current services; pass --no-restart to build without cycling services"
  fi

  echo "stopping gc services before build with $gc_bin"
  stop_standalone_controller_if_running "$gc_bin"
  stop_supervisor_if_running "$gc_bin"
  stop_leftover_controller_if_running "$gc_bin"
  GC_SERVICES_STOPPED_FOR_BUILD=1
}

start_after_gc_install() {
  local gc_bin="$1"
  if [ "$RESTART_AFTER_INSTALL" != "1" ]; then
    echo "restart after gc install disabled"
    return 0
  fi
  if [ ! -x "$gc_bin" ]; then
    die "installed gc is not executable: $gc_bin"
  fi

  if [ "$GC_SERVICES_STOPPED_FOR_BUILD" != "1" ]; then
    die "refusing to start gc services because they were not stopped before build"
  fi

  echo "starting city from $CITY_ROOT"
  "$gc_bin" start "$CITY_ROOT" || die "starting city after gc install failed"
}

build_gc() {
  if [ "$BUILD_GC_FROM_SOURCE" != "1" ] && [ -z "$GASCITY_SRC" ]; then
    local release_bin installed_to date version commit source_label
    if release_bin="$(ensure_gc_release_binary)"; then
      version="$(basename "$(dirname "$(dirname "$release_bin")")")"
      commit="${GC_COMMIT:-unknown}"
      date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      source_label="release:$version"
      echo "using released DoltLite-linked gc binary: $release_bin"
      verify_gc_binary "$release_bin"
      installed_to=""
      if [ "$INSTALL_BUILT" = "1" ]; then
        if [ -z "$GC_INSTALL" ]; then
          GC_INSTALL="$(default_install_path gc)"
        fi
        while IFS= read -r install_path; do
          [ -n "$install_path" ] || continue
          install_binary "$release_bin" "$install_path" "gc"
          if [ -z "$installed_to" ]; then
            installed_to="$LAST_INSTALLED_PATH"
          fi
        done < <(gc_install_paths "$GC_INSTALL")
      fi
      write_build_details "gc" "$source_label" "$release_bin" "$installed_to" "$commit" "$version" "release" "gascity_doltlite_lib,libsqlite3" "$date"
      if [ -n "$installed_to" ]; then
        start_after_gc_install "$installed_to"
        write_build_details "gc" "$source_label" "$release_bin" "$installed_to" "$commit" "$version" "release" "gascity_doltlite_lib,libsqlite3" "$date"
      fi
      return 0
    fi
    echo "DoltLite-linked gc release unavailable; falling back to source build" >&2
  fi

  if [ -z "$GASCITY_SRC" ] && [ "$SKIP_LOCAL_SOURCE" != "1" ]; then
    GASCITY_SRC="$(find_gascity_source || true)"
  fi
  if [ -z "$GASCITY_SRC" ]; then
    GASCITY_SRC="$(fetch_gascity_source)"
  fi
  if [ -z "$GASCITY_SRC" ] || ! has_gascity_source "$GASCITY_SRC"; then
    die "could not find Gas City source; set GASCITY_SRC=/path/to/gascity or pass --gc-source"
  fi
  GASCITY_SRC="$(abs_dir "$GASCITY_SRC")"

  if [ -z "$GC_OUTPUT" ]; then
    GC_OUTPUT="$GASCITY_SRC/bin/gc"
  fi

  local commit="${GC_COMMIT:-}"
  if [ -z "$commit" ]; then
    commit="$(revision_for "$GASCITY_SRC")"
  fi
  commit="${commit:-unknown}"
  local date="${GC_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

  mkdir -p "$(dirname "$GC_OUTPUT")"
  common_env_prefix "gascity_doltlite_lib,libsqlite3"

  echo "building gc from $GASCITY_SRC"
  echo "linking libdoltlite from $DOLTLITE_LIB"
  echo "writing $GC_OUTPUT"

  (
    cd "$GASCITY_SRC"
    go build \
      -ldflags "-X main.version=${VERSION} -X main.commit=${commit} -X main.date=${date}" \
      -o "$GC_OUTPUT" \
      ./cmd/gc
  )

  verify_gc_binary "$GC_OUTPUT"
  echo "built libdoltlite-linked native DoltLite beads gc: $GC_OUTPUT"

  local installed_to=""
  if [ "$INSTALL_BUILT" = "1" ]; then
    if [ -z "$GC_INSTALL" ]; then
      GC_INSTALL="$(default_install_path gc)"
    fi
    while IFS= read -r install_path; do
      [ -n "$install_path" ] || continue
      install_binary "$GC_OUTPUT" "$install_path" "gc"
      if [ -z "$installed_to" ]; then
        installed_to="$LAST_INSTALLED_PATH"
      fi
    done < <(gc_install_paths "$GC_INSTALL")
  fi
  write_build_details "gc" "$GASCITY_SRC" "$GC_OUTPUT" "$installed_to" "$commit" "$VERSION" "" "gascity_doltlite_lib,libsqlite3" "$date"
  if [ -n "$installed_to" ]; then
    start_after_gc_install "$installed_to"
    write_build_details "gc" "$GASCITY_SRC" "$GC_OUTPUT" "$installed_to" "$commit" "$VERSION" "" "gascity_doltlite_lib,libsqlite3" "$date"
  fi
}

build_bd() {
  if [ "$BUILD_BD_FROM_SOURCE" != "1" ] && [ -z "$BD_SRC" ]; then
    local release_bin installed_to date version commit
    if [ "$DOLTLITE_LIB_EXPLICIT" != "1" ]; then
      DOLTLITE_LIB="$(ensure_doltlite_release_lib)"
      DOLTLITE_LIB="$(abs_dir "$DOLTLITE_LIB")"
    fi
    release_bin="$(ensure_bd_release_binary)"
    version="${GC_DOLTLITE_BD_RELEASE_VERSION:-v1.0.5-doltlite.1}"
    commit="${BD_COMMIT:-02bc3e532a54683bac4df3f78578511fe3cf931f}"
    date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "using released bd DoltLite binary: $release_bin"
    verify_linked_binary "$release_bin" "bd"
    installed_to=""
    if [ "$INSTALL_BUILT" = "1" ]; then
      if [ -z "$BD_INSTALL" ]; then
        BD_INSTALL="$(default_install_path bd)"
      fi
      install_bd_release_wrapper "$release_bin" "$BD_INSTALL"
      installed_to="$LAST_INSTALLED_PATH"
    fi
    write_build_details "bd" "release:$version" "$release_bin" "$installed_to" "$commit" "$version" "main" "libsqlite3" "$date"
    return 0
  fi

  if [ -z "$BD_SRC" ] && [ "$SKIP_LOCAL_SOURCE" != "1" ]; then
    BD_SRC="$(find_bd_source || true)"
  fi
  if [ -z "$BD_SRC" ]; then
    BD_SRC="$(fetch_bd_source)"
  fi
  if [ -z "$BD_SRC" ] || ! has_bd_source "$BD_SRC"; then
    die "could not find beads-doltlite source; set BD_SRC=/path/to/beads-doltlite or pass --bd-source"
  fi
  BD_SRC="$(abs_dir "$BD_SRC")"

  if [ -z "$BD_OUTPUT" ]; then
    BD_OUTPUT="$BD_SRC/bin/bd"
  fi

  local commit="${BD_COMMIT:-}"
  if [ -z "$commit" ]; then
    commit="$(revision_for "$BD_SRC")"
  fi
  commit="${commit:-unknown}"
  local branch="${BD_BRANCH:-}"
  if [ -z "$branch" ]; then
    branch="$(branch_for "$BD_SRC")"
  fi
  local date
  date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local ldflags="-X main.Build=${BD_BUILD_VALUE} -X main.Commit=${commit}"
  if [ -n "$branch" ]; then
    ldflags="${ldflags} -X main.Branch=${branch}"
  fi

  mkdir -p "$(dirname "$BD_OUTPUT")"
  common_env_prefix "libsqlite3"

  echo "building bd from $BD_SRC"
  echo "linking libdoltlite from $DOLTLITE_LIB"
  echo "writing $BD_OUTPUT"

  (
    cd "$BD_SRC"
    go build \
      -ldflags "$ldflags" \
      -o "$BD_OUTPUT" \
      ./cmd/bd
  )

  verify_linked_binary "$BD_OUTPUT" "bd"
  echo "built libdoltlite-linked bd: $BD_OUTPUT"

  local installed_to=""
  if [ "$INSTALL_BUILT" = "1" ]; then
    if [ -z "$BD_INSTALL" ]; then
      BD_INSTALL="$(default_install_path bd)"
    fi
    install_binary "$BD_OUTPUT" "$BD_INSTALL" "bd"
    installed_to="$LAST_INSTALLED_PATH"
  fi
  write_build_details "bd" "$BD_SRC" "$BD_OUTPUT" "$installed_to" "$commit" "$BD_BUILD_VALUE" "$branch" "libsqlite3" "$date"
}

build_client() {
  if [ -z "$GASCITY_SRC" ] && [ "$SKIP_LOCAL_SOURCE" != "1" ]; then
    GASCITY_SRC="$(find_gascity_source || true)"
  fi
  if [ -z "$GASCITY_SRC" ]; then
    GASCITY_SRC="$(fetch_gascity_source)"
  fi
  if [ -z "$GASCITY_SRC" ] || ! has_gascity_source "$GASCITY_SRC"; then
    die "could not find Gas City source; set GASCITY_SRC=/path/to/gascity or pass --gc-source"
  fi
  GASCITY_SRC="$(abs_dir "$GASCITY_SRC")"

  if [ ! -f "$GASCITY_SRC/tools/doltlite-client/main.go" ]; then
    die "could not find doltlite-client source under $GASCITY_SRC/tools/doltlite-client"
  fi

  if [ -z "$CLIENT_OUTPUT" ]; then
    CLIENT_OUTPUT="$BUILD_DETAILS_DIR/bin/doltlite-client"
  fi

  local commit="${GC_COMMIT:-}"
  if [ -z "$commit" ]; then
    commit="$(revision_for "$GASCITY_SRC")"
  fi
  commit="${commit:-unknown}"
  local date="${GC_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

  mkdir -p "$(dirname "$CLIENT_OUTPUT")"
  common_env_prefix "gascity_doltlite_lib,libsqlite3"

  echo "building doltlite-client from $GASCITY_SRC"
  echo "linking libdoltlite from $DOLTLITE_LIB"
  echo "writing $CLIENT_OUTPUT"

  (
    cd "$GASCITY_SRC"
    go build \
      -o "$CLIENT_OUTPUT" \
      ./tools/doltlite-client
  )

  verify_linked_binary "$CLIENT_OUTPUT" "doltlite-client"
  echo "built libdoltlite-linked doltlite-client: $CLIENT_OUTPUT"
  write_build_details "doltlite-client" "$GASCITY_SRC" "$CLIENT_OUTPUT" "$CLIENT_OUTPUT" "$commit" "dev" "" "gascity_doltlite_lib,libsqlite3" "$date"
}

CITY_ROOT="${GC_CITY_PATH:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT_CHECKOUT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BASE_GOFLAGS="${GOFLAGS:-}"
BASE_CGO_CFLAGS="${CGO_CFLAGS:-}"
BASE_CGO_LDFLAGS="${CGO_LDFLAGS:-}"
BASE_LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"

TARGET="gc"
COMMON_SOURCE=""
COMMON_OUTPUT="${OUTPUT:-}"
GASCITY_SRC="${GASCITY_SRC:-${GC_GASCITY_SRC:-}}"
BD_SRC="${BD_SRC:-${BEADS_DOLTLITE_SRC:-${GC_BEADS_DOLTLITE_SRC:-}}}"
DOLTLITE_LIB="${DOLTLITE_LIB:-${GC_DOLTLITE_LIB:-}}"
DOLTLITE_LIB_EXPLICIT=0
if [ -n "${DOLTLITE_LIB:-}" ]; then
  DOLTLITE_LIB_EXPLICIT=1
fi
GC_OUTPUT="${GC_DOLTLITE_GC_OUTPUT:-}"
BD_OUTPUT="${BD_OUTPUT:-${GC_DOLTLITE_BD_OUTPUT:-}}"
CLIENT_OUTPUT="${GC_DOLTLITE_CLIENT_OUTPUT:-}"
INSTALL_BUILT="${GC_DOLTLITE_INSTALL:-0}"
INSTALL_DIR="${GC_DOLTLITE_INSTALL_DIR:-}"
GC_INSTALL="${GC_DOLTLITE_GC_INSTALL:-}"
BD_INSTALL="${GC_DOLTLITE_BD_INSTALL:-}"
GC_INSTALL_EXPLICIT=0
if [ -n "${GC_DOLTLITE_GC_INSTALL:-}" ]; then
  GC_INSTALL_EXPLICIT=1
fi
BUILD_DETAILS_DIR="${GC_DOLTLITE_BUILD_DETAILS_DIR:-}"
GO_CACHE_ROOT="${GC_DOLTLITE_GO_CACHE_ROOT:-}"
RESTART_AFTER_INSTALL="${GC_DOLTLITE_RESTART_AFTER_INSTALL:-1}"
RESTART_WAIT_SECONDS="${GC_DOLTLITE_RESTART_WAIT_SECONDS:-180}"
SKIP_LOCAL_SOURCE="${GC_DOLTLITE_SKIP_LOCAL_SOURCE:-0}"
SKIP_LOCAL_LIB="${GC_DOLTLITE_SKIP_LOCAL_LIB:-0}"
BUILD_BD_FROM_SOURCE="${GC_DOLTLITE_BUILD_BD_FROM_SOURCE:-0}"
BUILD_GC_FROM_SOURCE="${GC_DOLTLITE_BUILD_GC_FROM_SOURCE:-0}"
GC_SERVICES_STOPPED_FOR_BUILD=0
LAST_INSTALLED_PATH=""
VERSION="${GC_VERSION:-dev}"
BD_BUILD_VALUE="${BD_BUILD:-dev}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    gc|bd|client|all)
      TARGET="$1"
      shift
      ;;
    --target)
      require_value "$1" "${2:-}"
      TARGET="$2"
      shift 2
      ;;
    --target=*)
      TARGET="${1#*=}"
      shift
      ;;
    --source)
      require_value "$1" "${2:-}"
      COMMON_SOURCE="$2"
      shift 2
      ;;
    --source=*)
      COMMON_SOURCE="${1#*=}"
      shift
      ;;
    --gc-source)
      require_value "$1" "${2:-}"
      GASCITY_SRC="$2"
      shift 2
      ;;
    --gc-source=*)
      GASCITY_SRC="${1#*=}"
      shift
      ;;
    --bd-source)
      require_value "$1" "${2:-}"
      BD_SRC="$2"
      shift 2
      ;;
    --bd-source=*)
      BD_SRC="${1#*=}"
      shift
      ;;
    --skip-local-source|--no-local-source)
      SKIP_LOCAL_SOURCE=1
      shift
      ;;
    --use-local-source)
      SKIP_LOCAL_SOURCE=0
      shift
      ;;
    --build-bd-from-source)
      BUILD_BD_FROM_SOURCE=1
      shift
      ;;
    --build-gc-from-source)
      BUILD_GC_FROM_SOURCE=1
      shift
      ;;
    --skip-local-lib|--no-local-lib)
      SKIP_LOCAL_LIB=1
      shift
      ;;
    --use-local-lib)
      SKIP_LOCAL_LIB=0
      shift
      ;;
    --lib)
      require_value "$1" "${2:-}"
      DOLTLITE_LIB="$2"
      DOLTLITE_LIB_EXPLICIT=1
      shift 2
      ;;
    --lib=*)
      DOLTLITE_LIB="${1#*=}"
      DOLTLITE_LIB_EXPLICIT=1
      shift
      ;;
    --output)
      require_value "$1" "${2:-}"
      COMMON_OUTPUT="$2"
      shift 2
      ;;
    --output=*)
      COMMON_OUTPUT="${1#*=}"
      shift
      ;;
    --gc-output)
      require_value "$1" "${2:-}"
      GC_OUTPUT="$2"
      shift 2
      ;;
    --gc-output=*)
      GC_OUTPUT="${1#*=}"
      shift
      ;;
    --bd-output)
      require_value "$1" "${2:-}"
      BD_OUTPUT="$2"
      shift 2
      ;;
    --bd-output=*)
      BD_OUTPUT="${1#*=}"
      shift
      ;;
    --client-output)
      require_value "$1" "${2:-}"
      CLIENT_OUTPUT="$2"
      shift 2
      ;;
    --client-output=*)
      CLIENT_OUTPUT="${1#*=}"
      shift
      ;;
    --install)
      INSTALL_BUILT=1
      shift
      ;;
    --install-dir)
      require_value "$1" "${2:-}"
      INSTALL_DIR="$2"
      INSTALL_BUILT=1
      shift 2
      ;;
    --install-dir=*)
      INSTALL_DIR="${1#*=}"
      INSTALL_BUILT=1
      shift
      ;;
    --gc-install)
      require_value "$1" "${2:-}"
      GC_INSTALL="$2"
      GC_INSTALL_EXPLICIT=1
      INSTALL_BUILT=1
      shift 2
      ;;
    --gc-install=*)
      GC_INSTALL="${1#*=}"
      GC_INSTALL_EXPLICIT=1
      INSTALL_BUILT=1
      shift
      ;;
    --bd-install)
      require_value "$1" "${2:-}"
      BD_INSTALL="$2"
      INSTALL_BUILT=1
      shift 2
      ;;
    --bd-install=*)
      BD_INSTALL="${1#*=}"
      INSTALL_BUILT=1
      shift
      ;;
    --build-details-dir)
      require_value "$1" "${2:-}"
      BUILD_DETAILS_DIR="$2"
      shift 2
      ;;
    --build-details-dir=*)
      BUILD_DETAILS_DIR="${1#*=}"
      shift
      ;;
    --restart)
      RESTART_AFTER_INSTALL=1
      shift
      ;;
    --no-restart)
      RESTART_AFTER_INSTALL=0
      shift
      ;;
    --version)
      require_value "$1" "${2:-}"
      VERSION="$2"
      shift 2
      ;;
    --version=*)
      VERSION="${1#*=}"
      shift
      ;;
    --bd-build)
      require_value "$1" "${2:-}"
      BD_BUILD_VALUE="$2"
      shift 2
      ;;
    --bd-build=*)
      BD_BUILD_VALUE="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage_error "unknown argument: $1"
      ;;
  esac
done

case "$TARGET" in
  gc|bd|client|all) ;;
  *) usage_error "unknown target: $TARGET" ;;
esac

if [ -n "$COMMON_SOURCE" ]; then
  case "$TARGET" in
    gc) GASCITY_SRC="$COMMON_SOURCE" ;;
    bd) BD_SRC="$COMMON_SOURCE" ;;
    client) GASCITY_SRC="$COMMON_SOURCE" ;;
    all) usage_error "--source is ambiguous with target all; use --gc-source and --bd-source" ;;
  esac
fi

if [ -n "$COMMON_OUTPUT" ]; then
  case "$TARGET" in
    gc) GC_OUTPUT="$COMMON_OUTPUT" ;;
    bd) BD_OUTPUT="$COMMON_OUTPUT" ;;
    client) CLIENT_OUTPUT="$COMMON_OUTPUT" ;;
    all) usage_error "--output is ambiguous with target all; use --gc-output, --bd-output, and --client-output" ;;
  esac
fi

case "${INSTALL_BUILT,,}" in
  1|true|yes|on) INSTALL_BUILT=1 ;;
  ""|0|false|no|off) INSTALL_BUILT=0 ;;
  *) usage_error "GC_DOLTLITE_INSTALL must be true or false" ;;
esac

case "${RESTART_AFTER_INSTALL,,}" in
  1|true|yes|on) RESTART_AFTER_INSTALL=1 ;;
  ""|0|false|no|off) RESTART_AFTER_INSTALL=0 ;;
  *) usage_error "GC_DOLTLITE_RESTART_AFTER_INSTALL must be true or false" ;;
esac

case "${SKIP_LOCAL_SOURCE,,}" in
  1|true|yes|on) SKIP_LOCAL_SOURCE=1 ;;
  ""|0|false|no|off) SKIP_LOCAL_SOURCE=0 ;;
  *) usage_error "GC_DOLTLITE_SKIP_LOCAL_SOURCE must be true or false" ;;
esac

case "${SKIP_LOCAL_LIB,,}" in
  1|true|yes|on) SKIP_LOCAL_LIB=1 ;;
  ""|0|false|no|off) SKIP_LOCAL_LIB=0 ;;
  *) usage_error "GC_DOLTLITE_SKIP_LOCAL_LIB must be true or false" ;;
esac

case "${BUILD_GC_FROM_SOURCE,,}" in
  1|true|yes|on) BUILD_GC_FROM_SOURCE=1 ;;
  ""|0|false|no|off) BUILD_GC_FROM_SOURCE=0 ;;
  *) usage_error "GC_DOLTLITE_BUILD_GC_FROM_SOURCE must be true or false" ;;
esac

case "${BUILD_BD_FROM_SOURCE,,}" in
  1|true|yes|on) BUILD_BD_FROM_SOURCE=1 ;;
  ""|0|false|no|off) BUILD_BD_FROM_SOURCE=0 ;;
  *) usage_error "GC_DOLTLITE_BUILD_BD_FROM_SOURCE must be true or false" ;;
esac

case "$RESTART_WAIT_SECONDS" in
  ''|*[!0-9]*) usage_error "GC_DOLTLITE_RESTART_WAIT_SECONDS must be a positive integer" ;;
  0) usage_error "GC_DOLTLITE_RESTART_WAIT_SECONDS must be greater than zero" ;;
esac

if [ -z "$DOLTLITE_LIB" ]; then
  DOLTLITE_LIB="$(find_doltlite_lib || true)"
fi
if [ -z "$DOLTLITE_LIB" ] || ! has_doltlite_lib "$DOLTLITE_LIB"; then
  die "could not find libdoltlite; set DOLTLITE_LIB=/path/to/doltlite-work/build or pass --lib"
fi
DOLTLITE_LIB="$(abs_dir "$DOLTLITE_LIB")"

if [ -z "$BUILD_DETAILS_DIR" ]; then
  BUILD_DETAILS_DIR="${GC_PACK_STATE_DIR:-$CITY_ROOT/.gc/runtime/packs/beads-doltlite}"
fi
if [ -z "$GO_CACHE_ROOT" ]; then
  GO_CACHE_ROOT="$CITY_ROOT/.cache/go"
fi
if [ -z "${GOCACHE:-}" ]; then
  export GOCACHE="$GO_CACHE_ROOT/build"
fi
if [ -z "${GOMODCACHE:-}" ]; then
  export GOMODCACHE="$GO_CACHE_ROOT/mod"
fi
if [ -z "${GOTMPDIR:-}" ]; then
  export GOTMPDIR="$GO_CACHE_ROOT/tmp"
fi
mkdir -p "$GOCACHE" "$GOMODCACHE" "$GOTMPDIR"

if ! command -v go >/dev/null 2>&1; then
  die "go is required to build DoltLite-linked binaries"
fi

prepare_gc_install_path
stop_before_gc_build

case "$TARGET" in
  gc)
    build_gc
    ;;
  bd)
    build_bd
    ;;
  client)
    build_client
    ;;
  all)
    build_bd
    build_client
    build_gc
    ;;
esac
