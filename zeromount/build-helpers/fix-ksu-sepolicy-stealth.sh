#!/usr/bin/env bash
# fix-ksu-sepolicy-stealth.sh — remove (or rename) ReSukiSU's SELinux type
# "ksu_file" to kill the Duck/LSPosed detection oracle.
#
# ksu_file is injected into the loaded policy at boot by apply_kernelsu_rules()
# (kernel/selinux/rules.c), from #define KERNEL_SU_FILE "ksu_file" in
# kernel/selinux/selinux.h. Oracle: validity of u:object_r:ksu_file:s0 +
# allow ALL ksu_file ALL ALL (untrusted_app read). ZeroMount uses it to label its
# ext4-loopback storage — but that path is dormant in pure-VFS mode, and degrades
# to bare-fallback if ever needed, so CUT is safe here.
#
# Mode comes from $2 (ksu-sepolicy.conf), line `mode=...`:
#   keep            -> NO-OP (default; ksu_file stays)
#   cut             -> comment out the 3 KERNEL_SU_FILE rule-injection lines in
#                      rules.c: no type is added, no allow -> both oracle halves
#                      die, and nothing shows up under "list custom types".
#   rename:<8char>  -> rename the type instead (needs a matching binary-patch of
#                      the ZeroMount zm blob; see tools/README-ksu-type-rename.md).
set -euo pipefail
ROOT="${1:-.}"
CONF="${2:-}"

MODE="keep"
if [ -n "$CONF" ] && [ -s "$CONF" ]; then
  MODE="$(grep -vE '^[[:space:]]*(#|$)' "$CONF" | sed -nE 's/^[[:space:]]*mode[[:space:]]*=[[:space:]]*//p' | head -n1 | tr -d '[:space:]')"
  [ -n "$MODE" ] || MODE="keep"
fi

case "$MODE" in
  keep|"") echo "ksu-sepolicy: mode=keep — NO-OP (ksu_file unchanged)"; exit 0 ;;
esac

# Locate ReSukiSU's selinux files (not the kernel's own security/selinux).
RULES="$(find "$ROOT" -type f -name rules.c -path '*selinux*' 2>/dev/null \
         | xargs grep -l 'KERNEL_SU_FILE' 2>/dev/null | head -1 || true)"
[ -n "$RULES" ] || { echo "ksu-sepolicy: rules.c with KERNEL_SU_FILE not found (ReSukiSU integrated?)" >&2; exit 1; }

if [ "$MODE" = "cut" ]; then
  # (a) rules.c: comment the 3 KERNEL_SU_FILE rule-injection lines (no type, no allow).
  BEFORE="$(grep -c 'KERNEL_SU_FILE' "$RULES" || true)"
  python3 - "$RULES" <<'PY'
import sys
p = sys.argv[1]
out, changed = [], 0
for ln in open(p):
    if 'KERNEL_SU_FILE' in ln and 'zeromount cut ksu_file' not in ln:
        indent = ln[:len(ln) - len(ln.lstrip())]
        out.append(indent + '// [zeromount cut ksu_file] ' + ln.lstrip())
        changed += 1
    else:
        out.append(ln)
open(p, 'w').write(''.join(out))
print("ksu-sepolicy: commented %d KERNEL_SU_FILE line(s) in %s" % (changed, p))
PY
  if grep -nE 'KERNEL_SU_FILE' "$RULES" | grep -vqE 'zeromount cut ksu_file'; then
    echo "ksu-sepolicy: FAILED — an active KERNEL_SU_FILE line survives:" >&2
    grep -nE 'KERNEL_SU_FILE' "$RULES" | grep -vE 'zeromount cut ksu_file' >&2
    exit 1
  fi

  # (b) selinux.c: comment the KSU_FILE_CONTEXT block in cache_sid() (the failing
  # secctx_to_secid + its if/else logging), KEEPING the global `u32 ksu_file_sid = 0;`
  # declaration (guard var, no consumer). Removes the last macro expansion so the
  # "ksu_file" string leaves vmlinux and no dmesg line is emitted.
  SELC="$(find "$ROOT" -type f -name selinux.c -path '*selinux*' 2>/dev/null \
          | xargs grep -l 'KSU_FILE_CONTEXT' 2>/dev/null | head -1 || true)"
  if [ -n "$SELC" ]; then
    python3 - "$SELC" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).readlines()
