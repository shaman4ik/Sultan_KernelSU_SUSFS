# CHECKPOINT 5 — интегрированная сборка (Stage 1 Replace) — GREEN ✅

**Дата:** 2026-06-28
**Ветка сборки:** `zeromount-panther` @ `6569327`
**Run:** `28308917647` (workflow_dispatch, gs201, feature `resukisu-zeromount`) → **success**
**Стек:** ReSukiSU `47167aa7` (`susfs-ksud`) + simonpunk susfs **v2.0.0** (`50_/51_`) + **ZeroMount** (`60_`)

---

## Критерий зелёного CP5 — все 4 условия выполнены

| # | условие | результат |
|---|---------|-----------|
| 1 | компиляция + упаковка | ✅ `Build the Kernel` success (~19 мин, LTO-линк ок); `Image.lz4` + gs201 `dtb` → **`gs201-a16-resukisu-zeromount-anykernel3.zip`** (артефакт `kernel-gs201-resukisu-zeromount`, **19 652 314 B ≈ 19.65 MB**, sha256 `62ae9d86eecefc37691dd1623e54e055960ad8612b8f51423233dd1e25cfe704`, retention 90 дней) |
| 2 | символы выжили в `out/.config` | ✅ см. греп ниже |
| 3 | строгий `.rej`-гейт | ✅ не сработал — интеграционный шаг прошёл; `Collect .rej → found=false`; zip/upload .rej **skipped** |
| 4 | `trigger-release` | ✅ **SKIPPED** (publish=false → ни релиза, ни тега) |

### CP4-греп по сгенерированному `out/.config` (твой watch по автопрюнингу — снят)
```
5936:CONFIG_KSU=y
5946:CONFIG_KSU_SUSFS=y
5950:CONFIG_KSU_SUSFS_SPOOF_UNAME=y
6189:CONFIG_ZEROMOUNT=y
```
Оба критичных символа реальны (не скомпилены в ноль): `CONFIG_ZEROMOUNT=y` и
`CONFIG_KSU_SUSFS_SPOOF_UNAME=y` пережили assemble и резолв Kconfig.

---

## Ход прогона (шаги)

| шаг | итог |
|-----|------|
| Checkout orchestration (vendored ./zeromount) | ✅ |
| GCC 14.2.0 toolchain | ✅ |
| Clone AnyKernel3 (`sultan-gs201`) + kernel `-b 16.0.0-sultan` | ✅ |
| **Integrate ReSukiSU + apply 50→newuname-fix→51→70→supercalls-sed→60 + fix-susfs-compat + reject-gate** | ✅ **за ~5 c, 0 .rej** |
| Assemble defconfig (`--susfs --overlayfs` + явный `CONFIG_ZEROMOUNT=y`) | ✅ |
| Build the Kernel | ✅ (~19 мин) |
| CP4 verify on `out/.config` | ✅ (греп выше) |
| Copy Images / ZIP / Upload | ✅ |
| trigger-release | **skipped** |

**Ключевое:** сосуществование susfs (`50_/51_`) ↔ ReSukiSU-inline-hook (`susfs-ksud`) —
главный подозреваемый на линковке, который локальный CP3 показать не мог — **проблем не дало**:
`vmlinux` слинковался, дублей символов/Kconfig-конфликтов нет. Хуки комплементарны.

---

## Что зафиксировано в `sultan.yml` (zeromount-panther, коммит `6569327`)
- matrix → `["resukisu-zeromount"]`; `actions/checkout` репо в `orchestration/` для вендорного `./zeromount/`.
- Убраны клоны `susfs4ksu`/`kernel_patches`; ядро запинено `-b 16.0.0-sultan` (drift guard).
- ReSukiSU: `setup.sh susfs-ksud` → `git checkout 47167aa7` (fatal-check `KernelSU/`).
- Порядок apply: `50 → fix-tensynos-newuname.sh → 51 → 70 (в KSU dir) → ksu_mark_running_process-sed → 60`;
  `-F3` на 50/51/60, plain на 70; sed ПОСЛЕ 70_ (sed-first реджектит 70_ Hunk#1). libperfmgr-массаж убран.
- Строгий reject-gate (`exit 1` на любой `.rej`).
- defconfig через `assemble-defconfig.sh --susfs --overlayfs` + явный `CONFIG_ZEROMOUNT=y` (в фрагменте его нет).
- Новый helper `zeromount/build-helpers/fix-tensynos-newuname.sh` (anchor-based, идемпотентный, fails loud).

---

## Остаётся — проверка на устройстве (человек)
Замыкает хуки на panther (gs201):
1. Бэкап `boot`/`init_boot`/`vbmeta`. **Сначала `fastboot boot`**, не `flash`. Бутлуп → ребут в сток.
2. `uname -r` реально спуфится; `/dev/zeromount` присутствует; в WebUI ZeroMount **capability = VFS** (не OverlayFS-фолбэк);
   радио/Wi-Fi/датчики/термал живы; mountinfo чистый для не-root.
3. Несколько чистых ребутов — только потом писать в раздел.

> ⚠️ На Pixel 7/7Pro известен спонтанный ребут при подключении USB — device-баг линейки, НЕ от наших патчей.

## Откат
- Прошиваемый фоллбэк: официальный **WildKernels/Sultan gs201 A16** релиз (`fastboot flash` стоковых `boot`/`init_boot`/`vbmeta`).
- Откат кода: вернуться на чистый baseline-коммит `af9cb77`.

---

**Итог:** Stage 1 (Replace) собран и валиден в CI — загружаемое gs201/panther-ядро с
ReSukiSU + susfs v2.0.0 + ZeroMount, оба критичных конфига реальны. Тег не ставился (эксперимент).
Дальше — устройство.
