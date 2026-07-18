#!/usr/bin/env bash
# zeromount-force-dir-child.sh  ("61_" step, applied right after 60_zeromount)
#
# WHAT / WHY
#   60_zeromount can APPEND virtual children into a real directory's readdir
#   (zeromount_inject_dents_common), but the only code path that populates
#   zeromount_dirs_ht is zeromount_auto_inject_parent(), which begins with:
#
#       if (kern_path(v_path, LOOKUP_FOLLOW, &check) == 0) { path_put; return; }
#
#   i.e. it REFUSES to inject any child whose path already resolves on the real
#   fs ("if it exists, real readdir shows it"). That assumption breaks for a
#   soft-debloated dir: the child resolves by name (ext4 htree lookup is intact)
#   yet its dirent was cut from the linear directory listing, so real readdir
#   does NOT show it. There is no ioctl to force-register such a child.
#
#   This helper adds ZEROMOUNT_IOC_ADD_DIR_CHILD (cmd 12): a direct
#   {dir_path, child_name, d_type} insert into zeromount_dirs_ht — the lower
#   half of auto_inject_parent WITHOUT the kern_path existence guard. Register
#   the REAL child name so PMS's stat/open (by name) still resolves the real
#   inode; inject only restores its visibility in getdents.
#
#   Anchor-based + idempotent (the two target files are generated verbatim by
#   60_, so anchors are exact). Fails loud on a missing anchor. Run AFTER 60_
#   and BEFORE fix-susfs-compat so the base is pristine 60_ output.
set -euo pipefail

ROOT="${1:-.}"
C="$ROOT/fs/zeromount.c"
H="$ROOT/include/linux/zeromount.h"
R="$ROOT/fs/readdir.c"
[ -f "$C" ] || { echo "zeromount-force-dir-child: $C not found (run after 60_)" >&2; exit 1; }
[ -f "$H" ] || { echo "zeromount-force-dir-child: $H not found (run after 60_)" >&2; exit 1; }
[ -f "$R" ] || { echo "zeromount-force-dir-child: $R not found (run after 60_)" >&2; exit 1; }

python3 - "$C" "$H" <<'PY'
import sys
c_path, h_path = sys.argv[1], sys.argv[2]

# ---- include/linux/zeromount.h : add the ioctl command define ----------------
h = open(h_path).read()
h_anchor = '#define ZEROMOUNT_IOC_GET_STATUS _IOR(ZEROMOUNT_IOC_MAGIC, 11, int)\n'
h_add    = ('#define ZEROMOUNT_IOC_ADD_DIR_CHILD '
            '_IOW(ZEROMOUNT_IOC_MAGIC, 12, struct zeromount_ioctl_data)\n')
if 'ZEROMOUNT_IOC_ADD_DIR_CHILD' not in h:
    if h_anchor not in h:
        sys.exit('zeromount-force-dir-child: header anchor (GET_STATUS define) not found')
    h = h.replace(h_anchor, h_anchor + h_add, 1)
    open(h_path, 'w').write(h)
    print('zeromount-force-dir-child: header define added')
else:
    print('zeromount-force-dir-child: header define already present (idempotent)')

# ---- fs/zeromount.c : add handler + switch case ------------------------------
c = open(c_path).read()

