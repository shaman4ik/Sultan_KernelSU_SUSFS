#!/usr/bin/env bash
# fix-ksu-policyload-seqno.sh — kill ReSukiSU's SELinux "seqno-split" oracle by
# emitting a real, non-zero policyload seqno instead of the hardcoded 0.
#
# ReSukiSU edits the LIVE policydb in apply_kernelsu_rules() (boot) and in
# handle_sepolicy() (runtime ioctl). handle_sepolicy() ends in reset_avc_cache(),
# which calls selinux_status_update_policyload(0) — SETTING the /sys/fs/selinux
# status policyload counter to 0 (last-write-wins). A stock kernel keeps that
# counter monotonic and >=1 after boot. "access changed but policyload==0" is the
# split a Duck-style probe detects.
#
# This helper (mode from ksu-policyload.conf):
#   off      -> NO-OP (stock reset_avc_cache(0)).
#   seqno    -> seqno = selinux_state.policy->latest_granting (B-v1: kills ==0).
#   seqno+1  -> seqno = ++latest_granting (faithful selinux_policy_commit bump).
# It (1) adds a ksu_hidepl_seqno() reader mirroring get_policydb()'s access to the
# live selinux_policy, (2) rewrites the four hardcoded 0 args in reset_avc_cache()
# to that seqno, and (3) makes apply_kernelsu_rules() call reset_avc_cache() after
# it unlocks, so the boot-time edit ALSO carries a plausible seqno and no trailing
# (...,0) policyload write survives anywhere on the boot path.
#
# Idempotent, anchor-based, fail-loud. All edits go on ReSukiSU's kernel/selinux
# source AFTER integration, BEFORE the reject gate.
set -euo pipefail
ROOT="${1:-.}"
CONF="${2:-}"

MODE="off"
if [ -n "$CONF" ] && [ -s "$CONF" ]; then
  MODE="$(grep -vE '^[[:space:]]*(#|$)' "$CONF" | sed -nE 's/^[[:space:]]*mode[[:space:]]*=[[:space:]]*//p' | head -n1 | tr -d '[:space:]')"
  [ -n "$MODE" ] || MODE="off"
fi

case "$MODE" in
  off|"") echo "ksu-policyload: mode=off — NO-OP (stock reset_avc_cache(0))"; exit 0 ;;
  seqno)   SEQEXPR='policy->latest_granting' ;;
  seqno+1) SEQEXPR='++policy->latest_granting' ;;
  *) echo "ksu-policyload: unknown mode '$MODE' (use off|seqno|seqno+1)" >&2; exit 1 ;;
esac

# ReSukiSU's rules.c (has apply_kernelsu_rules + reset_avc_cache), not the kernel's.
RULES="$(find "$ROOT" -type f -name rules.c -path '*selinux*' 2>/dev/null \
         | xargs grep -l 'apply_kernelsu_rules' 2>/dev/null | head -1 || true)"
[ -n "$RULES" ] || { echo "ksu-policyload: rules.c with apply_kernelsu_rules not found (ReSukiSU integrated?)" >&2; exit 1; }

python3 - "$RULES" "$SEQEXPR" "$MODE" <<'PY'
import sys
p, seqexpr, mode = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(p).read()

MARK = "[zeromount hide-policyload]"
if MARK in src:
    print("ksu-policyload: already patched (idempotent) in %s" % p)
    sys.exit(0)

def die(msg):
    sys.exit("ksu-policyload: FATAL — " + msg)

# (1) Define ksu_hidepl_seqno() right after get_policydb()'s closing, before the
#     ksu_rules mutex. Mirrors get_policydb()'s branch selection exactly.
anchor1 = "static DEFINE_MUTEX(ksu_rules);"
if src.count(anchor1) != 1:
    die("expected exactly one '%s' anchor, found %d" % (anchor1, src.count(anchor1)))
helper = (
'/* %s: read the current committed policy seqno so a live policydb edit emits a\n'
' * plausible, non-zero policyload (mirrors selinux_policy_commit). */\n'
'static u32 ksu_hidepl_seqno(void)\n'
'{\n'
'#if defined(KSU_COMPAT_USE_SELINUX_STATE) && defined(SELINUX_POLICY_INSTEAD_SELINUX_SS)\n'
'    struct selinux_policy *policy = selinux_state.policy;\n'
'    return policy ? %s : 0;\n'
'#else\n'
'    return 0;\n'
'#endif\n'
'}\n'
'static void reset_avc_cache(void);\n\n'
) % (MARK, seqexpr)
src = src.replace(anchor1, helper + anchor1, 1)

