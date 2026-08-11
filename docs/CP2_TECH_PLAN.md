# Технический план CP2 — все модули ERT (ATOL + Штрих)

Канон: [ARCHITECTURE_AND_UPDATE_SPEC.md](ARCHITECTURE_AND_UPDATE_SPEC.md).  
Задание: [../PLAN.md](../PLAN.md).  
База CP0/CP1: [CP0_CP1_TECH_PLAN.md](CP0_CP1_TECH_PLAN.md).

Статус: **реализован и принят** (ручной тест-план выполнен).

**Исправление модели:** нет «главных» и «сопутствующих». Каждый `.ert` из набора линейки — полноценный `ert-module` со своим id в `stable.json`. Ограничение CP1 «обновлять только frATOL54» снято.

Не в scope: код конфигурации (`module-form-of-check`, глобальный модуль) — не внешние обработки.

**База Delphi:** `ProjectkktUpdater1c77`.

---

## Границы

### В scope

- [x] Один пайплайн ERT для **всех** модулей ATOL и Штрих из таблицы id в PLAN
- [x] Manifest: опциональный набор component id (не только два «драйвера»)
- [x] Legacy gate по stem файла
- [x] UI: обновление любой строки, у которой component есть в канале
- [x] `stable.example.json` с примерами; боевой `stable.json` — только реальные публикации

### Вне scope

- [ ] Код конфигурации 1С: `module-form-of-check`, глобальный модуль (обновление вручную)
- [ ] Службы / proxy / `requires` / self-update
- [ ] Правки бизнес-логики модулей в репозиториях ATOL/Штрих
- [ ] `sync_modules.py` как клиентский updater

---

## Зафиксированные решения

- [x] Переиспользовать `UpdateErt` / `ErtStorage` / `ErtCodec` / `Backup` / download / hash
- [x] Таблица id ↔ файл ↔ репозиторий — как в PLAN.md (без дублирования «рангов»)
- [x] `1c77-atol-module` / `1c77-shtrih-module` сохранить (уже в обороте); остальные id — `1c77-atol-<stem>` / `1c77-shtrih-<stem>`
- [x] Одинаковые имена файлов ATOL vs Штрих → разные id
- [x] Legacy: `//<stem>(\.ert)? … ver: YYYY.MM.DD-NN`; не любой `ver:`
- [x] Для `1c77-atol-module` legacy stems: **`frATOL54`** и **`frATOL54_comm`**
- [x] После записи: `component` + `version` == manifest
- [x] Manifest: отсутствующий ключ ≠ ошибка; битый присутствующий — ошибка; `{}` допустим
- [x] Пути не из `stable.json`; no auto-downgrade
- [x] `ModuleCatalog` = только внешние `.ert` (10 id из PLAN); без кода конфигурации

---

## CP2.1 — Каталог модулей в коде

- [x] `AppConsts` (или отдельный unit `ModuleCatalog`): для каждого **ERT**-модуля  
  `ComponentId`, `FileStem`, `Line` (ATOL/Shtrih), `DefaultFileName`, `LegacyStemPattern`
- [x] Наборы для грида и снимка строить **только** из `ModuleCatalog` (единый источник истины)
- [x] В каталоге **нет** `module-form-of-check` и глобального модуля конфигурации
- [x] ATOL labels: Злобин, Стрелец; Штрих: Сургут
- [x] Для `1c77-atol-module`: в legacy-паттерне оба stem — `frATOL54` / `frATOL54_comm`

---

## CP2.2 — Manifest: словарь компонентов

### Сейчас

Жёстко требуется `1c77-atol-module`; Штрих и остальные id не читаются.

### Нужно

- [x] `TStableManifest`: `Components: TDictionary<string, TComponentManifest>` (или эквивалент) + хелпер `TryGet(id)`
- [x] При parse: обойти ключи `components`; для каждого с `type=ert-module` — `ParseComponent`, проверка id==ключ, `ParseVersionKey`
- [x] Неизвестные type (service и т.д.) в CP2 можно пропускать с логом (не падать)
- [x] Успех: schema OK + объект `components` существует (может быть пустым)
- [x] `stable.example.json`: несколько id ATOL и Штрих (не обязательно все сразу с полными URL — пометки REPLACE)

---

## CP2.3 — Legacy / gate по stem

- [x] Общая функция `HasLegacyStemVerMarker(Text, Stem, out VersionRaw)`  
      pattern: `//\s*<stem>(?:\.ert)?\b[^\r\n]*\bver:\s*(YYYY.MM.DD-NN)`
- [x] Для `1c77-atol-module`: stem-check принимает `frATOL54` **или** `frATOL54_comm`
- [x] `CheckComponentGate(ModuleText, ExpectedComponentId)`:
  - при наличии `component` — строгое сравнение
  - иначе — legacy по stem(ам) из каталога для этого id
  - иначе отказ
- [x] `ReadInstalledVersion`: показывать `component`/`version`, иначе legacy stem, иначе «нет version»
- [x] Убрать ATOL-only legacy в UI/gate как единственный путь

