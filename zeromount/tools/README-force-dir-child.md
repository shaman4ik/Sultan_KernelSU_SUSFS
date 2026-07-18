# ZeroMount force-dir-child (`61_` step)

Restores a **soft-debloated** dirent to `readdir` without editing the partition
image, without any overlay mount, and without changing the filesystem type.

## The problem it solves

A "soft debloat" removes a directory entry from `/product/overlay`'s *linear*
listing but leaves the file on disk — ext4 htree lookup still resolves it, so
`stat`/`open`/`ls <that dir>` work, yet the entry is absent from `ls
/product/overlay`. PackageManagerService walks the directory with `getdents`,
never sees the entry, and the overlay is effectively disabled (e.g. an empty
Navigation section in Settings when `NavigationBarModeGestural` is cut).

ZeroMount's `zeromount_inject_dents_common` can *append* a synthetic dirent to a
real directory's `getdents` output. But the only registrar,
`zeromount_auto_inject_parent`, bails whenever the path already resolves on the
real fs (`kern_path(...) == 0 → return`) — which is exactly the soft-debloat
case. So there was no way to force it. That is why a plain userspace module
never surfaced the child.

## What `61_` adds

A new ioctl **`ZEROMOUNT_IOC_ADD_DIR_CHILD`** (`_IOW(0x5A, 12, struct
zeromount_ioctl_data)`) that inserts `{dir_path, child_name, d_type}` straight
into `zeromount_dirs_ht` — the tail of `auto_inject_parent` **without** the
`kern_path` existence guard. Injected as an anchor-based, idempotent source edit
right after `60_zeromount` (see `build-helpers/zeromount-force-dir-child.sh`).

`struct zeromount_ioctl_data` is reused as-is:
- `virtual_path` → the **directory** (canonical path PMS enumerates)
- `real_path`   → the **bare child name** (a single component, no `/`)
- `flags`       → `ZM_FLAG_IS_DIR (1<<7)` for a directory child, else a regular file

## Usage on device (human)

1. Cross-compile `zeromount_addchild.c` for arm64 (NDK), push it, run as root:
   ```
   ./zeromount_addchild /product/overlay NavigationBarModeGestural --dir
   ```
2. Register the **canonical** path PMS reads (`/product/overlay`, not
   `/system/product/...`) and the **real** child name — resolution by name must
   land on the real inode.
3. Register **before** PMS scans (boot). Drop `service.sh.example` into a
   KernelSU/Magisk module as `service.sh` (runs late_start; the tool binary
   next to it). Adjust the child list as needed.

## Notes / limits

- Fixes **only** readdir visibility. The file is already present; this is purely
  complementary to the soft-debloat.
- Injection is skipped for umounted/uid-blocked contexts
  (`zeromount_should_skip`). `system_server` (PMS) is not umounted, so it sees
  the injected child.
- `d_ino` in the synthetic dirent is a ZeroMount-generated placeholder; it is
  irrelevant to PMS, which resolves the real inode on `open`.
- To clear everything, use `ZEROMOUNT_IOC_CLEAR_ALL` (existing).
