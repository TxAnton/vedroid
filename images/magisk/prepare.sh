#!/usr/bin/env bash
# Lay out a "bootless" Magisk for Redroid under <outdir>, ready to COPY into
# an image. Redroid has no boot image to patch, so Magisk is started from an
# init .rc instead (approach from ayasa520/redroid-script).
set -euo pipefail

OUT="${1:?usage: prepare.sh <outdir>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="${VEDROID_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/vedroid}"

# Magisk build that supports running without a boot image on Redroid.
# The fork's v30.7 release tag ships Magisk 30.6 (versionCode 30600).
MAGISK_URL="https://github.com/ayasa520/Magisk/releases/download/v30.7/Magisk-v30.7.apk"
MAGISK_SHA256="a1292054b25c31f19f4cdc3f33b8b48020574fc237eabd7633e54193698ac396"

case "$(uname -m)" in
  x86_64)  ABI=x86_64 ;;
  aarch64) ABI=arm64-v8a ;;
  *) echo "unsupported host arch $(uname -m)" >&2; exit 1 ;;
esac

mkdir -p "$CACHE"
apk="$CACHE/magisk-v30.7.apk"
if ! echo "$MAGISK_SHA256  $apk" | sha256sum -c --status 2>/dev/null; then
  echo "==> downloading Magisk" >&2
  curl -fsSL -o "$apk.part" "$MAGISK_URL"
  echo "$MAGISK_SHA256  $apk.part" | sha256sum -c --status || { echo "Magisk checksum mismatch" >&2; exit 1; }
  mv "$apk.part" "$apk"
fi

dest="$OUT/system/etc/init/magisk"
rm -rf "$OUT"
mkdir -p "$dest"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
unzip -q -o "$apk" "lib/$ABI/*" -d "$tmp"
for so in "$tmp/lib/$ABI"/lib*.so; do
  name="$(basename "$so" .so)"
  install -m 0755 "$so" "$dest/${name#lib}"
done
install -m 0644 "$apk" "$dest/magisk.apk"
# --setup-sbin copies stub.apk to /sbin; magiskd trusts only manager APKs signed
# like it, and without it uninstalls the app as a "signature mismatch".
unzip -q -o "$apk" assets/stub.apk -d "$tmp"
install -m 0644 "$tmp/assets/stub.apk" "$dest/stub.apk"

# Magisk rewrites bootanim.rc when updated from its app; keep the stock one
# next to it so Magisk can restore it.
gzip -9 -n -c "$HERE/bootanim.stock.rc" > "$OUT/system/etc/init/bootanim.rc.gz"
cat "$HERE/bootanim.stock.rc" "$HERE/magisk.rc" > "$OUT/system/etc/init/bootanim.rc"
chmod 0644 "$OUT/system/etc/init/bootanim.rc" "$OUT/system/etc/init/bootanim.rc.gz"
# COPY applies these modes to the existing image directories; keep them stock.
chmod 0755 "$OUT" "$OUT/system" "$OUT/system/etc" "$OUT/system/etc/init" "$dest"