# reuse tab indentation exactly as 60_ emits it
FUNC = (
    "static int zeromount_ioctl_add_dir_child(unsigned long arg)\n"
    "{\n"
    "\tstruct zeromount_ioctl_data data;\n"
    "\tstruct zeromount_dir_node *dir_node = NULL, *curr;\n"
    "\tstruct zeromount_child_name *child;\n"
    "\tchar *dir_raw, *dir_path, *child_name;\n"
    "\tunsigned char d_type;\n"
    "\tbool child_exists = false;\n"
    "\tu32 hash;\n"
    "\n"
    "\tif (copy_from_user(&data, (void __user *)arg, sizeof(data)))\n"
    "\t\treturn -EFAULT;\n"
    "\n"
    "\tdir_raw = strndup_user(data.virtual_path, PATH_MAX);\n"
    "\tif (IS_ERR(dir_raw))\n"
    "\t\treturn PTR_ERR(dir_raw);\n"
    "\n"
    "\t/* store the dir path in the SAME normalized form inject compares against */\n"
    "\tdir_path = zeromount_normalize_path(dir_raw);\n"
    "\tkfree(dir_raw);\n"
    "\tif (!dir_path)\n"
    "\t\treturn -ENOMEM;\n"
    "\n"
    "\t/* data.real_path carries the BARE child name (single path component) */\n"
    "\tchild_name = strndup_user(data.real_path, PATH_MAX);\n"
    "\tif (IS_ERR(child_name)) {\n"
    "\t\tkfree(dir_path);\n"
    "\t\treturn PTR_ERR(child_name);\n"
    "\t}\n"
    "\tif (child_name[0] == '\\0' || strchr(child_name, '/')) {\n"
    "\t\tkfree(child_name);\n"
    "\t\tkfree(dir_path);\n"
    "\t\treturn -EINVAL;\n"
    "\t}\n"
    "\n"
    "\t/* mirror auto_inject_parent: DT_DIR (4) or DT_REG (8) */\n"
    "\td_type = (data.flags & ZM_FLAG_IS_DIR) ? 4 : 8;\n"
    "\thash = full_name_hash(NULL, dir_path, strlen(dir_path));\n"
    "\n"
    "\tspin_lock(&zeromount_lock);\n"
    "\n"
    "\thash_for_each_possible(zeromount_dirs_ht, curr, node, hash) {\n"
    "\t\tif (strcmp(curr->dir_path, dir_path) == 0) {\n"
    "\t\t\tdir_node = curr;\n"
    "\t\t\tbreak;\n"
    "\t\t}\n"
    "\t}\n"
    "\n"
    "\tif (!dir_node) {\n"
    "\t\tdir_node = kzalloc(sizeof(*dir_node), GFP_ATOMIC);\n"
    "\t\tif (!dir_node) {\n"
    "\t\t\tspin_unlock(&zeromount_lock);\n"
    "\t\t\tkfree(child_name);\n"
    "\t\t\tkfree(dir_path);\n"
    "\t\t\treturn -ENOMEM;\n"
    "\t\t}\n"
    "\t\tdir_node->dir_path = kstrdup(dir_path, GFP_ATOMIC);\n"
    "\t\tif (!dir_node->dir_path) {\n"
    "\t\t\tkfree(dir_node);\n"
    "\t\t\tspin_unlock(&zeromount_lock);\n"
    "\t\t\tkfree(child_name);\n"
    "\t\t\tkfree(dir_path);\n"
    "\t\t\treturn -ENOMEM;\n"
    "\t\t}\n"
    "\t\tINIT_LIST_HEAD(&dir_node->children_names);\n"
    "\t\thash_add_rcu(zeromount_dirs_ht, &dir_node->node, hash);\n"
    "\t\tatomic_inc(&zeromount_dirs_count);\n"
    "\t}\n"
    "\n"
    "\tlist_for_each_entry(child, &dir_node->children_names, list) {\n"
    "\t\tif (strcmp(child->name, child_name) == 0) {\n"
    "\t\t\tchild_exists = true;\n"
    "\t\t\tbreak;\n"
    "\t\t}\n"
    "\t}\n"
    "\n"
    "\tif (!child_exists) {\n"
    "\t\tchild = kzalloc(sizeof(*child), GFP_ATOMIC);\n"
    "\t\tif (child) {\n"
    "\t\t\tchild->name = kstrdup(child_name, GFP_ATOMIC);\n"
    "\t\t\tchild->d_type = d_type;\n"
    "\t\t\tlist_add_tail_rcu(&child->list,\n"
    "\t\t\t\t\t  &dir_node->children_names);\n"
    "\t\t}\n"
    "\t}\n"
    "\n"
    "\tspin_unlock(&zeromount_lock);\n"
    "\tkfree(child_name);\n"
    "\tkfree(dir_path);\n"
    "\treturn 0;\n"
    "}\n"
    "\n"
)

func_anchor = ("static long zeromount_ioctl(struct file *filp, unsigned int cmd,\n"
               "\t\t\t    unsigned long arg)\n")
