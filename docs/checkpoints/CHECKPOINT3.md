# CHECKPOINT 3 — наложение патчей 50→51→70→60 (Replace, ReSukiSU + susfs v2.0.0)

**Дата:** 2026-06-28 · **Ветка отчётов:** durable (`claude/vendoring-runbook-o9gdxi`)
Результат CP3 ляжет в `sultan.yml` на `zeromount-panther` (Replace).

---

## Метод (локальная репро)
- Дерево ядра: `kerneltoast/android_kernel_google_tensynos @ 16.0.0-sultan`
  (tar.gz через общий HTTPS-прокси — git-клон вне scope даёт 403), **6.1.145**,
  есть `gs201_defconfig`. git-init как baseline (`ec85942`) для чистого apply/reset.
- ReSukiSU: `ReSukiSU @ 47167aa7` (tar.gz, пин из `resukisu-pin.txt`).
- Патчи: вендорные `./zeromount/patches/`. Флаги — из INTEGRATION-SPEC:
  `50/51/60` → `patch -p1 -F3 --no-backup-if-mismatch` (в корне дерева);
  `70` → `patch -p1 --no-backup-if-mismatch` (БЕЗ `-F3`, **в дире ReSukiSU**).

> ⚠️ **Caveat:** `setup.sh` ReSukiSU (интеграция KSU В дерево ядра) локально не
> прогонялся — его внутренний `git clone` блокируется scope. `50/51/60` проверены
> против tensynos-дерева, которое **уже несёт нативные KSU-хуки** (`ksu_handle_stat`,
> `__ksu_is_allow_uid_for_current`, `ksu_handle_setresuid`), поэтому риск, что
> интеграция KSU сдвинет результаты susfs/zeromount-патчей, низкий. `70_` проверен
> против standalone ReSukiSU@47167aa7. Полное интегрированное подтверждение — на CP5.

---

## Результат по патчам (порядок 50 → 51 → 70 → 60)

| патч | где | итог | детали |
|------|-----|------|--------|
| `50_add_susfs` | дерево | **1 .rej + 1 fuzz** | `kernel/sys.c` Hunk#3 (newuname-спуф) FAILED → ручная правка ниже. `fs/proc/task_mmu.c` Hunk#2 fuzz1 (benign). Остальные 23 файла — чисто (только offsets). **`fs/open.c` — чисто** (массаж libperfmgr НЕ нужен, в отличие от v2.1.0-пути). |
| `51_enhanced_susfs` | дерево | **чисто** | exit 0, без fuzz/.rej. |
| `70_ksu_safety-resukisu` | **ReSukiSU dir** | **чисто** | dry-run + apply exit 0, без .rej. Оба хунка легли: `#if defined(KSU_TP_HOOK) && defined(CONFIG_KSU_SUSFS)` (L368), `CMD_SUSFS_ADD_SUS_KSTAT_REDIRECT` (L1078). |
| `60_zeromount` | дерево | **3 fuzz, 0 .rej** | `gki_defconfig` Hunk#1 fuzz3 (нерелевантно gs201), `fs/stat.c` Hunk#3 fuzz2 (benign — `zeromount_stat_hook` лёг верно), `fs/statfs.c` Hunk#1 fuzz2 (benign — `#include <linux/zeromount.h>`). |

**Итог: после ручной правки newuname — `.rej` по всему дереву = 0.**
Все fuzz-хиты вручную проверены — susfs/zeromount-код лёг в корректные места.

---

## Единственная ручная правка: `kernel/sys.c` newuname-спуф

`50_` ждёт ванильный `newuname`; у tensynos он кастомный (`struct task_struct *t;
bool is_gms;` + gms/rcu-блок) → Hunk#3 реджект. Ручная вставка (форма v2.0.0 —
простой вызов без `static_branch_likely`):

