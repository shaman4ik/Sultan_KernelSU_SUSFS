# Runbook: panther (Pixel 7) — gs201 kernel + ReSukiSU + SUSFS + ZeroMount

Инструкция для Claude Code. Этот файл лежит в КОРНЕ форка `shaman4ik/Sultan_KernelSU_SUSFS` —
именно здесь ты работаешь. Цель — привить в это дерево **ZeroMount (VFS) + SUSFS**, совместимые
с **ReSukiSU**, и собрать загружаемое ядро для **Pixel 7 (panther, gs201)**. Прошивку и тест
на устройстве делает человек, не ты.

---

## Репозитории (зафиксировано)

| Роль | Repo | Примечание |
|------|------|------------|
| **Рабочее дерево (этот репо)** | `shaman4ik/Sultan_KernelSU_SUSFS` | форкаем, ветка `zeromount-panther`, сборка тут |
| Исходник ядра gs201/A16 | `kerneltoast/android_kernel_google_tensynos` @ `16.0.0-sultan` | подтягивается build-репо, не клонировать вручную без нужды |
| **Источник патчей (только чтение)** | `shaman4ik/Super-Builders` | твой форк = пиннинг; НИЧЕГО туда не коммитим |
| Референс готового артефакта | `WildKernels/Sultan_KernelSU_SUSFS/releases` | как выглядит рабочий gs201 AnyKernel3 |

### PIN — зафиксировать версию патчей
```
PATCH_REPO   = shaman4ik/Super-Builders
PATCH_REF    = <ВСТАВИТЬ_COMMIT_HASH>   # пин-коммит; если пусто — берётся main (не рекомендуется)
PATCH_DIR    = android14-6.1/ReSukiSU/patches
```
На CHECKPOINT 1 зафиксируй текущий HEAD `shaman4ik/Super-Builders` в `PATCH_REF`, чтобы апстрим
не уехал в середине работы. Все обращения к патчам — через `gh api .../contents/...?ref=$PATCH_REF`.

---

## 0. Контекст и цель

- Устройство: Pixel 7, codename `panther`, SoC `gs201`.
- Ветка ядра: **GKI android14-6.1** (panther остаётся на ней и под Android 16 — это нормально).
- Стоковый саблевел: **6.1.145**, Android 16 userspace.
- Root: **ReSukiSU** (форк KernelSU; менеджер совместим с KSU/MKSU/RKSU/SukiSU).
- Скрытие: **SUSFS** + **ZeroMount** в VFS-режиме (драйвер `/dev/zeromount`, перехват `getname()`).

### Принцип №1 — минимальный диф к рабочей базе
Sultan_KernelSU_SUSFS уже грузится на panther. Меняем как можно меньше. Device-специфичное
(модули gs201, упаковка AnyKernel3, способ прошивки) НЕ трогаем — используем существующий
workflow дерева как есть, только добавляем патчи и флаги конфига.

### Принцип №2 — собирать из gs201-дерева, не из generic GKI
Image и модули gs201 собираются из одного дерева, иначе KMI разъедется и panther не загрузится.
Поэтому мы берём из Super-Builders ТОЛЬКО патчи, а не его generic-GKI пайплайн.

### Принцип №3 — ZeroMount жёстко связан с SUSFS из `50_`
`60_zeromount` написан против конкретной версии SUSFS из `50_enhanced_susfs` (общие биты inode-флагов,
`AS_FLAGS` collision guards, supercall-проводка). Нельзя смешивать `60_` с ПРОИЗВОЛЬНОЙ версией SUSFS.
Это главный риск интеграции — см. Фазу 2. (В дереве Sultan SUSFS уже есть, на форуме мелькали 1.5.7/1.5.9.)

### Принцип №4 — про саблевел 145
«Оставить 145» = собранное ядро должно грузиться на стоке 6.1.145. Дерево может стоять на ≥145
(напр. 6.1.16x) — это допустимо: GKI грузит равный-или-старший саблевел при той же KMI-генерации.
НЕ даунгрейдить дерево до ровно 145. uname при необходимости спуфится через SUSFS.
Сверь только KMI-генерацию (`android14-XX`) дерева со стоком.

### Принцип №5 — это P7/P8/P9 репо, нужен именно gs201/panther
Дерево собирает и zuma (P8/P9). Везде целься в **gs201/panther**-вариант (его workflow, его defconfig),
не в zuma.

---

## Правила работы (строго)

