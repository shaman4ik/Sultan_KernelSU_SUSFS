#!/usr/bin/env bash
# native-157.sh — native, fully-consistent 6.1.157 (uname -a, /proc/version,
# osrelease, vermagic) WITHOUT touching LINUX_VERSION_CODE.
#
# LINUX_VERSION_CODE comes from VERSION/PATCHLEVEL/SUBLEVEL (filechk_version.h) —
# we leave SUBLEVEL as-is, so every "#if LINUX_VERSION_CODE" gate keeps seeing the
# native version and mali/wlan/etc compile unchanged (no shims).
#
# UTS_RELEASE comes from KERNELRELEASE = include/config/kernel.release, produced by
# the Makefile's filechk_kernel.release. We OVERRIDE that recipe to emit the stock
# string. Rather than match the tree's exact recipe text (it varies), we APPEND a
# fresh `override define filechk_kernel.release` at EOF: GNU make honors the LAST
# (override) definition, so ours wins regardless of the original's shape.
set -euo pipefail

ROOT="${1:-.}"
MK="$ROOT/Makefile"
STOCK_RELEASE="6.1.157-android14-11-gbd23337e42e7-ab14791245"
[ -f "$MK" ] || { echo "native-157: $MK not found (run in kernel tree root)" >&2; exit 1; }

echo "native-157: kernel.release machinery in Makefile —"
grep -nE 'filechk_kernel\.release|kernel\.release|KERNELRELEASE' "$MK" | head -20 || true

if grep -q 'native-157: UTS_RELEASE override' "$MK"; then
  echo "native-157: override already appended (idempotent)"
elif grep -q 'filechk_kernel\.release' "$MK"; then
  {
    printf '\n# native-157: UTS_RELEASE override (SUBLEVEL/LINUX_VERSION_CODE untouched).\n'
    printf '# GNU make honors the LAST (override) definition, so this wins over the\n'
    printf '# original recipe whatever its exact text. Sets include/config/kernel.release\n'
    printf '# -> UTS_RELEASE -> uname(2)/proc-version/osrelease/vermagic to the stock string.\n'
    printf 'override define filechk_kernel.release\n'
    printf '\techo "%s"\n' "$STOCK_RELEASE"
    printf 'endef\n'
  } >> "$MK"
  echo "native-157: appended override filechk_kernel.release -> $STOCK_RELEASE"
else
  echo "native-157: ERROR filechk_kernel.release absent — kernel.release generated another way." >&2
  echo "native-157: machinery dump for adaptation:" >&2
  grep -nE 'kernel\.release|KERNELRELEASE|UTS_RELEASE|utsrelease' "$MK" >&2 || true
  exit 1
fi

echo "native-157: SUBLEVEL untouched: $(grep -E '^SUBLEVEL =' "$MK" || echo '(no SUBLEVEL line?)')"
grep -q 'native-157: UTS_RELEASE override' "$MK" \
  || { echo "native-157: post-check FAILED (override marker missing)" >&2; exit 1; }
echo "native-157: OK (UTS_RELEASE = $STOCK_RELEASE; version gates see native SUBLEVEL)"
