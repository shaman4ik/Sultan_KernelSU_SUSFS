# Runbook v3: panther (Pixel 7) — gs201 + ReSukiSU + SUSFS + ZeroMount

Лежит в КОРНЕ форка `shaman4ik/Sultan_KernelSU_SUSFS` (build-orchestration; ядро
`kerneltoast/android_kernel_google_tensynos` @ `16.0.0-sultan` клонируется workflow'ом).
Цель — **ZeroMount (VFS) + ReSukiSU + совместимый SUSFS** на **Pixel 7 (panther, gs201)**.
Прошивку и тест делает человек, не ты.

> Версия v3: учтены результаты CHECKPOINT 1 (вендоринг сделан) и решение CHECKPOINT 2 (**Replace**).
> Стек дерева — KernelSU-Next + simonpunk susfs **v2.1.0**; вендор-сет ZeroMount — на susfs **v2.0.0**.

---

## Факты recon (зафиксировано)

| Роль | Значение |
|------|----------|
| Рабочее дерево (этот репо) | `shaman4ik/Sultan_KernelSU_SUSFS` |
| Исходник ядра | `kerneltoast/android_kernel_google_tensynos` @ `16.0.0-sultan`, клонируется в workflow |
| Dispatch | `.github/workflows/build-kernel-release.yml` → reusable `sultan.yml`; таргеты **gs201**/zuma/zumapro |
| Сборка gs201 | codename `gs201`, android14, 6.1, **GCC 14.2.0**, `make gs201_defconfig`, AnyKernel3 (`Image.lz4` + `gs201` dtb) |
| KSU сейчас | **KernelSU-Next** (пин `293ca016…`) → меняем на **ReSukiSU** |
| SUSFS сейчас | **simonpunk v2.1.0** (пин `ef16cbce`) + патчи `TheWildJames/kernel_patches` (`50_add_susfs…` + `ksun-…-susfs-v2.1.0`) |
| defconfig | `arch/arm64/configs/gs201_defconfig` (внутри клонируемого дерева) |
| ZeroMount | отсутствует в дереве; принесён вендорингом (см. ниже) |

---

## Вендоринг — СДЕЛАНО (CHECKPOINT 1)

Скопировано из `shaman4ik/Super-Builders @ 7ea5c43` (путь `android14-6.1/`), sha256 сверены, в `./zeromount/`:
```
zeromount/
  patches/
    50_add_susfs_in_gki-android14-6.1.patch   # simonpunk база (v2.0.0)
    51_enhanced_susfs-android14-6.1.patch      # Enginex0 enhancements (v2.0.0)
    60_zeromount-android14-6.1.patch           # ZeroMount VFS, CONFIG_ZEROMOUNT
    70_ksu_safety-resukisu-6.1.patch           # ReSukiSU supercall guards
    _archive/65_…adb-filter…patch              # опционально, НЕ в цепочке
  defconfig.fragment
  build-helpers/                               # assemble-defconfig, fix-susfs-compat, report-config
  resukisu-pin.txt   -> 47167aa7
  VENDOR.md
```
> Расхождение с v1/v2 рунбука: патчей **4** (отдельные `50_add_susfs` + `51_enhanced_susfs`), а не «один `50_`».
> `defconfig.fragment` и `build-helpers/` — общие (с уровня `android14-6.1/`), не из `ReSukiSU/`.

---

## РЕШЕНИЯ ЗАФИКСИРОВАНЫ (CHECKPOINT 2)

- **SUSFS = REPLACE.** Вендор-сет (`50_`+`51_`+`60_`) построен на susfs **v2.0.0**; дерево несёт **v2.1.0**.
  `60_zeromount` жёстко завязан на раскладку `AS_FLAGS`/inode-битов своей базы → класть `60_` поверх
  v2.1.0 нельзя (BUILD_BUG_ON или тихая порча). Поэтому susfs дерева (v2.1.0 + патчи TheWildJames)
  **заменяем** на вендор-базу v2.0.0. «Keep» отвергнут.
- **KSU = swap KernelSU-Next → ReSukiSU** (пин `47167aa7`). `70_ksu_safety` есть только под ReSukiSU.
- Обе правки — деструктивные для стека дерева → только на ветке эксперимента, поверх чистого baseline (Стадия 0).

---

## Принципы

1. Минимальный диф к device-части: `gs201_defconfig`, GCC 14.2.0, dtb, AnyKernel3 c device-check panther — НЕ трогать без нужды.
2. Собирать из gs201-дерева, не из generic GKI.
3. `60_` ↔ susfs из `50_/51_` — одна версия (v2.0.0). В этом весь смысл Replace.
4. Саблевел: грузиться на стоке 6.1.145; равный-или-старший при той же KMI ок, насильно не даунгрейдить.
5. Только **gs201/panther**, не zuma.
6. Стадийность: сперва рабочий фоллбэк, потом эксперимент.

## Правила (строго)

1. НИКОГДА не флашить / `fastboot flash` / `fastboot boot`. Только сборка/упаковка.
2. На каждом CHECKPOINT — стоп, вывод артефакта/лога, ждать человека.
3. Стадия 0 — чистая ветка/тег; Стадия 1 — `zeromount-panther` поверх неё.
4. Фазз/`.rej` ≠ успех. Стоп и репорт.
5. Про железо panther не «додумывать».

---

## СТАДИЯ 0 — чистый baseline (фоллбэк, сделать ДО Replace)

1. Откатить мусор uname-спуфа: `sys.c`, `sys.c.rej`, `sys.c_fix.patch` (коммит `2cd9bc7`).
   У kerneltoast `newuname()` кастомный, ручной `susfs_spoof_uname(&tmp)` уже вставлен → `sys.c_fix.patch`
   **выкинуть**, проверив корректность ручного спуфа.
2. Чистое состояние (`git status` чистый, нет `.rej`).
3. Собрать **gs201/panther** существующим workflow (фича `wksu-susfs`), без изменений стека.
4. Зафиксировать baseline как тег/ветку — это фоллбэк, от него ответвляем Стадию 1.

**STOP — CHECKPOINT 0.** Вывести: что откатил (diff), `git status`, статус сборки, имя/состав `AnyKernel3*.zip`.

---

## СТАДИЯ 1 — ZeroMount + ReSukiSU (ветка `zeromount-panther` от baseline)

### 1.0 Проверка апстрима ПЕРЕД даунгрейдом (CHECKPOINT 1.0)
Вендор-сет на v2.0.0. ZeroMount в активной бете — проверить **upstream `Enginex0/Super-Builders`**
(свежий commit/ветка): нет ли уже **v2.1.0-матч-сета** (`50_/51_/60_` на susfs v2.1.0).
- Есть → ре-вендорить его в `./zeromount/` (новейший susfs + родная база ZeroMount, БЕЗ даунгрейда).
- Нет → идём на Replace с v2.0.0 как решено.

**STOP — CHECKPOINT 1.0.** Вывести: есть ли v2.1.0-сет в апстриме (ссылка/commit) и вывод —
ре-вендор или v2.0.0-Replace. Жди «go».

### 1.2 Стратегия — РЕШЕНО (Replace + ReSukiSU)
Из workflow убрать susfs-интеграцию TheWildJames (`50_add_susfs…` v2.1.0 + `ksun-…-susfs`) и `setup.sh`
KernelSU-Next. Подключить ReSukiSU:
```bash
curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s <branch>
# пин 47167aa7 (resukisu-pin.txt); точную ветку/команду сверить с доками ReSukiSU
```
Учесть: у ReSukiSU свой susfs inline hook — он и должен нести susfs v2.0.0 из `50_/51_`, без `ksun-susfs`.

### 1.3 Наложение патчей (CHECKPOINT 3)
KSU(ReSukiSU) уже интегрирован (1.2). Порядок: **`50_add_susfs` → `51_enhanced_susfs` → `70_ksu_safety-resukisu` → `60_zeromount`**.
Для каждого — сухой прогон, затем применение; `find . -name "*.rej"` ДОЛЖНО быть пусто.
`.rej`/фазз резолвить руками (tensynos тащит кастом в `newuname`/`namei`/`proc` — ждём конфликтов на `50_`).

**STOP — CHECKPOINT 3.** По каждому патчу: чисто/фазз/`.rej`; все `.rej` + ручные правки (diff); `git diff --stat`.
**Главный чекпоинт по смыслу.**

### 1.4 defconfig (CHECKPOINT 4)
Влить `./zeromount/defconfig.fragment` в `gs201_defconfig` (через `build-helpers/assemble-defconfig` или этап workflow).
Критично: **`CONFIG_ZEROMOUNT`** присутствует и `=y` (без него — OverlayFS-фолбэк), susfs-конфиги,
`CONFIG_KSU=y` (ReSukiSU), хук ReSukiSU для GKI2 корректен.
```bash
grep -nE "SUSFS|ZERO|ZEROMOUNT|KSU|KPM|KPROBES|TRACEPOINT" arch/arm64/configs/gs201_defconfig
```
**STOP — CHECKPOINT 4.** Вывод `grep` + подтверждение `CONFIG_ZEROMOUNT=y`.

### 1.5 Сборка (CHECKPOINT 5)
```bash
gh workflow run build-kernel-release.yml --ref zeromount-panther <inputs: target=gs201, feature=...>
gh run watch ; gh run view --log-failed
```
Грабли: несведённые символы susfs/zeromount (Replace неполный — остались куски v2.1.0/ksun-susfs);
`BUILD_BUG_ON` по `AS_FLAGS` (база susfs всё ещё не v2.0.0); ReSukiSU не подцепился.

**STOP — CHECKPOINT 5.** Статус; при ошибке — лог с первой ошибки; при успехе — состав zip (Image + gs201 dtb?).

---

## Проверка на устройстве (человек)

1. Бэкап `boot`/`init_boot`/`vbmeta` (+ `vendor_kernel_boot`/`dtbo` при необходимости).
2. **Сначала `fastboot boot`**, не `flash`. Бутлуп → ребут в сток.
3. `/dev/zeromount` есть; в WebUI ZeroMount **capability = VFS** (не OverlayFS); радио/Wi-Fi/датчики/термал живы;
   uname спуфится; mountinfo чистый для не-root.
4. Несколько чистых ребутов — только потом флашить в раздел.

> ⚠️ На Pixel 7/7Pro известен спонтанный ребут при подключении USB — device-баг линейки, НЕ от наших патчей.

## Откат
- После `fastboot boot`: ребут — грузится сток.
- После записи: `fastboot flash` стоковых `boot`/`init_boot`/`vbmeta`.
- Полный откат эксперимента: вернуться на baseline-тег Стадии 0.

---

## Что присылать в чат
- **CP0:** откат uname (diff) + `git status` + статус baseline-сборки + состав zip + имя тега baseline.
- **CP1.0:** есть ли v2.1.0-сет в upstream Super-Builders → ре-вендор или v2.0.0-Replace.
- **CP3:** по `50/51/70/60` — чисто/фазз/`.rej` + `.rej` + правки + `git diff --stat`.
- **CP4:** `grep` CONFIG + подтверждение `CONFIG_ZEROMOUNT=y`.
- **CP5:** статус сборки; лог с ошибки / состав zip.
