#!/usr/bin/env bash
# native-compiler.sh — override LINUX_COMPILER (the compiler substring shown in
# /proc/version) to the stock string, WITHOUT switching the real toolchain.
#
# scripts/mkcompile_h emits `#define LINUX_COMPILER "<cc>, <ld>"` into
# include/generated/compile.h; init/version.c bakes it into linux_banner ->
# /proc/version. A detector reads only that string, never the real codegen, so we
# keep compiling with GCC (no BOLT/PGO/LTO of a real Clang that could break custom
# patches) and just print the stock Clang banner.
#
# tensynos' mkcompile_h writes compile.h via a heredoc, so the define is a raw
# line `#define LINUX_COMPILER "${CC_VERSION}, ${LD_VERSION}"` (not echo/printf).
# We replace the quoted VALUE on that line with the stock literal — form-agnostic
# across heredoc and echo styles. The literal is inlined (not a shell var) so it
# works whether the heredoc is quoted or unquoted. The idempotency/gate marker is
# a shell comment at the top of the script (NOT inside the heredoc — that would
# leak into compile.h).
#
# Stock literal = first non-comment, non-blank line of $2 (stock-compiler.txt).
# Absent/empty/placeholder ("…"/"TODO") -> NO-OP (banner stays native GCC).
set -euo pipefail
ROOT="${1:-.}"
STOCK_FILE="${2:-}"
MKC="$ROOT/scripts/mkcompile_h"
[ -f "$MKC" ] || { echo "native-compiler: $MKC not found" >&2; exit 1; }

if [ -z "$STOCK_FILE" ] || [ ! -s "$STOCK_FILE" ]; then
  echo "native-compiler: no stock-compiler file — NO-OP (LINUX_COMPILER stays native GCC)"; exit 0
fi
STOCK="$(grep -vE '^[[:space:]]*(#|$)' "$STOCK_FILE" | head -n1 | sed -e 's/[[:space:]]*$//')"
case "${STOCK:-}" in
  ""|*…*|*TODO*)
    echo "native-compiler: stock-compiler.txt is a placeholder/empty — NO-OP"; exit 0;;
  *\"*|*\`*|*\$*)
    echo "native-compiler: stock string contains \" \` or \$ — unsupported, aborting" >&2; exit 1;;
esac

if grep -q 'native-compiler: LINUX_COMPILER override applied' "$MKC"; then
  echo "native-compiler: already patched (idempotent)"; exit 0
fi

python3 - "$MKC" "$STOCK" <<'PY'
import sys, re
mkc, stock = sys.argv[1], sys.argv[2]
lines = open(mkc).read().splitlines(keepends=True)

idx = next((i for i,l in enumerate(lines) if '#define LINUX_COMPILER' in l), None)
if idx is None:
    sys.stderr.write("native-compiler: no '#define LINUX_COMPILER' line found. dump:\n")
    for i,l in enumerate(lines):
        if 'LINUX_COMPILER' in l or 'CC_VERSION' in l or 'LD_VERSION' in l:
            sys.stderr.write("  %d: %s" % (i, l))
    sys.exit(1)

line = lines[idx]
if '\\"' in line:                       # echo-style escaped quotes: \"...\"
    new, n = re.subn(r'\\"[^"]*\\"', '\\"' + stock + '\\"', line, count=1)
else:                                   # heredoc-style real quotes: "..."
    new, n = re.subn(r'"[^"]*"', '"' + stock + '"', line, count=1)
if n != 1:
    sys.exit("native-compiler: could not locate the quoted value on the LINUX_COMPILER line: %r" % line)
lines[idx] = new

marker = "# native-compiler: LINUX_COMPILER override applied (stock banner, GCC codegen kept)\n"
lines.insert(1 if (lines and lines[0].startswith('#!')) else 0, marker)
open(mkc, 'w').write(''.join(lines))
print("native-compiler: patched mkcompile_h LINUX_COMPILER -> " + stock)
PY

grep -q 'native-compiler: LINUX_COMPILER override applied' "$MKC" \
  || { echo "native-compiler: post-check FAILED (marker missing)" >&2; exit 1; }
grep -qF "$STOCK" "$MKC" \
  || { echo "native-compiler: post-check FAILED (stock string not in mkcompile_h)" >&2; exit 1; }
echo "native-compiler: OK"