start = next((i for i,l in enumerate(lines)
             if 'security_secctx_to_secid(KSU_FILE_CONTEXT' in l
             and 'zeromount cut ksu_file' not in l), None)
if start is None:
    if any('KSU_FILE_CONTEXT' in l and 'zeromount cut ksu_file' not in l for l in lines):
        sys.exit("ksu-sepolicy: KSU_FILE_CONTEXT present in %s but cache_sid anchor not found — structure changed" % p)
    print("ksu-sepolicy: no active KSU_FILE_CONTEXT block in %s (already cut or absent)" % p)
    sys.exit(0)
# Comment from the call line until the brace balance opened by `if (err) {`
# returns to 0 (the closing } of the else), covering wrapped call + if/else.
bal, seen_brace, end = 0, False, start
for i in range(start, len(lines)):
    bal += lines[i].count('{') - lines[i].count('}')
    if '{' in lines[i]:
        seen_brace = True
    end = i
    if seen_brace and bal == 0:
        break
n = 0
for i in range(start, end + 1):
    indent = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
    lines[i] = indent + '// [zeromount cut ksu_file] ' + lines[i].lstrip()
    n += 1
open(p, 'w').write(''.join(lines))
print("ksu-sepolicy: commented %d-line KSU_FILE_CONTEXT block in %s (kept global ksu_file_sid=0)" % (n, p))
PY
    if grep -nE 'KSU_FILE_CONTEXT' "$SELC" | grep -vqE 'zeromount cut ksu_file'; then
      echo "ksu-sepolicy: FAILED — active KSU_FILE_CONTEXT survives in $SELC:" >&2
      grep -nE 'KSU_FILE_CONTEXT' "$SELC" | grep -vE 'zeromount cut ksu_file' >&2
      exit 1
    fi
  else
    echo "ksu-sepolicy: note — selinux.c with KSU_FILE_CONTEXT not found; rules.c cut alone still kills the oracle"
  fi

  echo "ksu-sepolicy: OK cut — $BEFORE KERNEL_SU_FILE line(s) + KSU_FILE_CONTEXT cache block neutralized (no type, no allow, no cached sid)"
  exit 0
fi

# rename:<8char> mode (kept for completeness; requires zm binary-patch in lockstep)
NAME="${MODE#rename:}"
if [ "$NAME" = "$MODE" ] || [ -z "$NAME" ]; then
  echo "ksu-sepolicy: unknown mode '$MODE' (use keep|cut|rename:<8char>)" >&2; exit 1
fi
if ! printf '%s' "$NAME" | grep -qE '^[a-z][a-z0-9_]{7}$'; then
  echo "ksu-sepolicy: rename name '$NAME' invalid — need exactly 8 chars ^[a-z][a-z0-9_]{7}$" >&2; exit 1
fi
case "$NAME" in *ksu*|*su*|*root*) echo "ksu-sepolicy: name '$NAME' contains ksu/su/root — rejected" >&2; exit 1;; esac
SH="$(find "$ROOT" -type f -name selinux.h -path '*selinux*' 2>/dev/null | xargs grep -l 'KERNEL_SU_FILE' 2>/dev/null | head -1 || true)"
[ -n "$SH" ] || { echo "ksu-sepolicy: selinux.h with KERNEL_SU_FILE not found" >&2; exit 1; }
if grep -q '#define KERNEL_SU_FILE "ksu_file"' "$SH"; then
  sed -i "s/#define KERNEL_SU_FILE \"ksu_file\"/#define KERNEL_SU_FILE \"$NAME\"/" "$SH"
fi
grep -q "\"$NAME\"" "$SH" || { echo "ksu-sepolicy: rename post-check failed" >&2; exit 1; }
echo "ksu-sepolicy: OK rename -> $NAME (remember to binary-patch zm to the SAME name)"
