# CHECKPOINT 1 — Вендоринг ZeroMount/ReSukiSU (Stage 1.1)

**Ветка:** `claude/vendoring-runbook-o9gdxi`
**Коммит:** `70b52c3` (запушен в origin)
**Дата:** 2026-06-28

---

## Содержимое `./zeromount/`

```
zeromount/
  patches/
    50_add_susfs_in_gki-android14-6.1.patch   (simonpunk susfs база)
    51_enhanced_susfs-android14-6.1.patch     (Enginex0 enhancements)
    60_zeromount-android14-6.1.patch          (ZeroMount VFS, CONFIG_ZEROMOUNT)
    70_ksu_safety-resukisu-6.1.patch          (ReSukiSU supercall guards)
    _archive/65_zeromount-adb-filter-…patch   (опционально, НЕ в цепочке)
  defconfig.fragment                          (KSU + susfs + zram + KPM + ZeroMount)
  build-helpers/  (assemble-defconfig, fix-susfs-compat, report-config, …)
  resukisu-pin.txt  -> 47167aa7
  VENDOR.md  (провенанс + sha256-верификация)
```

**Источник:** `shaman4ik/Super-Builders @ 7ea5c43`, путь `android14-6.1/`.
Все 15 файлов **байт-в-байт** идентичны источнику (sha256 сверены).

---

## ⚠️ Расхождение с рунбуком (важно)

Рунбук v1 предполагал «3 патча в `ReSukiSU/`». Реально:

- **4 патча** (отдельная база `50_add_susfs` **+** `51_enhanced_susfs`),
  а не «один `50_enhanced_susfs`».
- `defconfig.fragment` и `build-helpers/` лежат уровнем выше
  (`android14-6.1/`, общие для KSU-вариантов), не внутри `ReSukiSU/`.

---

## 🔑 Версия SUSFS из `50_`/`51_` vs дерево

- В `50_add_susfs` и `51_enhanced_susfs`: `#define SUSFS_VERSION "v2.0.0"`.
- → Матч-сет Enginex0 (`50_`+`51_`+`60_`) построен на **simonpunk susfs v2.0.0**.
- Дерево сейчас несёт **v2.1.0** (пин `ef16cbce`, патчи TheWildJames).

### Оценка конфликта битов

Есть расхождение версий **v2.0.0 (вендор) vs v2.1.0 (дерево)**.
`60_zeromount` жёстко завязан на раскладку inode-флагов / `AS_FLAGS`
именно из своего `50_/51_`. Накладывать `60_` поверх v2.1.0-susfs дерева —
ровно тот риск, о котором предупреждает рунбук. Это упирается в решение
**keep vs replace susfs** на Стадии 1.2.

---

## Рекомендация (решает человек — CHECKPOINT 2)

**Replace:** заменить susfs дерева (v2.1.0 + патчи TheWildJames) на матч-сет
`50_`+`51_` из вендора, чтобы `60_` лёг на свою родную базу v2.0.0, и
параллельно сделать swap KSU-Next → ReSukiSU.

Альтернатива — **keep** (оставить v2.1.0 дерева, добавить только `60_`) —
несёт риск конфликта битовой раскладки, не рекомендуется.

Жду «go» или выбор стратегии.
