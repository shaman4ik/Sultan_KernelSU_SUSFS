# Integration spec — извлечено из upstream `Enginex0/Super-Builders@main`

Рецепт (НЕ копия workflow) для вживления ReSukiSU + susfs v2.0.0 + ZeroMount в
Sultan/gs201-workflow. Источник: `.github/workflows/kernel-a14-6.1.yml` (диспетчер)
→ reusable **`build-resukisu.yml`**. Дата извлечения: 2026-06-28.

> ⚠️ Upstream собирает **generic GKI** (AOSP `repo` + Kleaf/bazel + AOSP clang, LTO=thin).
> У нас gs201 = GCC 14.2.0 + `make gs201_defconfig`. **Build/toolchain-шаги НЕ вживляем** —
> берём только шаги 6–13: KSU setup → патчи → fix-susfs-compat → assemble-defconfig.

---

## `.github/workflows/` upstream (список)
```
kernel-a12-5.10.yml  kernel-a12-5.4.yml  kernel-a13-5.10.yml  kernel-a13-5.15.yml
kernel-a14-5.15.yml  kernel-a14-6.1.yml  <-- entry (a14/6.1)   kernel-a15-6.6.yml
kernel-a16-6.12.yml  kernel-custom.yml   main.yml   cache-dependencies.yml
build-resukisu.yml  <-- reusable (рецепт тут)       build-ksu-next.yml  build-wksu.yml
build-sukisu.yml    build-bbk-{resukisu,ksu-next,sukisu,wksu}.yml
build-samsung-{resukisu,ksu-next,sukisu,wksu}.yml    samsung-m14-reference.yml
dry-test-patches.yml  dry-test-bbk-patches.yml  dry-test-samsung-patches.yml
```

---

## Порядок наложения патчей (ответ на CP3)
Все в `$KERNEL_ROOT/common`, **кроме `70_`** — он в `$KSU_DIR` (= `KernelSU/`, дир ReSukiSU).
Отдельными шагами, без dry-run; реджекты собираются артефактом после сборки.

| # | патч | команда | где |
|---|------|---------|-----|
| 1 | `50_add_susfs_in_gki-android14-6.1.patch` | `patch -p1 -F3 --no-backup-if-mismatch` | `common/` |
| 2 | `51_enhanced_susfs-android14-6.1.patch` | `patch -p1 -F3 --no-backup-if-mismatch` | `common/` |
| 3 | `70_ksu_safety-resukisu-6.1.patch` | `patch -p1 --no-backup-if-mismatch` (БЕЗ `-F3`), guarded `[ -s "$PATCH" ]` | **`$KSU_DIR`** |
| 4 | `60_zeromount-android14-6.1.patch` | `patch -p1 -F3 --no-backup-if-mismatch` | `common/` |
| 5 | `fix-susfs-compat.sh` | пост-обработка (sed/python, идемпотент) | `common/` |

**Итог: 50 → 51 → 70 → 60 → fix-susfs-compat** — совпадает с CP3 рунбука.
Дельты к нашему плану:
- `50/51/60` идут с **`-F3`** (fuzz 3) + `--no-backup-if-mismatch`; `70` — без fuzz.
- **`70_` накладывается ВНУТРИ дира ReSukiSU**, не в `common/` → на CP3 надо `cd` в KSU-дир для `70_`.
- Dry-run нет; реджекты терпят на этапе patch и сканируют потом. Под наш строгий CP3
  («`.rej` пусто») добавляем явный гейт `find . -name '*.rej'`.

---

## ReSukiSU / KSU integration
```bash
curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s susfs-ksud
# → создаёт $KERNEL_ROOT/KernelSU ; фатально проверить, что дир появился
PIN="${sukisu_commit:-$(cat $VERSION_DIR/resukisu-pin.txt)}"   # наш пин = 47167aa7
[ -n "$PIN" ] && (cd KernelSU && git fetch origin && git checkout "$PIN")
```
- **Ветка для setup.sh = `susfs-ksud`** (несёт susfs inline hook) — это и есть пропуск
  `<branch>` в §1.2 рунбука.
- `KSU_DIR=KernelSU`. Пин из `resukisu-pin.txt` (`47167aa7`), переопределяем входом.
- Пост-setup массаж в `common/drivers/kernelsu/supercalls.c`:
  `sed -i '/ksu_mark_running_process/d'` + инъекция `#include <linux/vmalloc.h>` после строки 1,
  если `vzalloc` используется без хедера. (Часть «ReSukiSU supercall guards» — остальное в `70_`.)

