# Runbook v2: panther (Pixel 7) — gs201 + ReSukiSU + SUSFS + ZeroMount

Лежит в КОРНЕ форка `shaman4ik/Sultan_KernelSU_SUSFS`. Этот репо — build-orchestration
(само ядро `kerneltoast/android_kernel_google_tensynos` @ `16.0.0-sultan` клонируется workflow'ом).
Цель — добавить **ZeroMount (VFS) + ReSukiSU + совместимый SUSFS** и собрать загружаемое ядро для
**Pixel 7 (panther, gs201)**. Прошивку и тест делает человек, не ты.

> ⚠️ ВАЖНО: дерево собрано НЕ так, как предполагал рунбук v1. Реальный стек — **KernelSU-Next + simonpunk
> susfs v2.1.0** (патчи TheWildJames), ZeroMount отсутствует. Поэтому это не «наложить патч», а ре-платформинг
> части стека. Делаем стадиями, держа рабочий фоллбэк.

---

## Репозитории и факты recon (зафиксировано)

| Роль | Значение |
|------|----------|
| Рабочее дерево (этот репо) | `shaman4ik/Sultan_KernelSU_SUSFS` |
| Исходник ядра | `kerneltoast/android_kernel_google_tensynos` @ `16.0.0-sultan`, клонируется в workflow |
| Dispatch workflow | `.github/workflows/build-kernel-release.yml` → reusable `sultan.yml`, таргеты: **gs201**/zuma/zumapro |
| Сборка gs201 | codename `gs201`, android14, 6.1, **GCC 14.2.0**, `make gs201_defconfig`, AnyKernel3 (`Image.lz4` + `gs201` dtb) |
| Матрица фич | `stock`, `wksu-susfs` |
| KSU сейчас | **KernelSU-Next** (пин `293ca016…`), через `setup.sh` |
| SUSFS сейчас | **simonpunk susfs v2.1.0** (gitlab пин `ef16cbce`, ветка `gki-android14-6.1`); патчи `50_add_susfs_in_gki-android14-6.1.patch` + `ksun-…-susfs-v2.1.0-…` из `TheWildJames/kernel_patches` |
| defconfig | `arch/arm64/configs/gs201_defconfig` (внутри клонируемого дерева; в этом репо его нет) |
| KMI / саблевел | `android14-6.1` |
| ZeroMount | **отсутствует** |

### Источник патчей ZeroMount — ВЕНДОРИНГ
Скопировать из `shaman4ik/Super-Builders` каталог `android14-6.1/ReSukiSU/` (3 патча + `defconfig.fragment`
+ `build-helpers/`) в этот репо в `./zeromount/`. Дальше читать ТОЛЬКО из `./zeromount/`. Это фиксирует версию
патчей и снимает проблему доступа ко второму репо.
```
PATCH_DIR = ./zeromount            # 50_enhanced_susfs / 60_zeromount / 70_ksu_safety-resukisu / defconfig.fragment / build-helpers
```
(Альтернатива: смонтировать `shaman4ik/Super-Builders` вторым репо в сессию и читать из его пути. Вендоринг проще.)

---

## Принципы

1. **Минимальный диф к рабочей базе.** gs201-сборка дерева грузится на panther; device-часть
   (`gs201_defconfig`, GCC 14.2.0, dtb, AnyKernel3 с device-check panther) НЕ трогаем без нужды.
2. **Собирать из gs201-дерева**, не из generic GKI (иначе KMI разъедется).
3. **ZeroMount `60_` жёстко связан с SUSFS из `50_`** (биты inode-флагов, `AS_FLAGS` guards, supercall).
   Нельзя мешать `60_` с произвольной версией susfs — отсюда главный вопрос Стадии 1.
4. **Саблевел:** цель — грузиться на стоке 6.1.145; равный-или-старший саблевел дерева при той же KMI
   допустим, насильно не даунгрейдить.
5. **Это P7/P8/P9 репо** — целиться строго в **gs201/panther**, не zuma.
6. **Стадийность** (ниже): сперва рабочий фоллбэк, потом эксперимент.

---

## Правила работы (строго)

1. **НИКОГДА не флашить / `fastboot flash` / `fastboot boot`.** Только сборка и упаковка.
2. На каждом **CHECKPOINT** — стоп, вывести артефакт/лог, ждать подтверждения человека.
3. Стадия 0 — в `main`/чистой ветке; Стадия 1 — в отдельной ветке `zeromount-panther`.
4. Фазз/`.rej` ≠ успех. Стоп и репорт.
5. Про железо panther ничего не «додумывать».

---

## СТАДИЯ 0 — чистый baseline (фоллбэк, низкий риск)

Дать рабочее ядро на текущем стеке (KSU-Next + susfs v2.1.0) и проверить пайплайн в руках агента.

1. **Откатить незакоммиченный мусор uname-спуфа** из прошлой сессии: `sys.c`, `sys.c.rej`,
   `sys.c_fix.patch` (коммит `2cd9bc7`). Причина: у kerneltoast `newuname()` кастомный (is_gms/libperfmgr),
   и в него УЖЕ вручную вставлен `susfs_spoof_uname(&tmp)`. Патч `sys.c_fix.patch` ждёт вариант со
   `static_branch_likely(&susfs_is_uname_spoof_buffer_set)` — отсюда `.rej`. Патч **выкинуть**,
   убедившись, что ручной `susfs_spoof_uname` на месте и корректен.
2. Восстановить чистое состояние дерева (`git status` чистый, никаких `.rej`).
3. Собрать **gs201/panther** существующим workflow (фича `wksu-susfs`), без изменений стека.

**STOP — CHECKPOINT 0.** Вывести: что откатил (diff), `git status`, статус сборки; при успехе — имя
`AnyKernel3*.zip` и что внутри. Это валидированный фоллбэк. Жди «go» на Стадию 1.

---

## СТАДИЯ 1 — интеграция ZeroMount + ReSukiSU (ветка `zeromount-panther`)

### 1.1 Вендоринг + проверка совместимости SUSFS (CHECKPOINT 1)

```bash
git checkout -b zeromount-panther
# скопировать ./zeromount/ из Super-Builders-форка (или из смонтированного репо), закоммитить
ls ./zeromount
```
Ключевая проверка ПЕРЕД любым swap'ом: **на какой версии simonpunk susfs основан `50_enhanced_susfs`
Enginex0 и совместима ли раскладка `AS_FLAGS`/inode-битов с тем, что сейчас в дереве (v2.1.0)?**
Найти версию внутри `./zeromount/50_*.patch` (define/строка) и сравнить с `ef16cbce` (v2.1.0).

**STOP — CHECKPOINT 1.** Вывести: содержимое `./zeromount/` (список файлов), **версию susfs из `50_`**
vs v2.1.0 дерева, первичную оценку конфликта битов. Жди решения стратегии.

### 1.2 Стратегия SUSFS + KSU (CHECKPOINT 2) — решает человек

- **SUSFS:**
  - если `50_`-база совместима с v2.1.0 → оставить susfs дерева, добавить только `60_`;
  - если расходится → заменить susfs дерева на тот, что несёт `50_` (матч-сет `50_`+`60_`), убрав
    патчи susfs от TheWildJames.
- **KSU: swap `KernelSU-Next` → `ReSukiSU`** (под него написан `70_ksu_safety`; под KSU-Next его нет).
  Это правка интеграции в workflow: заменить `setup.sh` KSU-Next на ReSukiSU и подогнать пин/ветку.
  ```bash
  curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s <branch>
  ```
  Учесть: у ReSukiSU свой susfs inline hook — свериться, чтобы хук-режим не конфликтовал с тем, как
  susfs заходит в дерево после решения по пункту выше.

**STOP — CHECKPOINT 2.** Вывести: стратегию susfs (keep/replace) с обоснованием; точные правки swap'а
KSU-Next→ReSukiSU в workflow; список затрагиваемых файлов. Жди «go».

### 1.3 Наложение патчей (CHECKPOINT 3)

Порядок: **`50_` → `70_` → `60_`** (или `70_`→`60_`, если susfs оставили). Для каждого — сухой прогон,
затем применение; `find . -name "*.rej"` ДОЛЖНО быть пусто. `.rej`/фазз резолвить руками (tensynos тащит
кастом в `newuname`/`namei`/`proc`).

**STOP — CHECKPOINT 3.** По каждому патчу: чисто/фазз/`.rej`; все `.rej` + твои правки (diff);
`git diff --stat`. **Главный чекпоинт по смыслу.**

### 1.4 defconfig (CHECKPOINT 4)

Влить `./zeromount/defconfig.fragment` в `gs201_defconfig` (как этап workflow или прямой правкой).
Критично: **символ CONFIG ZeroMount из фрагмента** (без него — OverlayFS-фолбэк), susfs-конфиги,
`CONFIG_KSU=y` (ReSukiSU), хук ReSukiSU для GKI2 корректен.
```bash
grep -nE "SUSFS|ZERO|ZEROMOUNT|KSU|KPM|KPROBES|TRACEPOINT" arch/arm64/configs/gs201_defconfig
```
**STOP — CHECKPOINT 4.** Вывести `grep` + подтверждение, что символ ZeroMount присутствует и `=y`.

### 1.5 Сборка (CHECKPOINT 5)

Запустить gs201-таргет существующего workflow на ветке `zeromount-panther`.
```bash
gh workflow run build-kernel-release.yml --ref zeromount-panther <inputs: target=gs201, feature=...>
gh run watch ; gh run view --log-failed
```
Грабли: несведённые символы susfs/zeromount (база susfs разъехалась → назад в 1.2); `BUILD_BUG_ON`
по `AS_FLAGS`; KSU-swap не подцепился.

**STOP — CHECKPOINT 5.** Статус; при ошибке — лог с первой ошибки; при успехе — состав zip
(Image + gs201 dtb?). Жди «go» на выдачу.

---

## Проверка на устройстве (человек)

1. Бэкап `boot`/`init_boot`/`vbmeta` (+ `vendor_kernel_boot`/`dtbo` при необходимости).
2. **Сначала `fastboot boot`**, не `flash`. Бутлуп → ребут в сток.
3. Проверить: `/dev/zeromount` есть; в WebUI ZeroMount **capability = VFS** (не OverlayFS-фолбэк);
   радио/Wi-Fi/датчики/термал живы; uname спуфится; mountinfo чистый для не-root.
4. Несколько чистых ребутов — только потом флашить в раздел.

> ⚠️ На Pixel 7/7Pro у этой линейки известен спонтанный ребут при подключении USB — это device-баг,
> НЕ от наших патчей.

---

## Откат

- После `fastboot boot`: ребут — грузится сток.
- После записи: `fastboot flash` стоковых `boot`/`init_boot`/`vbmeta` из бэкапа.
- Полный откат эксперимента: вернуться на артефакт Стадии 0.

---

## Что присылать в чат

- **CP0:** что откатил (diff) + `git status` + статус baseline-сборки + состав zip.
- **CP1:** список `./zeromount/`, **версия susfs из `50_`** vs v2.1.0, оценка конфликта битов.
- **CP2:** стратегия susfs + правки swap'а KSU-Next→ReSukiSU + затрагиваемые файлы.
- **CP3:** по патчам (чисто/фазз/`.rej`) + `.rej` + правки + `git diff --stat`.
- **CP4:** `grep` CONFIG + подтверждение символа ZeroMount.
- **CP5:** статус сборки; лог с ошибки / состав zip.