---

## CP2.4 — UI и оркестрация обновлений

### Убрать

- [x] Флаг/ветка «Updatable только frATOL54*»
- [x] Состояние «только просмотр» **как класс модулей** (допустимо лишь «нет в канале» / нет пути / нет version)

### Сделать

- [x] Строка грида несёт `ComponentId` (+ label ИБ, path, stem)
- [x] «Доступно» = `manifest[ComponentId].Version` или «—»
- [x] Состояния: нет пути / файл не найден / версия не задана / не проверен / нет в канале / актуально / обновление / локальная новее / ошибка
- [x] «Обновить выбранное»: prepare asset для `Row.ComponentId` → `UpdateErtInstance`
- [x] «Обновить всё»: сгруппировать строки с «обновление» по `ComponentId`; один download/prepare на группу; обновить все instances группы
- [x] Сбой одного instance не откатывает другие; сводка в статусе

Пути: по-прежнему якорь ИБ + поиск файлов по каталогу stem в `ExtForms\` / `Equip\`.

---

## CP2.5 — Config + WorkingSnapshot

- [x] При сохранении/detect по возможности заполнять instances для **всех** найденных ERT id линейки (не только двух драйверов)
- [x] Чтение старого config с только `1c77-atol-module` / `1c77-shtrih-module` — не ломать
- [x] Пользовательские пути не затирать из manifest
- [x] **`WorkingSnapshot`:** набор файлов только из `ModuleCatalog` соответствующей линейки + `1Cv7.MD` (как сейчас — только в архив, не восстанавливать).  
  Никакого отдельно вручную поддерживаемого списка файлов snapshot.  
  Не включать код конфигурации (`module-form-of-check`, глобальный модуль).  
  (В CP1 в companions Штрих ошибочно фигурировал `module-form-of-check` — убрать при переходе на каталог.)

---

## CP2.6 — Пайплайн записи

Без изменений порядка CP1.9; меняется только то, **какой** `TComponentManifest` и **какой** path передаём:

```text
precheck path + gate(component id / legacy stem)
  → download TXT этой версии component
  → SHA-256
  → TXT component/version + CRLF + strict CP1251
  → exclusive → re-read → backup → write → verify → rollback
```

---

## Порядок реализации

1. **CP2.1** — ModuleCatalog / consts  
2. **CP2.2** — Manifest dictionary + example  
3. **CP2.3** — legacy/gate по stem  
4. **CP2.4** — UI + RunUpdates  
5. **CP2.5** — config instances для всех id  
6. **CP2.6** — проверка оркестрации / сообщения / лог  
7. ~~Ручной тест-план~~ — выполнен

---

## Unit’ы

| Файл | Изменение |
|---|---|
| `AppConsts` (+ опц. `ModuleCatalog`) | каталог id↔stem↔line |
| `Manifest` | словарь компонентов, опциональный parse |
| `VersionParse` / `UpdateErt` | legacy по stem, нейтральный gate |
| `Config` | instances по всем id; совместимость со старым файлом |
| `kktUpdater1c77` | грид/Available/RunUpdates без «view-only касты» |
| `WorkingSnapshot` | набор файлов = ModuleCatalog линейки (+ MD в архив); без кода конфигурации |
| `channels/stable.example.json` | несколько ATOL + Штрих id |
| `channels/stable.json` | только реальные публикации |

`ErtStorage` / `ErtCodec` / `Backup` / `HttpDownload` / `HashUtil` — без смены контракта.

---

## Критерий готовности (код)

- [x] Любой модуль из каталога с путём и записью в manifest обновляется тем же пайплайном
- [x] Модуль без записи в канале — «нет в канале», не «второсортный просмотр»
- [x] ATOL (Злобин/Стрелец) и Штрих (Сургут) работают параллельно
- [x] Legacy stem → обновление → в ERT появляются `component`+`version`
- [x] Чужой ERT / чужой component → отказ до записи
- [x] Verify fail → rollback; no downgrade; config paths не из manifest
- [x] Снимок ИБ / видимость полей Titles — без регрессии

---

## Тест-план (ручной) — закрыт

- [x] Грид: все модули ATOL/Штрих по наличию ИБ
- [x] Manifest с одним id → обновляется только он
- [x] Manifest с несколькими id → «Обновить всё» пишет каждый своим TXT
- [x] `permissive_regime_2024` ATOL и Штрих — разные id, не путаются
- [x] Legacy `//… ver:` своего stem — OK; чужой ver — отказ
- [x] SHA/CP1251/locked/rollback/downgrade — как в CP1
- [x] Старый `config.json` с двумя драйверами открывается

### Prerequisite e2e

В каждом публикуемом TXT:

```text
// component: <id из таблицы>
// version: YYYY.MM.DD-NN
```

В боевой `stable.json` — только после реального Release и проверки.

---

## Вне этапа

CP3 службы · CP4 proxy · CP5 requires · CP6 self-update · CP7 release hygiene