---

## `fix-susfs-compat.sh` — аргументы (подтверждено)
```
fix-susfs-compat.sh <kernel_common_dir> <sublevel> <android_ver> <kernel_ver> <kernel_patches_dir>
# вызов из common/:  bash "$FIX" . "$SUBLEVEL" "$ANDROID_VER" "$KERNEL_VER" "$KERNEL_PATCHES"
```
- `<sublevel>` берётся РЕАЛЬНЫЙ из `common/Makefile` (`SUBLEVEL =`), не из matrix-инпута. 5-й арг зарезервирован.
- Это **НЕ инструмент даунгрейда susfs**. Чинит только компиляцию от дрейфа саблевела
  (наличие хелперов, порядок label/decl): show_pad в `task_mmu.c`; `fdinfo.c`
  (`inotify_mark_user_mask`→`mark->mask`, старый `u32 mask`, `;` после label);
  `susfs.c` (`i_uid_into_mnt`→`i_uid.val`); дубль `ksu_handle_setresuid` для 6.8+.
- **Раскладку `AS_FLAGS`/inode-битов v2.0.0↔v2.1.0 он НЕ примиряет** → `BUILD_BUG_ON`-риски
  остаются. Безопасность даунгрейда даёт сам матч-сет v2.0.0 (`50_/51_/60_`), а не этот хелпер.
- Для gs201 @ sublevel **145**: Fix2–5 скорее no-op (хелперы есть), Fix6 N/A (это 6.8+).
  Реально может сработать только Fix1 (show_pad).

---

## `assemble-defconfig.sh` — аргументы + слияние фрагмента
```
assemble-defconfig.sh <FRAGMENT_SRC> <FRAGMENT_DST> <DEFCONFIG> [--susfs --overlayfs --zram --kpm --kleaf]
```
- Фрагмент **секционирован тегами**: `# [base]`, `# [susfs]`, `# [overlayfs]`, `# [zram]`, `# [kpm]`.
  `awk` тащит `base` всегда + включённые секции; дедуп по ключу CONFIG (last-wins).
- `--kleaf` добавляется когда НЕТ `build/build.sh` (bazel-путь, фрагмент отдельным файлом).
  Legacy `make`-путь — фрагмент **дописывается прямо в `gki_defconfig`**.
- После assemble: автопрюнинг неизвестных `CONFIG_KSU_*`/`CONFIG_KSU_SUSFS_*` (grep по `Kconfig*`+sed),
  затем `bypass-abi-check.sh . "$ANDROID_VER" "$KERNEL_VER"`. (Автопрюнинг спасает при swap KSU-варианта.)

**Для gs201:** `DEFCONFIG = arch/arm64/configs/gs201_defconfig`, путь **legacy (не kleaf)** —
фрагмент дописывается в `gs201_defconfig`. На CP4 проверить, что **`CONFIG_ZEROMOUNT=y`** долетел.

---

## Прочие хелперы (по порядку в reusable)
`fix-old-kernel-compat.sh "$KERNEL_ROOT/common" "$SUBLEVEL"` (||true) перед патчами;
`apply-kernel-patches.sh . "$KERNEL_VER" "$KERNEL_PATCHES"` (ptrace/perf);
`clean-build-flags.sh . "$KERNEL_VER" "ReSukiSU"` и module-version-bypass sed —
**toolchain-adjacent (clang/Kleaf)**, под GCC/`make` пересмотреть/возможно не нужны;
`setup-bbg.sh`/ZRAM — по инпутам, нам не обязательны.

---

## Что это даёт нашим чекпоинтам
- **CP3:** порядок `50→51→70→60` подтверждён; `70_` — в KSU-дире; `50/51/60` с `-F3`; добавить `.rej`-гейт.
- **§1.2:** ветка ReSukiSU `setup.sh` = **`susfs-ksud`**.
- **CP4:** `assemble-defconfig.sh src dst gs201_defconfig --susfs --overlayfs --zram --kpm` (без `--kleaf`),
  проверить `CONFIG_ZEROMOUNT=y`.
- **CP1.0 подтверждено повторно:** отдельного v2.1.0-матч-сета в android14-6.1 нет → остаёмся на **v2.0.0-Replace**.
- `fix-susfs-compat` даунгрейд НЕ упрощает (только компайл-фиксы саблевела) — Replace остаётся единственным верным путём.
