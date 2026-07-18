#!/usr/bin/env bash
# fix-resukisu-selinux-export.sh — satisfy fresh ReSukiSU's static_export_check.mk
# (the "selinux_hide" build guard added after pin 47167aa7).
#
# The check greps for specific `static` SELinux declarations and ERRORS if they are
# still static — ReSukiSU needs them non-static (globally linkable) to reference
# them. For linux 6.1 with `struct selinux_state` present (tensynos), only ONE
# check is enforced: sel_handle_status_ops in security/selinux/selinuxfs.c. The
# write_op check passes trivially (that exact static array form is absent), and the
# selinux_state-absent block + the <4.2 / >=6.6 blocks are all skipped on 6.1.
#
# This de-statics only what the check enforces, guarded + idempotent. If the tree
# ever changes shape (e.g. selinux_state removed), add the extra de-statics then.
set -euo pipefail

ROOT="${1:-.}"
SFS="$ROOT/security/selinux/selinuxfs.c"
[ -f "$SFS" ] || { echo "fix-resukisu-selinux-export: $SFS not found" >&2; exit 1; }

changed=0

# Required on 6.1: sel_handle_status_ops must not be static.
if grep -q '^static const struct file_operations sel_handle_status_ops' "$SFS"; then
  sed -i 's/^static const struct file_operations sel_handle_status_ops/const struct file_operations sel_handle_status_ops/' "$SFS"
  echo "de-static: sel_handle_status_ops (selinuxfs.c)"
  changed=1
fi

# Only present on some trees; de-static if the exact static array form exists.
if grep -qF 'static ssize_t (*write_op[])' "$SFS"; then
  sed -i 's/static ssize_t (\*write_op\[\])/ssize_t (*write_op[])/' "$SFS"
  echo "de-static: write_op (selinuxfs.c)"
  changed=1
fi

# Verify the enforced symbol is no longer static.
if grep -q '^static const struct file_operations sel_handle_status_ops' "$SFS"; then
  echo "fix-resukisu-selinux-export: FAILED — sel_handle_status_ops still static" >&2
  exit 1
fi

[ "$changed" -eq 1 ] && echo "fix-resukisu-selinux-export: OK" \
  || echo "fix-resukisu-selinux-export: nothing to change (already de-static'd)"