```diff
@@ override_release ... newuname @@
 	return ret;
 }
 
+#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
+extern void susfs_spoof_uname(struct new_utsname* tmp);
+#endif
 SYSCALL_DEFINE1(newuname, struct new_utsname __user *, name)
 {
 	struct new_utsname tmp;
 	struct task_struct *t;          // tensynos-кастом сохранён
 	bool is_gms = false;
 
 	down_read(&uts_sem);
 	memcpy(&tmp, utsname(), sizeof(tmp));
+#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
+	susfs_spoof_uname(&tmp);
+#endif
 	up_read(&uts_sem);
 	... gms-логика tensynos не тронута ...
```
(Хунки #1/#2 `50_` в `kernel/sys.c` — `ksu_handle_setresuid` — легли чисто сами.)

**→ В Stage-1 workflow:** эту правку нужно нести как шаг ПОСЛЕ `50_` (sed или
маленький supplementary-патч `71_tensynos_newuname-gs201.patch`), т.к. она
tensynos-специфична и `fix-susfs-compat` её НЕ делает.

---

## `fix-susfs-compat.sh . 145 android14 6.1` (пост-патч)
Практически no-op на 6.1.145: единственное действие —
`marking show_pad: as maybe-unused in task_mmu.c` (Fix1). Остальное не требуется
(`inotify_mark_user_mask`/`i_user_ns` присутствуют; `setuid_hook.c` отсутствует —
6.8+-фикс N/A). Подтверждает спеку.

---

## `git diff --stat` (дерево ядра, 50+51+60+ручная+fixcompat)
```
 25 files changed, 1367 insertions(+), 3 deletions(-)
 fs/namei.c        236 +  fs/namespace.c    201 +  fs/readdir.c      183 +
 fs/stat.c         142 +  fs/proc/task_mmu  102 +  fs/proc/base.c     59 +
 fs/open.c          58 +  fs/proc/fd.c       50 +  fs/notify/fdinfo   53 +
 fs/Kconfig         37 +  fs/proc_namespace  35 +  kernel/kallsyms    32 +
 ... kernel/sys.c   13 +  arch/.../gki_defconfig 1 + ...
```

---

## Выводы / TODO для Stage 1 (zeromount-panther)
1. **Apply-флаги:** `50/51/60` с `-F3` в корне; `70` без fuzz в дире ReSukiSU.
2. **newuname:** добавить tensynos-фикс как шаг после `50_` (см. диф выше).
3. **fs/open.c:** массаж libperfmgr из старого workflow **убрать** — для v2.0.0 не нужен.
4. **ReSukiSU:** пин `47167aa7`, ветка setup.sh `susfs-ksud`; setup.sh тянется с
   main (movable) → рассмотреть пин и его (residual-риск дрейфа).
5. **CP4:** `CONFIG_ZEROMOUNT` лёг только в `gki_defconfig`, НЕ в `gs201_defconfig` →
   на CP4 завести его в `gs201_defconfig` через `defconfig.fragment`/assemble-defconfig.
6. **0 .rej** — формальный критерий CP3 рунбука выполнен (после ручной newuname-правки).

---

## Приложение — верификация перед CP5 (по запросу ревью)

### A. newuname — один когерентный путь спуфа
- В `kernel/sys.c` ровно **2** упоминания `susfs_spoof_uname`: `extern` декл (внутри
  `#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME`) + один вызов. **Дубля нет.**
- Важно: чистое дерево `kerneltoast/...tensynos@16.0.0-sultan` НЕ несёт собственного
  `susfs_spoof_uname` в `newuname` (проверено на свежем клоне до патчей). Формулировка
  старого рунбука «у kerneltoast уже вставлен» относилась к stray-`sys.c` прошлой сессии,
  не к чистому дереву. Наша вставка — единственная.
- Гейт: и декл, и вызов — под `#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME`.
- Родная логика tensynos цела: вызов спуфа стоит между `memcpy(utsname())` и `up_read`;
  ниже без изменений `struct task_struct *t; bool is_gms`, `for_each_thread`+`rcu`,
  и `if (is_gms) snprintf(tmp.release,…,LINUX_VERSION…)`.
- Взаимодействие: для app `id.gms.unstable` tensynos НАМЕРЕННО перезаписывает `tmp.release`
  реальной версией ПОСЛЕ спуфа (его штатное поведение для Play Integrity) — мы это не трогали.
  Для всех остальных uid susfs-спуф остаётся в силе. Конфликта нет.
- (libperfmgr-массаж — это `fs/open.c`, к `newuname` отношения не имеет; его удаление
  на эту функцию не влияет.)

### B. Гейт-конфиг долетит =y (формально CP4, но смысл правки A)
- `zeromount/defconfig.fragment` секция `# [susfs]` содержит `CONFIG_KSU_SUSFS_SPOOF_UNAME=y`.
- **CP4-действие:** `assemble-defconfig.sh … gs201_defconfig --susfs` тянет секцию `[susfs]`
  в `gs201_defconfig` → символ долетает `=y`, `#ifdef` компилит спуф РЕАЛЬНО (не в ноль).
  Проверить на CP4 grep'ом по итоговому `gs201_defconfig`.

### C. 60_ zeromount-VFS-хуки сели ВНУТРЬ нужных функций (не «patch success с fuzz»)
- `fs/stat.c`: `zeromount_stat_hook(dfd,filename,stat,…)` — внутри `vfs_statx`
  (резолвер по filename+dfd), после KSU-блока `orig_flow:`, под `#ifdef CONFIG_ZEROMOUNT`,
  ранний возврат при `zm_ret != -ENOENT`. ✓
- `fs/statfs.c`: `zeromount_spoof_statfs(pathname, st)` — внутри `user_statfs()`,
  ПОСЛЕ `vfs_statfs(&path, st)` (постобработка результата). ✓
- `fs/d_path.c`: `zeromount_get_static_vpath(d_backing_inode(path->dentry))` — внутри
  настоящего `d_path()`. ✓
- Fuzz был только context-offset; семантическое размещение верное.