1. **НИКОГДА не флашить, не запускать `fastboot flash`/`fastboot boot`.** Ты только собираешь и пакуешь.
2. На каждом **CHECKPOINT** — стоп, вывести указанный артефакт/лог, **ждать подтверждения человека**.
   Сам к следующей фазе не переходишь.
3. Все изменения — в ветке `zeromount-panther`. Осмысленные коммиты по шагам.
4. Патч лёг «с фаззом» (fuzz) или есть `.rej` — это НЕ успех. Стоп и репорт.
5. Ничего не «додумывай» про железо panther. Сомнения — в отчёт.
6. Упаковку/скрипты прошивки дерева без явного указания не править.

---

## 1. Recon (CHECKPOINT 1)

Ничего не менять. Только факты.

```bash
# 1.1 База: подтвердить gs201/panther-таргет в этом репо
gh repo view shaman4ik/Sultan_KernelSU_SUSFS
ls -la .github/workflows                 # какой workflow собирает gs201? его dispatch-инпуты?
# найти, где в workflow выбирается панель/устройство (gs201 vs zuma) и какой build entrypoint

# 1.2 Какой KSU-форк уже в дереве и как подключён (submodule / setup.sh / in-tree)?

# 1.3 Версия SUSFS уже в дереве — найти define:
grep -rni "SUSFS_VERSION\|susfs.*v1\.\|SUS_SU" --include=*.c --include=*.h | head

# 1.4 defconfig для panther/gs201 (arch/arm64/configs, gki_defconfig, device fragment) — где?

# 1.5 KMI-генерация и текущий саблевел дерева (android14-XX, 6.1.YYY)
```

```bash
# 1.6 Зафиксировать пин патчей и подтвердить файлы
gh api repos/shaman4ik/Super-Builders/commits/main --jq '.sha'   # -> записать в PATCH_REF
gh api "repos/shaman4ik/Super-Builders/contents/android14-6.1/ReSukiSU/patches?ref=$PATCH_REF" --jq '.[].name'
# ожидаем: 50_enhanced_susfs-...  60_zeromount-...  70_ksu_safety-...-6.1.patch
# + найти defconfig.fragment и build-helpers/ в android14-6.1/
# + достать версию SUSFS, против которой написан 50_ (строка/define внутри патча)
```

**STOP — CHECKPOINT 1. Отчёт человеку:**
- gs201/panther workflow + build entrypoint (подтвердить, что не zuma);
- KSU-форк в дереве сейчас и способ подключения;
- **версия SUSFS в дереве** vs **версия SUSFS в `50_`** (решает стратегию Фазы 2);
- путь(и) defconfig для panther;
- KMI-генерация + саблевел дерева;
- зафиксированный `PATCH_REF` (sha).

Жди решения по стратегии.

---

## 2. Стратегия SUSFS + KSU (CHECKPOINT 2)

Развилка по recon. Решает человек, ты предлагаешь.

**SUSFS:**
- **Вариант A (мало конфликтов):** версия SUSFS в дереве == версии под `50_`
  → `50_` НЕ применяем, используем SUSFS дерева, кладём только `70_` + `60_`.
- **Вариант B (правильнее):** версии расходятся
  → снять/отключить SUSFS-интеграцию дерева и положить матч-сет `50_` + `70_` + `60_`,
  чтобы биты inode-флагов совпали с ZeroMount.

**KSU:** цель — **ReSukiSU** (под него написан `70_ksu_safety`).
- Если в дереве другой форк (Wild_KSU / KSU-Next) — заменить на ReSukiSU по правилам дерева, затем:
  ```bash
  curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s <branch>
  # точную команду/branch взять из доков ReSukiSU
  ```
- KSU должен лежать ДО `70_` (патч правит код в `kernel/` форка).

**STOP — CHECKPOINT 2.** Вывести: выбранную стратегию SUSFS (A/B) с обоснованием; план по KSU
+ точную setup-команду; предварительный список затрагиваемых файлов. Жди «go».

---

## 3. Наложение патчей (CHECKPOINT 3)

Порядок строго как в Super-Builders: **`50_` → `70_` → `60_`** (в варианте A — `70_` → `60_`).

```bash
git checkout -b zeromount-panther

# для каждого патча: сухой прогон, затем применение
git apply --check -p1 <patch>            # должно молчать
git apply --reject  -p1 <patch>          # создаст *.rej при конфликте
git status --porcelain
find . -name "*.rej"                      # ДОЛЖНО быть пусто
```