# (2) apply_kernelsu_rules(): call reset_avc_cache() right after it unlocks, so the
#     boot-time policy edit notifies with a real seqno (last policyload write wins).
anchor2 = (
'    ksu_allow(db, "system_server", KERNEL_SU_DOMAIN, "process", "sigkill");\n'
'    mutex_unlock(&ksu_rules);\n'
'}'
)
if src.count(anchor2) != 1:
    die("apply_kernelsu_rules tail anchor not unique/found (count=%d)" % src.count(anchor2))
repl2 = (
'    ksu_allow(db, "system_server", KERNEL_SU_DOMAIN, "process", "sigkill");\n'
'    mutex_unlock(&ksu_rules);\n'
'\n'
'    /* %s: emit a real policyload for the boot-time edit (no trailing 0). */\n'
'    reset_avc_cache();\n'
'}'
) % MARK
src = src.replace(anchor2, repl2, 1)

# (3) reset_avc_cache(): declare seqno at the top and replace every hardcoded 0.
open_anchor = "static void reset_avc_cache(void)\n{\n"
if src.count(open_anchor) != 1:
    die("reset_avc_cache definition opener not unique/found (count=%d)" % src.count(open_anchor))
src = src.replace(
    open_anchor,
    open_anchor + "    u32 seqno = ksu_hidepl_seqno(); /* %s */\n" % MARK,
    1)

pairs = [
    ("avc_ss_reset(0);",                              "avc_ss_reset(seqno);"),
    ("avc_ss_reset(avc, 0);",                         "avc_ss_reset(avc, seqno);"),
    ("selnl_notify_policyload(0);",                   "selnl_notify_policyload(seqno);"),
    ("selinux_status_update_policyload(0);",          "selinux_status_update_policyload(seqno);"),
    ("selinux_status_update_policyload(&selinux_state, 0);",
     "selinux_status_update_policyload(&selinux_state, seqno);"),
]
counts = {}
for old, new in pairs:
    counts[old] = src.count(old)
    src = src.replace(old, new)

# selnl_notify_policyload(0) appears once per #if branch -> 2; the others once each.
if counts["selnl_notify_policyload(0);"] != 2:
    die("selnl_notify_policyload(0) count=%d (expected 2 — both #if branches)"
        % counts["selnl_notify_policyload(0);"])
for k in ("avc_ss_reset(0);", "selinux_status_update_policyload(0);"):
    if counts[k] != 1: die("%s count=%d (expected 1)" % (k, counts[k]))
for k in ("avc_ss_reset(avc, 0);", "selinux_status_update_policyload(&selinux_state, 0);"):
    if counts[k] != 1: die("%s count=%d (expected 1)" % (k, counts[k]))

# Definitive: no hardcoded-0 policyload/avc-reset write may survive.
import re
for bad in ("avc_ss_reset(0)", "avc_ss_reset(avc, 0)",
            "selnl_notify_policyload(0)",
            "selinux_status_update_policyload(0)",
            "selinux_status_update_policyload(&selinux_state, 0)"):
    if bad in src:
        die("a hardcoded-0 call survived: %s" % bad)

open(p, 'w').write(src)
print("ksu-policyload: OK mode=%s — reset_avc_cache now emits seqno=%s; "
      "apply_kernelsu_rules notifies after unlock (no trailing 0). file=%s"
      % (mode, seqexpr, p))
PY

# Post-check (shell side): marker present, no bare 0-write left.
grep -q 'zeromount hide-policyload' "$RULES" \
  || { echo "ksu-policyload: post-check FAILED (marker missing in $RULES)" >&2; exit 1; }
if grep -qE 'selinux_status_update_policyload\((&selinux_state, )?0\)' "$RULES"; then
  echo "ksu-policyload: post-check FAILED — a selinux_status_update_policyload(...,0) survives:" >&2
  grep -nE 'selinux_status_update_policyload\((&selinux_state, )?0\)' "$RULES" >&2
  exit 1
fi
echo "ksu-policyload: post-check OK ($RULES)"
