# Sultan Kernel — ZeroMount edition (Pixel 7 / 7 Pro / 7a — gs201)

A **Sultan** 6.1 kernel for the whole **Pixel 7 generation (Tensor G2 / `gs201`)** —
Pixel 7 (`panther`), Pixel 7 Pro (`cheetah`), Pixel 7a (`lynx`) — with a
kernel-level root-hiding stack that actually lands on Sultan's heavily-modified tree —
**ZeroMount VFS + ReSukiSU + SUSFS**, plus a byte-for-byte stock-looking uname/version
spoof. Built with GCC 14.2 + LTO, packaged as AnyKernel3 (`Image.lz4` + gs201 `dtb`).

> Kernel source: [`kerneltoast/android_kernel_google_tensynos`](https://github.com/kerneltoast/android_kernel_google_tensynos) `@ 16.0.0-sultan` (cloned by the workflow).
> This repo is the **build orchestration** (patch set + CI + helpers) over the vendored `./zeromount`.

---

## Features

- **ZeroMount (VFS root-hiding)** — `CONFIG_ZEROMOUNT`. Hides root/module artifacts at the
  **VFS layer** — not OverlayFS, not bind-mounts, no mount changes. WebUI capability reports
  **VFS** (not OverlayFS). This is the notable part: ZeroMount was thought impossible on
  Sultan's modified tree — here it works.
- **ReSukiSU** — the KernelSU flavor used for root (pin `47167aa7`), with the
  `70_ksu_safety-resukisu` supercall guards.
- **SUSFS (v2.0.0)** — `50_add_susfs` + `51_enhanced_susfs`: mount/path/kstat hiding for
  detection resistance, matched to the ZeroMount base version.
- **Full uname / `/proc/version` spoof** — UTS release pinned to stock `6.1.157-android14-11`
  and the compiler banner spoofed, so `uname` and `/proc/version` read **byte-identical to a
  stock official build**. No "custom kernel" tell.
- **Gesture-nav restore (`61_` force-dir-child)** — a ZeroMount ioctl
  (`ZEROMOUNT_IOC_ADD_DIR_CHILD`) that re-surfaces a **soft-debloated** `/product/overlay`
  child in `readdir` without touching the partition, so PackageManager re-enables gesture
  navigation. Ships as an optional companion module (see Releases).

---

## Requirements

- Device: any **gs201 (Tensor G2)** — Pixel 7 (`panther`), 7 Pro (`cheetah`), or 7a (`lynx`).
  One unified kernel: the `Image` + a generic `gs201` dtb are shared across all three;
  device-specifics stay in each device's own `dtbo`. **Not** Pixel 6-gen (gs101) or
  Pixel 8-gen (`zuma`/`zumapro`).
- Unlocked bootloader + a KernelSU-based root manager (ReSukiSU/KernelSU).
- A recent stock base (loads on stock 6.1.145+; equal-or-newer sublevel at the same KMI).

---

## Install

**Kernel** (AnyKernel3 zip from Releases, or build via Actions):
- ReSukiSU / KernelSU manager → flash the AnyKernel3 zip, **or** `fastboot boot` it first to test.
- Back up `boot` / `vendor_kernel_boot` first. A bad flash → reboot into stock (no bootloop by design).

**Gesture-nav module** (optional — only if your device is soft-debloated the same way):
- **KernelSU / ReSukiSU manager** (this kernel bakes in ReSukiSU, a KernelSU variant) →
  Modules → Install from storage → `gesturenav-module-*.zip` → reboot.
- Standard KernelSU-format module (`service.sh` at late_start). The real dependency is the
  **kernel** — it needs ZeroMount's `61_` ioctl (`/dev/zeromount`), not any particular root
  manager; on a non-ZeroMount kernel it silently no-ops.

---

## Build it yourself

`Actions → Build and Release Sultan Kernels → Run workflow` (branch `zeromount-panther`).
Default `matrix_features` builds the stealth pair (`resukisu-zeromount` + `resukisu-fresh`).
Artifact: `kernel-gs201-resukisu-zeromount` (AnyKernel3 zip).

---

## Credits

Sultan / [kerneltoast](https://github.com/kerneltoast) (base tree) ·
[WildKernels](https://github.com/WildKernels) (Sultan+KSU+SUSFS lineage) ·
ReSukiSU · [simonpunk SUSFS](https://gitlab.com/simonpunk/susfs4ksu) ·
ZeroMount (Enginex0). Orchestration + panther integration in this repo.

---

## Disclaimer

**Your warranty is now void.** Flashing a custom kernel is at **your own risk** — bricks,
data loss, and broken features are possible. Understand what each feature does before you
flash. By flashing, **you** chose to make these changes.