Есть `.rej`/фазз — НЕ коммить «как есть». Резолвь руками: gs201 тащит out-of-tree-код в
`namei/readdir/proc/namespace`, контекст хунков может смещаться. После правки — `git apply --check`
на чистом состоянии. Применить `build-helpers/`, если нужны под текущий саблевел.

**STOP — CHECKPOINT 3.** Вывести: по каждому патчу (чисто/фазз/`.rej`); содержимое всех `.rej`
и твои ручные правки (diff); `git diff --stat`. **Главный чекпоинт по смыслу — жди ревью.**

---

## 4. defconfig + флаги (CHECKPOINT 4)

Влить `defconfig.fragment` в defconfig panther/gs201 (слить, не перетереть). Критично:
- SUSFS-конфиги (как в фрагменте);
- **CONFIG ZeroMount** — точный символ ИЗ `defconfig.fragment`, не угадывать. Без него драйвер
  не соберётся и VFS молча выпадет в OverlayFS-фолбэк;
- `CONFIG_KSU=y` (ReSukiSU), по желанию `CONFIG_KPM=y`;
- хук ReSukiSU включён корректно для GKI2 (tracepoint syscall redirect / susfs inline hook),
  без конфликта с manual hook.

```bash
grep -nE "SUSFS|ZERO|ZEROMOUNT|KSU|KPM|KPROBES|TRACEPOINT" <defconfig_path>
```

**STOP — CHECKPOINT 4.** Вывести результат `grep` + подтверждение, что символ ZeroMount есть и `=y`.

---

## 5. Сборка через Actions (CHECKPOINT 5)

Использовать **существующий** gs201-workflow дерева (он умеет в device-модули и упаковку panther).
Сборку с нуля не писать.

```bash
gh workflow run <gs201_workflow>.yml --ref zeromount-panther <inputs...>
gh run watch
gh run view --log-failed                  # при падении — хвост с первой ошибки
```

Грабли в логах: несведённые символы SUSFS/ZeroMount (значит SUSFS-версии разъехались → назад в Фазу 2,
вариант B); `BUILD_BUG_ON` по `AS_FLAGS` (конфликт битов inode-флагов); отсутствие toolchain/Kleaf-таргета
(брать тот, что в workflow дерева).

**STOP — CHECKPOINT 5.** Вывести: статус сборки; при ошибке — лог от первой ошибки (не весь);
при успехе — артефакты и итоговый `AnyKernel3*.zip`, что внутри (Image + модули gs201?). Жди «go».

---

## 6. Выдача артефакта (финал твоей части)

При зелёной сборке — ссылка на артефакт + мэппинг: саблевел, KMI-ген, KSU-форк, включён ли ZeroMount VFS.
**Дальше — человек.**

---

## 7. Проверка на устройстве (делает человек, не Claude Code)

1. Бэкап стоковых `boot` / `init_boot` / `vbmeta` (+ `dtbo`/`vendor_kernel_boot` при необходимости).
2. **Сначала `fastboot boot`**, НЕ `flash`. Бутлуп → ребут в сток.
3. Проверить: узел `/dev/zeromount` есть; в WebUI ZeroMount **capability = VFS** (не OverlayFS-фолбэк);
   радио/Wi-Fi/датчики/термал живые; `uname -r` спуфится (если включено); mountinfo чистый для не-root.
4. Только после нескольких чистых ребутов — флашить в раздел.

> ⚠️ Известный device-баг этой линейки: на Pixel 7/7Pro бывает спонтанный ребут при подключении USB.
> Он НЕ от наших патчей — не списывай на ZeroMount.

---

## 8. Откат

- Бутлуп после `fastboot boot`: просто ребут — устройство грузится со стока, ничего не записано.
- После записи: `fastboot flash` стоковых `boot`/`init_boot`/`vbmeta` из бэкапа.

---

## Что присылать в чат на каждом CHECKPOINT

- **CP1:** recon-отчёт (gs201-workflow, KSU-форк, **две версии SUSFS**, defconfig-путь, KMI-ген+саблевел, `PATCH_REF`).
- **CP2:** стратегия SUSFS/KSU + затрагиваемые файлы.
- **CP3:** статус по каждому патчу, все `.rej` и ручные правки, `git diff --stat`.
- **CP4:** `grep` финальных CONFIG-строк + подтверждение символа ZeroMount.
- **CP5:** статус сборки; при ошибке — лог с первой ошибки; при успехе — состав zip.
