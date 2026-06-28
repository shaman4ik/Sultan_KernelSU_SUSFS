# Vendored ZeroMount / ReSukiSU patch set

Vendored per CLAUDE.md Runbook v2, Stage 1.1. After this point the runbook
reads **only** from `./zeromount/`.

## Source

| Field | Value |
|-------|-------|
| Source repo | `shaman4ik/Super-Builders` |
| Source commit | `7ea5c4399cf0150e768e5b6b901aab454e66e98e` |
| Source path | `android14-6.1/` (ReSukiSU patches + shared defconfig/build-helpers) |
| Last functional change | `cffc854 fix(zeromount): guard against ERR_PTR filename in stat hook` |
| Vendored on | 2026-06-28 |

All files verified byte-identical to source (sha256).

## Layout vs runbook expectation

The runbook v1 text assumed "3 patches + defconfig.fragment + build-helpers"
inside a `ReSukiSU/` dir. Real layout differs:

- Patches live in `Super-Builders/android14-6.1/ReSukiSU/patches/` — **4** patches,
  not 3 (a separate `50_add_susfs` base **plus** `51_enhanced_susfs`).
- `defconfig.fragment` and `build-helpers/` live one level up at `android14-6.1/`
  (shared across KSU variants), not inside `ReSukiSU/`.
- `resukisu-pin.txt` (= `47167aa7`) also lives at `android14-6.1/`.

Mapped into this repo as:

```
zeromount/
  patches/
    50_add_susfs_in_gki-android14-6.1.patch   # simonpunk susfs base, SUSFS_VERSION v2.0.0
    51_enhanced_susfs-android14-6.1.patch      # Enginex0 enhancements, layered on v2.0.0
    60_zeromount-android14-6.1.patch           # ZeroMount VFS subsystem (CONFIG_ZEROMOUNT)
    70_ksu_safety-resukisu-6.1.patch           # ReSukiSU supercall safety guards
    _archive/
      65_zeromount-adb-filter-android14-6.1.patch   # optional, NOT in apply chain
  defconfig.fragment                            # CONFIG_KSU + susfs + zram + KPM + ZeroMount
  build-helpers/                                # assemble-defconfig, fix-susfs-compat, etc.
  resukisu-pin.txt                              # 47167aa7
  VENDOR.md
```

## CHECKPOINT 1 — SUSFS version finding (critical)

- `50_add_susfs` and `51_enhanced_susfs` both carry `#define SUSFS_VERSION "v2.0.0"`.
  → The Enginex0 `50_`/`51_` matched set is based on **simonpunk susfs v2.0.0**.
- The current tree (per CLAUDE.md recon) carries **simonpunk susfs v2.1.0**
  (gitlab pin `ef16cbce`, via TheWildJames patches).
- **Mismatch: v2.0.0 (vendored set) vs v2.1.0 (tree).** `60_zeromount` is tightly
  coupled to the susfs inode-flag / AS_FLAGS bit layout from its matching `50_/51_`,
  so mixing `60_` onto the tree's v2.1.0 susfs is the risk the runbook warns about.
  This feeds the Stage 1.2 keep-vs-replace decision (CHECKPOINT 2).

## Notes

- `_archive/65_zeromount-adb-filter` is kept for reference but is **not** part of
  the documented apply chain (`50_ → 51_ → 70_ → 60_`).
- `build-helpers/fix-susfs-compat.sh` mostly targets 5.10/5.15 sublevels; it is
  idempotent and safe to run on android14-6.1 but may be a no-op here.