case_anchor = ("\tcase ZEROMOUNT_IOC_GET_STATUS:\treturn atomic_read(&zeromount_enabled);\n")
case_add    = ("\tcase ZEROMOUNT_IOC_ADD_DIR_CHILD:\treturn "
               "zeromount_ioctl_add_dir_child(arg);\n")

if 'zeromount_ioctl_add_dir_child' in c:
    print('zeromount-force-dir-child: handler already present (idempotent)')
else:
    if func_anchor not in c:
        sys.exit('zeromount-force-dir-child: function anchor (zeromount_ioctl def) not found')
    if case_anchor not in c:
        sys.exit('zeromount-force-dir-child: switch anchor (GET_STATUS case) not found')
    c = c.replace(func_anchor, FUNC + func_anchor, 1)
    c = c.replace(case_anchor, case_anchor + case_add, 1)
    open(c_path, 'w').write(c)
    print('zeromount-force-dir-child: handler + switch case added')
PY

# =============================================================================
# htree f_pos fix — ext4 htree dirs (e.g. /product/overlay) set
#   f_pos = EXT4_HTREE_EOF_64BIT = 0x7FFFFFFFFFFFFFFF  at end-of-directory.
# That is >= ZEROMOUNT_MAGIC_POS (0x7000000000000000), so:
#   - inject_dents_common read v_index = f_pos - MAGIC_POS ~= 0x0FFF...FFFF and
#     the "skip already-emitted" loop skipped EVERY virtual child; and
#   - the 3 getdents wrappers took `goto skip_real_iterate` on it.
# Small/linear dirs have a tiny EOF f_pos (< MAGIC_POS) so they were unaffected;
# htree dirs failed every time -> injected children never appeared.
#
# Fix: bound our virtual pagination to [MAGIC_POS, MAGIC_POS + MAX_VIRTUAL) and
# treat the ext4 htree EOF sentinel (and any linear/small EOF < MAGIC_POS) as
# "real iterate finished -> start at child 0". A stray htree hash from a
# buffer-full mid-iterate (>= MAGIC_POS, not the EOF sentinel, not in our
# window) is left alone so the real iterate resumes -> no lost real entries.
# =============================================================================
python3 - "$C" "$H" "$R" <<'PY'
import sys
c_path, h_path, r_path = sys.argv[1], sys.argv[2], sys.argv[3]

# ---- include/linux/zeromount.h : constants (line-based, ws-agnostic anchor) --
h = open(h_path).read()
if 'ZEROMOUNT_HTREE_EOF64' not in h:
    lines = h.splitlines(keepends=True)
    out, done = [], False
    for ln in lines:
        out.append(ln)
        if not done and 'define ZEROMOUNT_MAGIC_POS' in ln:
            out.append('#define ZEROMOUNT_MAX_VIRTUAL\t65536ULL /* max injected children per dir (pagination window) */\n')
            out.append('#define ZEROMOUNT_HTREE_EOF64\t0x7fffffffffffffffULL /* ext4 EXT4_HTREE_EOF_64BIT */\n')
            done = True
    if not done:
        sys.exit('zeromount-force-dir-child(htree): header anchor (MAGIC_POS define) not found')
    open(h_path, 'w').write(''.join(out))
    print('zeromount-force-dir-child(htree): header constants added')
else:
    print('zeromount-force-dir-child(htree): header constants already present (idempotent)')

# ---- fs/zeromount.c : v_index disambiguation + reset condition ---------------
c = open(c_path).read()

OLD_VINDEX = ("\tif (*pos >= ZEROMOUNT_MAGIC_POS) {\n"
              "\t\tv_index = *pos - ZEROMOUNT_MAGIC_POS;\n"
              "\t} else {\n"
              "\t\tv_index = 0;\n"
              "\t}\n")
