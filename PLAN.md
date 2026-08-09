# PLAN: 1C77 KKT Updater — CP2 (все модули ERT ATOL + Штрих)

Канон: [docs/ARCHITECTURE_AND_UPDATE_SPEC.md](docs/ARCHITECTURE_AND_UPDATE_SPEC.md).  
Готово ранее: [docs/CP0_CP1_TECH_PLAN.md](docs/CP0_CP1_TECH_PLAN.md) (CP0/CP1; ограничение «обновлять только frATOL54» — **снимается в рамках этого этапа**).

Этот файл — **задание на updater для CP2**. Не трогать Delphi-службы и C# proxy. Репозитории ATOL/Штрих — только при необходимости заголовков `component`/`version` в публикуемых TXT (не бизнес-логика модулей).

**Не начинать с «реализуй PLAN целиком».** Сначала: spec + этот PLAN → подробный техплан CP2 → код после принятия.

---

## Главное исправление модели

Все перечисленные `.ert` — **одинаковые** продукты типа `ert-module`. Нет «главных» и «сопутствующих» с разным правом на обновление.

В UI и в канале: **каждый файл модуля** — отдельный component id, своя `version`, свой TXT asset, свой SHA-256.  
Обновляется любой модуль, для которого есть запись в `stable.json` и известен путь на диске.

«Только frATOL54 / только просмотр остальных» — было искусственным сужением CP1; в CP2 это убираем.

---

## Цель этапа

1. Тот же пайплайн записи ERT (как CP1) для **каждого** модуля линейки.
2. Подключить линейку **Штрих** (Сургут) целиком.
3. Включить обновление **всех** модулей линейки **ATOL** (Злобин / Стрелец), не только `frATOL54_comm`.

```text
channels/stable.json
  → для выбранного component id: скачать TXT → SHA → gate → exclusive → backup → write → verify → rollback
```

Экземпляры по ИБ (как раньше):

| Линейка | ИБ (labels) | Модули (файлы) |
|---|---|---|
| ATOL | Злобин, Стрелец | `frATOL54_comm`, `permissive_regime_2024`, `razresh_regim_check`, `razresh_regim_dialog_error`, `test_check` |
| Штрих | Сургут | `fr_elves-12`, `fr_elves_test`, `permissive_regime_2024`, `razresh_regim_check`, `razresh_regim_dialog_error` |

Пути ATOL-модулей кроме `frATOL54*`: обычно `ExtForms\` (не Equip). `frATOL54*` часто в `ExtForms\Equip\`.

**Вне updater:** `module-form-of-check` и глобальный модуль конфигурации — код в конфигурации 1С, не внешние обработки; обновляются вручную.

---

## Зафиксированные решения

### Component id (постоянные)

Сохранить уже использованные id драйверов; остальные — по stem файла:

| ID | Файл | Репозиторий |
|---|---|---|
| `1c77-atol-module` | `frATOL54_comm.ert` | `1c77-tspiot-atol` |
| `1c77-atol-permissive_regime_2024` | `permissive_regime_2024.ert` | `1c77-tspiot-atol` |
| `1c77-atol-razresh_regim_check` | `razresh_regim_check.ert` | `1c77-tspiot-atol` |
| `1c77-atol-razresh_regim_dialog_error` | `razresh_regim_dialog_error.ert` | `1c77-tspiot-atol` |
| `1c77-atol-test_check` | `test_check.ert` | `1c77-tspiot-atol` |
| `1c77-shtrih-module` | `fr_elves-12.ert` | `1c77-tspiot-shtrih` |
| `1c77-shtrih-fr_elves_test` | `fr_elves_test.ert` | `1c77-tspiot-shtrih` |
| `1c77-shtrih-permissive_regime_2024` | `permissive_regime_2024.ert` | `1c77-tspiot-shtrih` |
| `1c77-shtrih-razresh_regim_check` | `razresh_regim_check.ert` | `1c77-tspiot-shtrih` |
| `1c77-shtrih-razresh_regim_dialog_error` | `razresh_regim_dialog_error.ert` | `1c77-tspiot-shtrih` |

Одинаковые имена файлов у ATOL и Штрих — **разные** id (разный текст/репозиторий). Итого **10** `ert-module` (не код конфигурации).

### Gate / legacy

- Есть `component:` → должен совпасть с ожидаемым id.
- Нет `component:` → legacy OK только при маркере своего stem:  
  `//<stem>` или `//<stem>.ert` … `ver: YYYY.MM.DD-NN`  
  (пример: `//fr_elves-12.ert ver:…`, `//permissive_regime_2024 ver:…`).
- Для `1c77-atol-module` legacy допускаются оба исторических stem: **`frATOL54`** и **`frATOL54_comm`**.
- Произвольный чужой `ver:` → отказ.
- После успешной записи в ERT обязательны `component` + `version` из manifest.

### Manifest

- Любой набор ключей в `components` **опционален** (в т.ч. пустой `{}`).
- Битые поля **присутствующего** компонента → ошибка.
- Боевой `stable.json` — только реальные URL/SHA; образцы всех id — в `stable.example.json`.
- Asset: `<component-id>-YYYY.MM.DD-NN.txt`, tag по соглашениям релиза (`module-*` или согласованный префикс на модуль).

### UI / обновление

- Каждая строка грида = один модуль × одна ИБ.
- Строка **обновляема**, если для её component id есть запись в manifest и есть путь к `.ert`.
- Нет записи в канале → «нет в канале» / «—» в «Доступно», запись не предлагать (это не «вечный просмотр по рангу модуля»).
- «Обновить выбранное» — один component × один instance.
- «Обновить всё» — все строки с состоянием «обновление»; сбой одного не откатывает уже успешные.
- No auto-downgrade; пути в config не из `stable.json`.

### Config / пути

- Как сейчас: якоря ИБ (пути к известным ERT по labels Злобин/Стрелец/Сургут) + поиск соседних `.ert` по известным именам в `ExtForms\` / `ExtForms\Equip\`.
- В `config.json` со временем — instances по **каждому** component id; миграция без потери уже сохранённых путей `1c77-atol-module` / `1c77-shtrih-module`.

### Вне CP2

- Код конфигурации 1С: `module-form-of-check`, глобальный модуль — только вручную
- Delphi-службы, C# proxy, `requires`, самообновление updater
- Полный CP7 hygiene (кроме минимальных заголовков в TXT asset для e2e)

---

## CP2 (чеклист)

- [x] Модель: все модули равноправны; убрать логику «только frATOL54 / view-only остальные»
- [x] Manifest: словарь `ert-module` по id из таблицы выше (parse опциональный)
- [x] `stable.example.json` — примеры нескольких ATOL + Штрих id
- [x] Legacy gate по stem для каждого модуля
- [x] UI: «Доступно» / состояния / Обновить по component id строки
- [x] Тот же `UpdateErt` для любого id
- [x] Лог: component id + label ИБ + stem

---

## Критерий готовности CP2

На ПК с нужными ИБ в гриде видны все модули линейки; у модулей с записью в `stable.json` работает Проверить / Обновить / rollback; модули без записи в канале не обновляются, но не из-за «второсортности»; ATOL и Штрих используют один пайплайн; пути config не портятся из manifest.
