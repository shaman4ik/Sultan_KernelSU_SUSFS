# Status — stock gs201 GREEN + zeromount-panther + CP3

**Дата:** 2026-06-28 · **Durable-ветка:** `claude/vendoring-runbook-o9gdxi`

---

## ✅ Stock gs201 — GREEN (пайплайн форка валиден)

Run `28307765937` (`70df930`) — **success**. Прошёл весь путь, который валидировали:

| шаг | итог |
|---|---|
| GCC 14.2.0 toolchain | ✅ |
| Build the Kernel | ✅ (~19 мин компиляции) |
| Copy Images → Create ZIP (AnyKernel3) | ✅ |
| Upload artifact | ✅ `kernel-gs201-stock` (19.4 MB, sha256 `4d833df6…`) |
| KSU/SUSFS/Networking/TCP шаги | skipped (фича `stock` — патчей нет) |
| Collect .rej | ✅ нашёл 0 → zip/upload .rej **skipped** (чисто) |
| **trigger-release** | **SKIPPED** ✅ — guard сработал (`publish=false` → ни релиза, ни тега) |

**Вывод:** toolchain → compile → dtb → AnyKernel3-упаковка исправны. Любой провал
на CP5 теперь = наши патчи, не CI. Флэш-фоллбэк = официальный WildKernels/Sultan-релиз;
code-rollback = `af9cb77`.

---

## ✅ `zeromount-panther` создан от `af9cb77`

Запушен. Чистый срез: **не содержит** stock-matrix-правку (`70df930`),
`sultan.yml` matrix = исходный `["stock", "wksu-susfs"]`, на борту вендорный `./zeromount/`.
`git diff af9cb77..zeromount-panther` будет чистой дельтой интеграции.

---

## ✅ CP3 — наложение 50→51→70→60 (детали: `docs/checkpoints/CHECKPOINT3.md`, `da4b4ac`)

Локальная репро: tensynos@16.0.0-sultan (6.1.145) + ReSukiSU@47167aa7.

| патч | итог |
|---|---|
| `50_` | 1 `.rej` (`kernel/sys.c` newuname-спуф — кастом tensynos) → ручная правка (2× `#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME`). `fs/open.c` **чисто** (массаж libperfmgr для v2.0.0 НЕ нужен). 1 benign fuzz (task_mmu.c). |
| `51_` | чисто |
| `70_` | чисто (в дире ReSukiSU) |
| `60_` | 0 `.rej`, 3 benign fuzz (gki_defconfig нерелевантен gs201; stat.c/statfs.c — zeromount-хуки легли верно) |

**После ручной правки newuname — `.rej` по всему дереву = 0** (критерий CP3 рунбука выполнен).
`fix-susfs-compat @145` ≈ no-op (только show_pad). 25 файлов изменено.

**Caveat:** `setup.sh` ReSukiSU (интеграция KSU в дерево) локально не гонялся — git-клон
вне scope; tensynos уже несёт нативные KSU-хуки, риск низкий; финальное подтверждение —
интегрированная сборка на CP5.

---

## Следующий шаг (Stage 1 на `zeromount-panther`, перед CP5)

Вживить рецепт в `sultan.yml`:
- ReSukiSU (пин `47167aa7`, ветка setup.sh `susfs-ksud`);
- apply `50/51/60` с `-F3` в корне + `70` без fuzz в дире ReSukiSU;
- **newuname-фикс шагом после `50_`** (tensynos-специфичный, см. диф в CHECKPOINT3.md);
- убрать libperfmgr-массаж (для v2.0.0 не нужен);
- CP4: `CONFIG_ZEROMOUNT=y` в `gs201_defconfig` через `defconfig.fragment`/assemble-defconfig.

CP3 — «главный чекпоинт по смыслу» → **стоп**: ждём «go» на правку workflow `zeromount-panther`.
