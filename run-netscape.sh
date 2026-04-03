#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPAT_LIB_DIR="$ROOT_DIR/compat/lib"
SHIM_LIB="$ROOT_DIR/compat/shim/libnetscape_compat_shim.so"
X11_DATA_DIR="$ROOT_DIR/compat/x11"
FONT_ROOT="$ROOT_DIR/compat/fonts"
STATE_HOME="$ROOT_DIR/state/home"
BIN_DIR="$ROOT_DIR/extracted"
NETSCAPE_BIN="$BIN_DIR/netscape"
ARCHIVE_PATH="${NETSCAPE_ARCHIVE:-$ROOT_DIR/netscape-v304-export_x86-unknown-linux-elf_tar.gz}"
LOADER_CANDIDATES=(
  "/usr/lib32/ld-linux.so.2"
  "/usr/lib/ld-linux.so.2"
)

find_loader() {
  local candidate
  for candidate in "${LOADER_CANDIDATES[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

add_font_path() {
  local path="$1"
  if [[ -d "$path" ]] && command -v xset >/dev/null 2>&1; then
    xset q 2>/dev/null | grep -Fq "$path" && return 0
    xset +fp "$path" >/dev/null 2>&1 || true
  fi
}

remove_font_path() {
  local path="$1"
  if [[ -d "$path" ]] && command -v xset >/dev/null 2>&1; then
    xset -fp "$path" >/dev/null 2>&1 || true
  fi
}

cleanup_font_paths() {
  remove_font_path "$FONT_ROOT/misc"
  remove_font_path "$FONT_ROOT/75dpi"
  remove_font_path "$FONT_ROOT/100dpi"
  if command -v xset >/dev/null 2>&1; then
    xset fp rehash >/dev/null 2>&1 || true
  fi
}

cleanup_and_exit() {
  local status="${1:-0}"
  cleanup_font_paths
  exit "$status"
}

if [[ ! -x "$NETSCAPE_BIN" ]]; then
  printf 'missing %s\n' "$NETSCAPE_BIN" >&2
  printf 'run ./setup.sh first.\n' >&2
  if [[ ! -f "$ARCHIVE_PATH" ]]; then
    printf 'expected Netscape archive at %s\n' "$ARCHIVE_PATH" >&2
  fi
  exit 1
fi

if [[ ! -d "$COMPAT_LIB_DIR" ]]; then
  printf 'missing compat libraries in %s\n' "$COMPAT_LIB_DIR" >&2
  printf 'run ./setup.sh first.\n' >&2
  exit 1
fi

if [[ ! -f "$SHIM_LIB" ]]; then
  printf 'missing shim library in %s\n' "$SHIM_LIB" >&2
  printf 'run ./setup.sh first.\n' >&2
  exit 1
fi

LOADER="$(find_loader)" || {
  printf 'could not find a 32-bit glibc loader on this host.\n' >&2
  printf 'expected one of:\n' >&2
  printf '  %s\n' "${LOADER_CANDIDATES[@]}" >&2
  exit 1
}

mkdir -p "$STATE_HOME"
cd "$ROOT_DIR"

X11_DATA_CWD="/proc/self/cwd/compat/x11"

export HOME="$STATE_HOME"
export LANG=C
export LC_ALL=C
if [[ -f "$X11_DATA_DIR/XKeysymDB" ]]; then
  export XKEYSYMDB="$X11_DATA_CWD/XKeysymDB"
fi
if [[ -d "$X11_DATA_DIR/locale" ]]; then
  export XNLSPATH="$X11_DATA_CWD/locale"
  export XLOCALEDIR="$X11_DATA_CWD/locale"
fi
export MOZILLA_HOME="$BIN_DIR"
export LD_LIBRARY_PATH="$COMPAT_LIB_DIR"
ARGS=()

if [[ "${NETSCAPE_STDIO_TO_TERMINAL:-0}" == "1" ]]; then
  ARGS+=(-xrm '*useStdoutDialog: False' -xrm '*useStderrDialog: False')
fi

if command -v xset >/dev/null 2>&1; then
  add_font_path "$FONT_ROOT/misc"
  add_font_path "$FONT_ROOT/75dpi"
  add_font_path "$FONT_ROOT/100dpi"
  xset fp rehash >/dev/null 2>&1 || true
else
  printf 'warning: xset not found; bundled bitmap fonts were not registered, so old X font warnings may remain.\n' >&2
fi

trap 'cleanup_and_exit 130' INT
trap 'cleanup_and_exit 143' TERM
trap 'cleanup_and_exit 129' HUP
trap cleanup_font_paths EXIT

"$LOADER" \
  --library-path "$COMPAT_LIB_DIR" \
  --preload "./compat/shim/libnetscape_compat_shim.so" \
  "$NETSCAPE_BIN" \
  "${ARGS[@]}" \
  "$@"

status=$?
cleanup_and_exit "$status"
