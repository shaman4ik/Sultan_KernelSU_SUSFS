#!/bin/bash
# fix-tensynos-newuname.sh — gs201/tensynos-specific resolution for the 50_ susfs
# newuname-spoof hunk (Hunk#3), which rejects against kerneltoast's custom newuname
# (struct task_struct *t; bool is_gms; + gms/rcu block). See docs/checkpoints/CHECKPOINT3.md.
#
# Inserts the two CONFIG_KSU_SUSFS_SPOOF_UNAME blocks (extern decl + spoof call between
# memcpy(utsname()) and up_read) without touching the native is_gms logic.
# Anchor-based (offset-immune) and idempotent; fails LOUD if the expected shape is absent.
#
# Usage: fix-tensynos-newuname.sh <path/to/kernel/sys.c>
set -euo pipefail
F="${1:?usage: fix-tensynos-newuname.sh <path/to/sys.c>}"
[ -f "$F" ] || { echo "fix-tensynos-newuname: $F not found" >&2; exit 1; }

if grep -q 'susfs_spoof_uname(&tmp)' "$F"; then
  echo "fix-tensynos-newuname: spoof already present in $F — nothing to do"
  exit 0
fi

python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()

anchor = 'SYSCALL_DEFINE1(newuname, struct new_utsname __user *, name)\n{'
decl = ('#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n'
        'extern void susfs_spoof_uname(struct new_utsname* tmp);\n'
        '#endif\n')
assert s.count(anchor) == 1, "newuname anchor not found/unique"
s = s.replace(anchor, decl + anchor, 1)

old = ('\tdown_read(&uts_sem);\n'
       '\tmemcpy(&tmp, utsname(), sizeof(tmp));\n'
       '\tup_read(&uts_sem);\n\n'
       '\trcu_read_lock();')
new = ('\tdown_read(&uts_sem);\n'
       '\tmemcpy(&tmp, utsname(), sizeof(tmp));\n'
       '#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME\n'
       '\tsusfs_spoof_uname(&tmp);\n'
       '#endif\n'
       '\tup_read(&uts_sem);\n\n'
       '\trcu_read_lock();')
assert s.count(old) == 1, "newuname body anchor (down_read..rcu_read_lock) not found/unique"
s = s.replace(old, new, 1)

open(p, 'w').write(s)
print("fix-tensynos-newuname: inserted susfs_spoof_uname into newuname")
PY
