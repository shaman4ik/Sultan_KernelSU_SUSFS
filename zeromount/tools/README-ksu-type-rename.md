# ksu_file sepolicy stealth (cut / rename)

**Active mode: `cut`** (`zeromount/ksu-sepolicy.conf` → `mode=cut`). The build
comments out the 3 `KERNEL_SU_FILE` rule-injection lines in
`apply_kernelsu_rules()`, so the `ksu_file` type is never added and there is no
`allow ALL ksu_file ALL ALL`. Both oracle halves die (`u:object_r:ksu_file:s0` →
EINVAL, no untrusted_app allow) and nothing shows up under "list custom types".
**No ZeroMount `zm` coordination is needed** — `zm`'s hard-coded `ksu_file` stays
a dormant string; it only matters if the (currently unused) ext4/overlay storage
path runs, and ZeroMount then degrades to bare-fallback, not a crash. Cut removes
ZeroMount's storage-redirect *capability*; switch to `rename` (below) only if a
future module needs storage-backed mounts.

The `rename` mode below is the fallback for that case — it keeps ksu_file working
under a neutral name but requires the coordinated `zm` binary-patch.

---

# ksu_file sepolicy rename — coordinated kernel ↔ ZeroMount (fallback mode)

`ksu_file` is a SELinux type ReSukiSU injects into the loaded policy at boot
(`apply_kernelsu_rules()` in `kernel/selinux/rules.c`, from
`#define KERNEL_SU_FILE "ksu_file"` in `kernel/selinux/selinux.h`). It gives a
Duck/LSPosed detection oracle:
- **validity half:** `u:object_r:ksu_file:s0` written to `/proc/self/attr/current`
  is a *valid* context on a KSU kernel (non-EINVAL) but EINVAL on stock;
- **access half:** `allow ALL ksu_file ALL ALL` → `untrusted_app` can read a
  `ksu_file`-labelled file.

It is **NOT vestigial**: ZeroMount labels its ext4-loopback storage with
`u:object_r:ksu_file:s0` (via the `zm`/`zeromount` binary), and the broad `allow`
is what lets every app domain read the redirected files. In pure-VFS mode the
path is dormant (no labelled files), but a storage-backed mount (or a VFS→ext4
fallback) makes `zm` run `mkfs.ext4` and apply the label.

## Therefore: rename must be SYNCHRONOUS on both sides

1. **Kernel (this repo):** `build-helpers/fix-ksu-sepolicy-stealth.sh` renames
   `KERNEL_SU_FILE` to the 8-char name in `zeromount/ksu-type-name.txt`.
2. **ZeroMount userspace (Enginex0's blob — YOU do this):** binary-patch the same
   name into `zm` and `arm64-v8a/zeromount`.

A kernel-only rename **silently breaks** ZeroMount storage-fallback (EINVAL on the
label) the first time a storage mount happens.

## Binary-patch recipe (equal length → offsets stay put)

`ksu_file` is 8 bytes; the replacement is 8 bytes, so the ELF layout is unchanged.
Back up first, then (replace `NEWNAME8` with your chosen 8-char name):

```sh
cp zm zm.bak; cp zeromount zeromount.bak
for f in zm zeromount; do
  LANG=C perl -0777 -pi -e 's/\Qu:object_r:ksu_file:s0\E/u:object_r:NEWNAME8:s0/g' "$f"
  # if `strings "$f" | grep -w ksu_file` also shows a BARE token, patch it too:
  LANG=C perl -0777 -pi -e 's/\Qksu_file\E/NEWNAME8/g' "$f"
done
# verify: no ksu_file left, new name present
for f in zm zeromount; do echo "== $f =="; strings "$f" | grep -E 'object_r:|NEWNAME8|ksu_file' || true; done
```

Flash the patched module together with the renamed kernel. Re-patch after every
ZeroMount module update (the upstream blob re-introduces `ksu_file`).

## Honest limits

- **Access half only dies for the LITERAL name.** The `allow` stays (redirect
  needs app read access), now on the renamed type. A detector that *guesses* the
  new 8-char name still gets `allowed`. That is why the name should not be a
  community-known constant. Fully killing it is impossible without breaking
  ZeroMount's app-visible redirect.
- **Narrow (optional, risky):** tightening `ksu_allow(ALL, …)` to fewer source
  domains closes the allow-all hole, but `untrusted_app` (and most app domains)
  MUST stay or the redirect becomes invisible to those apps. Do it only with
  on-device testing under a real storage-mount.
- **seqno-split is separate.** The SELinux verdict also flags runtime policydb
  modification (apply_kernelsu_rules bumps the policy seqno at load). Rename does
  not touch that — it is a deeper layer (bake rules into the base policy vs inject
  at load, which ReSukiSU does not support out of the box).
