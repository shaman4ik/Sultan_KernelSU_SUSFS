# CHECKPOINT 1.0 — Проверка апстрима перед даунгрейдом susfs

**Ветка:** `claude/vendoring-runbook-o9gdxi`
**Дата:** 2026-06-28
**Цель:** до деструктивного Replace убедиться, что в upstream нет готового
v2.1.0-матч-сета (`50_/51_/60_` на susfs v2.1.0) — иначе ре-вендорить его
вместо даунгрейда дерева до v2.0.0.

---

## Что проверяли

- **Upstream:** `Enginex0/Super-Builders` (подтверждён README форка: это build-pipeline
  ZeroMount — `github.com/Enginex0/zeromount`).
- **Вендор-пин:** форк `shaman4ik/Super-Builders @ 7ea5c43`, путь `android14-6.1/`.

---

## Результаты

### Есть ли в upstream готовый v2.1.0-матч-сет? — НЕТ.

| Проверка | Результат |
|---|---|
| Ветки upstream | `main`, `feature/bbk-ogki-workflows`, `worktree-samsung-ogki`, `experiment/samsung-m14-reference`, `feature/patch-restructure` — **ни одной** susfs/v2.1.0/zeromount-версионной |
| `50_`/`51_` на `main` | `#define SUSFS_VERSION "v2.0.0"` (оба) — v2.1.0-бампа нет |
| Свежие коммиты по `patches/` | последний `cffc854` (22 мар 2026) «fix(zeromount): guard against ERR_PTR filename in stat hook»; ранее рефактор «split monolithic → 50_+51_» (`5e3e36c`, 7 мар), всё на базе **v2.0.0** |
| Вендор vs upstream HEAD (sha256) | `50_/51_/60_/70_` + `defconfig.fragment` — **совпадают** |

### Лог коммитов upstream по `android14-6.1/ReSukiSU/patches/`
```
cffc854  2026-03-22  cawilliamson  fix(zeromount): guard against ERR_PTR filename in stat hook
93bc005  2026-03-08  Enginex0      perf(zeromount): skip recursive mkdir when path already exists
2112713  2026-03-08  Enginex0      refactor(susfs): remove UID_GATED_HIDING from 51_ patches
e7a0160  2026-03-08  Enginex0      fix(susfs): apply IS_ERR and cleanup fixes to 6.1/6.12
889b653  2026-03-07  Enginex0      refactor(susfs): remove defconfig hunks from 51_ patches
5e3e36c  2026-03-07  Enginex0      refactor(susfs): split 6.1 monolithic into upstream 50_ + enhanced 51_
```

### Sha256-сверка вендор vs `Enginex0/Super-Builders@main`
```
50_add_susfs_in_gki-android14-6.1.patch    9dafe5a5561a…  MATCH
51_enhanced_susfs-android14-6.1.patch      90b68184eb44…  MATCH
60_zeromount-android14-6.1.patch           530b5dfeb741…  MATCH
70_ksu_safety-resukisu-6.1.patch           3866a128c574…  MATCH
defconfig.fragment                         1a2cfef09ef9…  MATCH
```

---

## Вывод

- Ре-вендорить **нечего**: `./zeromount/` уже на последнем upstream-состоянии
  (включая `cffc854`); новее/v2.1.0 в апстриме не существует. ZeroMount-база живёт
  строго на susfs **v2.0.0**.
- Даунгрейд susfs дерева (v2.1.0 → v2.0.0) **неизбежен** → идём на **Replace с v2.0.0**,
  как зафиксировано в CP2/v3. Дешёвая проверка вопрос не сняла, но подтвердила: другого пути нет.

---

## Статус двух страховок

1. ✅ **Апстрим-проверка (CP1.0)** — сделана. Итог: Replace v2.0.0.
2. ✅ **Откат Стадии 0** — `sys.c*` + шаг `sys.c_fix.patch` выкинуты, дерево чистое,
   без `.rej`, запушено (`895a268`).
   - ⏳ Не закрыто: валидная baseline-сборка (решение «не собирать сейчас») и
     формальный baseline-тег. Ветку Replace ответвлять от чистого baseline.

## Открытый вопрос
Ветку `zeromount-panther` (Replace) ответвлять сейчас от чистого `895a268`,
или сперва снять валидную baseline-сборку (тогда — выбор режима запуска workflow)?
