#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPAT_DIR="$ROOT_DIR/compat"
ARCHIVE_DIR="$COMPAT_DIR/archives"
BUILD_DIR="$COMPAT_DIR/build"
LIB_DIR="$COMPAT_DIR/lib"
X11_DIR="$COMPAT_DIR/x11"
FONT_DIR="$COMPAT_DIR/fonts"
SHIM_DIR="$ROOT_DIR/shim"
SHIM_OUT_DIR="$ROOT_DIR/compat/shim"
BIN_DIR="$ROOT_DIR/extracted"
NETSCAPE_BIN="$BIN_DIR/netscape"
NETSCAPE_ARCHIVE="${NETSCAPE_ARCHIVE:-$ROOT_DIR/netscape-v304-export_x86-unknown-linux-elf_tar.gz}"

BASE_URL="https://archive.debian.org/debian"

PACKAGES=(
  "dists/slink/main/binary-i386/base/ldso_1.9.10-1.deb"
  "dists/slink/main/binary-i386/oldlibs/libc5_5.4.46-3.deb"
  "dists/slink/main/binary-i386/x11/xlib6g_3.3.2.3a-11.deb"
  "dists/slink/main/binary-i386/x11/xpm4g_3.4j-0.6.deb"
  "dists/slink/main/binary-i386/x11/xfonts-base_3.3.2.3a-11.deb"
  "dists/slink/main/binary-i386/x11/xfonts-75dpi_3.3.2.3a-11.deb"
  "dists/slink/main/binary-i386/x11/xfonts-100dpi_3.3.2.3a-11.deb"
)

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  }
}

extract_deb_data() {
  local deb="$1"
  local dest="$2"

  rm -rf "$dest"
  mkdir -p "$dest/pkg" "$dest/root"
  (
    cd "$dest/pkg"
    ar x "$deb"
  )
  tar -xzf "$dest/pkg/data.tar.gz" -C "$dest/root"
}

copy_matches() {
  local src_dir="$1"
  shift
  local pattern
  for pattern in "$@"; do
    find "$src_dir" -maxdepth 1 -name "$pattern" -exec cp -a {} "$LIB_DIR/" \;
  done
}

print_staged_entries() {
  local label="$1"
  local dir="$2"

  printf '\n%s in %s\n' "$label" "$dir"
  find "$dir" -mindepth 1 -maxdepth 1 | sort
}

need_cmd curl
need_cmd ar
need_cmd find
need_cmd gcc
need_cmd tar

if [[ ! -x "$NETSCAPE_BIN" && ! -f "$NETSCAPE_ARCHIVE" ]]; then
  printf 'missing Netscape archive: %s\n' "$NETSCAPE_ARCHIVE" >&2
  exit 1
fi

mkdir -p "$ARCHIVE_DIR" "$BUILD_DIR" "$LIB_DIR" "$X11_DIR" "$FONT_DIR"

for relpath in "${PACKAGES[@]}"; do
  file_name="${relpath##*/}"
  if [[ ! -f "$ARCHIVE_DIR/$file_name" ]]; then
    printf 'downloading %s\n' "$file_name"
    curl -fL "$BASE_URL/$relpath" -o "$ARCHIVE_DIR/$file_name"
  fi
done

rm -rf "$BUILD_DIR" "$LIB_DIR" "$X11_DIR" "$FONT_DIR"
mkdir -p "$BUILD_DIR" "$LIB_DIR" "$X11_DIR" "$FONT_DIR"

extract_deb_data "$ARCHIVE_DIR/ldso_1.9.10-1.deb" "$BUILD_DIR/ldso"
extract_deb_data "$ARCHIVE_DIR/libc5_5.4.46-3.deb" "$BUILD_DIR/libc5"
extract_deb_data "$ARCHIVE_DIR/xlib6g_3.3.2.3a-11.deb" "$BUILD_DIR/xlib6g"
extract_deb_data "$ARCHIVE_DIR/xpm4g_3.4j-0.6.deb" "$BUILD_DIR/xpm4g"
extract_deb_data "$ARCHIVE_DIR/xfonts-base_3.3.2.3a-11.deb" "$BUILD_DIR/xfonts-base"
extract_deb_data "$ARCHIVE_DIR/xfonts-75dpi_3.3.2.3a-11.deb" "$BUILD_DIR/xfonts-75dpi"
extract_deb_data "$ARCHIVE_DIR/xfonts-100dpi_3.3.2.3a-11.deb" "$BUILD_DIR/xfonts-100dpi"

copy_matches "$BUILD_DIR/ldso/root/lib" "ld-linux.so.1*" "libdl.so.1*"
copy_matches "$BUILD_DIR/libc5/root/lib" "libc.so.5*"
copy_matches "$BUILD_DIR/xlib6g/root/usr/X11R6/lib" \
  "libICE.so.6*" \
  "libSM.so.6*" \
  "libX11.so.6*" \
  "libXext.so.6*" \
  "libXmu.so.6*" \
  "libXt.so.6*"
copy_matches "$BUILD_DIR/xpm4g/root/usr/X11R6/lib" "libXpm.so.4*"

cp -a "$BUILD_DIR/xlib6g/root/usr/X11R6/lib/X11/." "$X11_DIR/"
cp -a "$BUILD_DIR/xfonts-base/root/usr/X11R6/lib/X11/fonts/misc" "$FONT_DIR/"
cp -a "$BUILD_DIR/xfonts-75dpi/root/usr/X11R6/lib/X11/fonts/75dpi" "$FONT_DIR/"
cp -a "$BUILD_DIR/xfonts-100dpi/root/usr/X11R6/lib/X11/fonts/100dpi" "$FONT_DIR/"

mkdir -p "$SHIM_OUT_DIR"
gcc -m32 -shared -fPIC \
  -Wl,-soname,libnetscape_compat_shim.so \
  -o "$SHIM_OUT_DIR/libnetscape_compat_shim.so" \
  "$SHIM_DIR/netscape_compat_shim.c"

if [[ ! -x "$NETSCAPE_BIN" ]]; then
  mkdir -p "$BIN_DIR"
  tar -xzf "$NETSCAPE_ARCHIVE" -C "$BIN_DIR"
fi

print_staged_entries "compat libraries staged" "$LIB_DIR"
print_staged_entries "X11 support data staged" "$X11_DIR"
print_staged_entries "bitmap fonts staged" "$FONT_DIR"
printf '\nshim built at %s\n' "$SHIM_OUT_DIR/libnetscape_compat_shim.so"
printf 'netscape available at %s\n' "$NETSCAPE_BIN"