NEW_VINDEX = ("\tif (*pos < ZEROMOUNT_MAGIC_POS || *pos == ZEROMOUNT_HTREE_EOF64) {\n"
              "\t\t/* real iterate just finished: linear/small EOF (< MAGIC_POS)\n"
              "\t\t * or ext4 htree EOF sentinel (0x7FFF..., which is >= MAGIC_POS\n"
              "\t\t * and was misread as a huge v_index) -> start at child 0 */\n"
              "\t\tv_index = 0;\n"
              "\t} else if (*pos < ZEROMOUNT_MAGIC_POS + ZEROMOUNT_MAX_VIRTUAL) {\n"
              "\t\tv_index = *pos - ZEROMOUNT_MAGIC_POS;\n"
              "\t} else {\n"
              "\t\t/* an ext4 htree hash from a buffer-full mid-iterate: do NOT\n"
              "\t\t * inject; let the real iterate resume next getdents call */\n"
              "\t\t__putname(page_buf);\n"
              "\t\treturn;\n"
              "\t}\n")

OLD_RESET = ("\t\t\tif (*pos < ZEROMOUNT_MAGIC_POS)\n"
             "\t\t\t\t*pos = ZEROMOUNT_MAGIC_POS;\n")
NEW_RESET = ("\t\t\tif (*pos < ZEROMOUNT_MAGIC_POS ||\n"
             "\t\t\t    *pos == ZEROMOUNT_HTREE_EOF64)\n"
             "\t\t\t\t*pos = ZEROMOUNT_MAGIC_POS;\n")

if 'ZEROMOUNT_HTREE_EOF64' in c:
    print('zeromount-force-dir-child(htree): zeromount.c already fixed (idempotent)')
else:
    if OLD_VINDEX not in c:
        sys.exit('zeromount-force-dir-child(htree): v_index block anchor not found in zeromount.c')
    if OLD_RESET not in c:
        sys.exit('zeromount-force-dir-child(htree): reset-pos anchor not found in zeromount.c')
    c = c.replace(OLD_VINDEX, NEW_VINDEX, 1)
    c = c.replace(OLD_RESET, NEW_RESET, 1)
    open(c_path, 'w').write(c)
    print('zeromount-force-dir-child(htree): zeromount.c inject fix applied')

# ---- fs/readdir.c : bound the 3 identical skip_real_iterate guards -----------
r = open(r_path).read()
OLD_GUARD = ("\tif (f.file->f_pos >= ZEROMOUNT_MAGIC_POS) {\n"
             "\t\terror = 0;\n"
             "\t\tgoto skip_real_iterate;\n"
             "\t}\n")
NEW_GUARD = ("\tif (f.file->f_pos >= ZEROMOUNT_MAGIC_POS &&\n"
             "\t    f.file->f_pos < ZEROMOUNT_MAGIC_POS + ZEROMOUNT_MAX_VIRTUAL) {\n"
             "\t\terror = 0;\n"
             "\t\tgoto skip_real_iterate;\n"
             "\t}\n")
n = r.count(OLD_GUARD)
if 'ZEROMOUNT_MAGIC_POS + ZEROMOUNT_MAX_VIRTUAL' in r:
    print('zeromount-force-dir-child(htree): readdir.c guards already bounded (idempotent)')
elif n == 3:
    r = r.replace(OLD_GUARD, NEW_GUARD)
    open(r_path, 'w').write(r)
    print('zeromount-force-dir-child(htree): readdir.c 3 guards bounded')
else:
    sys.exit('zeromount-force-dir-child(htree): expected 3 skip_real_iterate guards in readdir.c, found %d' % n)
PY

# ---- verify ------------------------------------------------------------------
grep -q 'zeromount_ioctl_add_dir_child' "$C" \
  || { echo "zeromount-force-dir-child: post-check FAILED (handler missing in $C)" >&2; exit 1; }
grep -q 'ZEROMOUNT_IOC_ADD_DIR_CHILD' "$H" \
  || { echo "zeromount-force-dir-child: post-check FAILED (define missing in $H)" >&2; exit 1; }
grep -q 'ZEROMOUNT_HTREE_EOF64' "$C" \
  || { echo "zeromount-force-dir-child: post-check FAILED (htree fix missing in $C)" >&2; exit 1; }
grep -q 'ZEROMOUNT_MAGIC_POS + ZEROMOUNT_MAX_VIRTUAL' "$R" \
  || { echo "zeromount-force-dir-child: post-check FAILED (guard bound missing in $R)" >&2; exit 1; }
echo "zeromount-force-dir-child: OK"
