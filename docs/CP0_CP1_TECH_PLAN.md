# Технический план CP0 + CP1 (+ дополнения сессии)

Канон: [ARCHITECTURE_AND_UPDATE_SPEC.md](ARCHITECTURE_AND_UPDATE_SPEC.md).  
Задание этапа: [../PLAN.md](../PLAN.md) — **источник истины по статусу чекпоинтов**.

Статус: **CP0 / CP1 реализованы**; дополнения сессии (набор модулей в гриде, Штрих в UI, снимок, видимость полей, версия exe) — **реализованы**.  
Ручной прогон тест-плана на машине с двумя ИБ (`CP1.11`) — **выполнен** (принято пользователем).

**Коррекция модели (после CP1):** деление «главный / companions / только просмотр» было искусственным сужением MVP. Все `.ert` линейки равноправны. Актуальная модель и задание — [../PLAN.md](../PLAN.md) + [CP2_TECH_PLAN.md](CP2_TECH_PLAN.md). Этот файл сохраняет историю CP0/CP1.

**База Delphi:** существующий VCL-проект (не новый `.dpr` с нуля).

| Файл | Назначение |
|---|---|
| `ProjectkktUpdater1c77.dpr` / `.dproj` | Точка входа / проект |
| `kktUpdater1c77.pas` / `.dfm` | Главная форма (`TfrmMain`) |
| `units\*.pas` | Логика |
| `channels/stable.json` | Боевой manifest (только реальные публикации) |
| `channels/stable.example.json` | Пример полей |
| `tests/ErtRoundtripTest.dpr` | OLE roundtrip |

Корень проекта не переносить в `src\`, пока сами не решим иначе.

---

## Границы

### В scope (сделано)

- [x] Delphi updater на существующем проекте
- [x] Реестр Titles → кандидаты Злобин / Стрелец / Сургут
- [x] `%ProgramData%\1C77KKTUpdater\config.json` с `instances[]`
- [x] `channels/stable.json` только с реально разрешёнными клиентам версиями (без фиктивных URL/SHA); пока релизов нет — допустим пустой `components: {}`  
  На момент CP1 парсер был рассчитан на обязательный `1c77-atol-module`. После перехода к CP2 пустой `components` допустим, парсер должен быть обобщён (см. CP2).
- [x] HTTPS: manifest + TXT asset
- [x] UI: строки ATOL (+ остальные модули линейки в гриде); Проверить / Обновить выбранное / Обновить всё
- [x] Пайплайн ERT: exclusive → re-read → backup → write → verify → rollback
- [x] Лог в ProgramData
- [x] Дополнения сессии: полный набор модулей в гриде, Штрих в UI, снимок рабочей конфигурации, условная видимость полей, версия updater в заголовке
  (обновление «только frATOL54» / «остальные view-only» — ограничение CP1, снимается в CP2)

### Вне scope на момент CP1 (актуализировано)

- [ ] **Обновление всех модулей ERT + Штрих** — перенесено в **CP2** (равноправные id, не «view-only»)
- [ ] Delphi-службы, C# proxy, `requires`, самообновление updater
- [ ] Правки репозиториев ATOL / Штрих / proxy (кроме чтения контракта из spec)
- [ ] Клиентская логика через правки `sync_modules.py`

Справочник только для чтения: `описание-модуля-на-Delphi-для-1cv77.txt`, `sync_modules.py`, `installer_1cv77_extforms.iss`.

---

## Зафиксированные решения

- [x] Источник путей: только `%ProgramData%\1C77KKTUpdater\config.json`
- [x] Рядом с exe конфиг не дублировать как основной
- [x] Пути пользователя никогда не перезаписывать из `stable.json`
- [x] Один URL `stable.json` (константа / `manifest_url`), не строить из `component.repository`
- [x] Default URL: `https://raw.githubusercontent.com/AlexanderYekat/1c77-kkt-updater/main/channels/stable.json`
- [x] ATOL: два экземпляра ERT (Злобин, Стрелец), не один path на component id
- [x] Component gate до записи; legacy без `component` — только маркер `//frATOL54[_comm] ver:` (не любой `ver:`)
- [x] После обновления в ERT обязательны `component: 1c77-atol-module` и новая `version`
- [x] Backup после exclusive probe/re-read, до записи; при fail verify — автоматический rollback
- [x] Порядок: exclusive probe → re-read → backup → write (сверка prior version под exclusive)
- [x] Запись потока: Seek(0) → SetSize → Write → Commit; CRLF + строгий CP1251
- [x] Локальная version новее channel → без auto-downgrade
- [x] `requires` / services / proxy / self-update — не реализовывать в этом этапе
- [x] База: существующий `ProjectkktUpdater1c77`
- [x] Кириллица: captions в коде / `#$` в константах; важные `.pas` — UTF-8 BOM
- [x] Сборка из IDE (Delphi 23)

---

## CP0 — Подготовка

### CP0.1 — Константы и ProgramData

- [x] Зафиксировать ID: `1c77-atol-module`, type: `ert-module` (+ `1c77-shtrih-module` в модели)
- [x] Формат версии: `YYYY.MM.DD-NN`, сравнение `(YYYY, MM, DD, NN)`
- [x] `schema_version: 1` для config и manifest
- [x] Unit `AppConsts`: URL manifest, пути ProgramData, component id, labels, имена ERT
- [x] Unit `AppPaths`: bootstrap каталогов
  - [x] `%ProgramData%\1C77KKTUpdater\`
  - [x] `logs\`
  - [x] `backup\`
  - [x] `cache\`
  - [x] `snapshots\` (дополнение сессии)

### CP0.2 — `config.json`

- [x] Unit `Config`: load / save
- [x] Формат: JSON, `"schema_version": 1`
- [x] Модель: `component id` → `instances[{ "label", "path" }]`
- [x] Слот `1c77-shtrih-module` / label «Сургут» в модели (+ UI; обновление остальных модулей — CP2)
- [x] Опционально `manifest_url` (`null` → константа приложения)
- [x] Атомарная запись (temp → replace)
- [x] Неизвестный `schema_version` → явный отказ
- [x] Неизвестные поля при чтении по возможности сохранять (forward-compatible)
- [x] Пользовательские пути никогда не брать/не писать из `stable.json`

Пример структуры:

```json
{
  "schema_version": 1,
  "manifest_url": null,
  "components": {
    "1c77-atol-module": {
      "instances": [
        { "label": "Злобин", "path": "C:\\...\\ExtForms\\Equip\\frATOL54_comm.ert" },
        { "label": "Стрелец", "path": "C:\\...\\ExtForms\\Equip\\frATOL54_comm.ert" }
      ]
    },
    "1c77-shtrih-module": {
      "instances": [
        { "label": "Сургут", "path": "C:\\...\\ExtForms\\fr_elves-12.ert" }
      ]
    }
  }
}
```

### CP0.3 — Реестр ИБ

- [x] Unit `RegistryBases`
- [x] Чтение `HKCU\Software\1C\1Cv7\7.7\Titles` (имя value = путь ИБ, данные = название)
- [x] Фильтр ATOL: подстроки «Злобин», «Стрелец» (case-insensitive)
- [x] Фильтр Штрих «Сургут» — FindSurgutBases + UI
- [x] Кандидаты ERT: `{IB}\ExtForms\`, `{IB}\ExtForms\Equip\`
- [x] Подсказка имени ATOL: `frATOL54_comm.ert` / `frATOL54.ert`; Штрих: `fr_elves-12.ert`
- [x] Понятные сообщения, если ключа нет / пусто / нет прав

### CP0.4 — UI выбора путей

- [x] На форме: пути Злобин / Стрелец / Сургут; Detect / Save
- [x] Сохранить пути в `config.json`
- [x] Caption → «1C77 KKT Updater» (+ версия exe — дополнение)
- [x] Условная видимость полей по Titles (дополнение сессии)

### Критерий готовности CP0

- [x] Константы ID / type / version в коде
- [x] Titles читается; Злобин / Стрелец / Сургут находятся (на машине с соответствующими базами)
- [x] `config.json` создаётся / читается / пишется; независимые path ATOL (+ Сургут)
- [x] Сургут в модели и UI (обновление модулей Штрих — CP2)
- [x] Скачивание/запись ERT — в CP1 (не в CP0)

---

## CP1 — MVP: модуль 1С ATOL

### CP1.1 — `channels/stable.json`

- [x] `channels/stable.json` — **только** реально разрешённые клиентам версии (без фиктивных URL/SHA)
- [x] `channels/stable.example.json` — пример полей до появления Release
- [x] Поля компонента: `id`, `type`, `version`, `repository`, `tag`, `asset`, `download_url`, `sha256`
- [x] `type`: `ert-module`
- [x] `requires` не enforce (если поле появится — игнорировать)

### CP1.2 — Загрузка manifest по HTTPS

- [x] Unit `Manifest`
- [x] GET с фиксированного URL (константа / `config.manifest_url`)
- [x] HTTPS only, без GitHub PAT
- [x] Parse JSON, `schema_version == 1`
- [x] Найти `components["1c77-atol-module"]`
- [x] Проверить обязательные поля; `type` должен быть `ert-module`
- [x] Источник «Доступно» — свежая загрузка по «Проверить»

### CP1.3 — Чтение ERT (OLE + версия) + технический тест

- [x] Unit `ErtStorage`: `IStorage` / `IStream`, поток `MD Programm text`
- [x] Unit `ErtCodec`: raw DEFLATE (`windowBits = -15`) ↔ CP1251
- [x] Unit `VersionParse`:
  - [x] `// component:` + `// version:`
  - [x] fallback `ver: YYYY.MM.DD-NN` (для отображения)
  - [x] опционально `глЭтотМодульВерсияМодуля` только как доп. fallback версии
  - [x] legacy ATOL gate: `//frATOL54[_comm] … ver:`
- [x] Техтест `tests/ErtRoundtripTest.dpr`: read → long write → read → short write → read; прочие OLE-потоки (SHA) без изменений

### CP1.4 — UI таблицы обновлений

- [x] Таблица по экземплярам (не один ряд на component id):
  - [x] Модуль 1С ATOL / Злобин (+ остальные модули линейки в гриде)
  - [x] Модуль 1С ATOL / Стрелец (+ остальные модули линейки в гриде)
  - [x] Штрих / Сургут (+ модули линейки в гриде; обновление — CP2)
- [x] Колонки: экземпляр | Установлено | Доступно | Состояние
- [x] Кнопка **Проверить обновления**
- [x] Кнопка **Обновить выбранное**
- [x] Кнопка **Обновить всё**
- [x] Состояния: нет пути / файл не найден / версия не задана / не проверен / актуально / обновление / **локальная версия новее** / только просмотр / ошибка
- [x] Auto-downgrade запрещён
- [x] Автообновление без клика — запрещено
- [x] **CP1:** обновление по кнопкам — только ATOL `frATOL54*` (история); в CP2 — любой модуль с id в канале

### CP1.5 — Скачивание TXT + SHA-256 + проверка заголовков

- [x] Unit `HttpDownload`: GET asset → `%ProgramData%\1C77KKTUpdater\cache\`
- [x] Unit `HashUtil`: SHA-256, сравнение с manifest (hex, case-insensitive)
- [x] При несовпадении SHA — отказ, ERT не трогать
- [x] Декодирование UTF-8 **без BOM** (норма)
- [x] CRLF-нормализация; строгий CP1251 (непредставимый символ → отказ)
- [x] В TXT: `component` и `version` == полям manifest, иначе отказ до backup

### CP1.6 — Проверка component до записи

- [x] Есть `component` и ≠ `1c77-atol-module` → отказ **до** backup/записи
- [x] Есть `component` и == ожидаемому → OK
- [x] Нет `component` → legacy OK **только** при маркере `//frATOL54` или `//frATOL54_comm ... ver:`
- [x] Произвольный `ver:` в чужой обработке → отказ

### CP1.7 — Backup (цикла обновления)

- [x] Unit `Backup`
- [x] Полная копия ERT **после** exclusive probe / re-read, **до** записи
- [x] Каталог: `%ProgramData%\1C77KKTUpdater\backup\`
- [x] Имя без коллизий (label + timestamp + original name)
- [x] Retention минимум 3–5 комплектов на instance
- [x] UI «Откатить» backup цикла обновления — не в CP1 (есть снимок рабочей конфигурации — дополнение)

### CP1.8 — Запись `MD Programm text`

- [x] Unit `UpdateErt` (оркестрация)
- [x] Exclusive open: `STGM_READWRITE | STGM_SHARE_EXCLUSIVE`
- [x] Под exclusive: повторное чтение + сверка prior version
- [x] Текст → CRLF → строгий CP1251 → raw DEFLATE → только поток `MD Programm text`
- [x] Запись: `Seek(0)` → `SetSize(new)` → `Write` → `Commit` stream → `Commit` storage
- [x] Остальные потоки ERT не трогать
- [x] Нет эксклюзивного доступа → сообщение закрыть 1С 7.7, запись не начинать

### CP1.9 — Verify + автоматический rollback

- [x] После записи: повторное чтение `component` + `version`
- [x] Успех только если `component == 1c77-atol-module` и `version == manifest.version`
- [x] Иначе: восстановить ERT из backup этого цикла + ошибка пользователю + запись в лог
- [x] Триггеры rollback: не читается / битый поток / inflate fail / нет заголовков / несовпадение / исключение после начала записи
- [x] «Обновить всё»: по очереди; сбой одного не откатывает уже успешный другой; итог — сводка
- [x] Пути в `config.json` после успеха не менять от содержимого manifest

Порядок на instance:

```text
precheck path + component identity
  → download TXT (если ещё нет в этом «Обновить»)
  → SHA-256
  → check TXT component/version + CRLF + strict CP1251
  → exclusive probe + re-read snapshot
  → backup именно этой версии
  → exclusive open + verify prior version + Seek(0)/SetSize/Write/Commit
  → re-read component+version
  → fail → rollback + error
  → ok → log success
```

### CP1.10 — Логи

- [x] Unit `AppLog`
- [x] `%ProgramData%\1C77KKTUpdater\logs\updater-YYYY-MM-DD.log`
- [x] Логировать: проверка, URL (без секретов), SHA, backup path, запись, verify, rollback, «файл занят»

### Критерий готовности CP1 (код)

- [x] На машине с двумя базами ATOL — строки модулей линейки
- [x] Обновление выбранного ATOL ERT по кнопке
- [x] После успеха `component` и `version` в ERT совпадают с manifest
- [x] При искусственной порче / ошибке проверки после записи — rollback
- [x] Backup и полный лог на месте
- [x] Пути в `config.json` не меняются от содержимого `stable.json`
- [x] Техтест ERT roundtrip зелёный
- [x] Нет auto-downgrade при локальной version новее

---

## Дополнения сессии (сверх исходного CP1)

### CP1+.A — Модули в UI (версии / пути) — как сделано в CP1

- [x] В таблице — полный набор модулей линейки (версия может отсутствовать — legacy)
- [x] **ATOL (Злобин/Стрелец):** `frATOL54_comm` (часто `ExtForms\Equip\`); также в **`ExtForms\`**:  
  `permissive_regime_2024`, `razresh_regim_check`, `razresh_regim_dialog_error`, `test_check`
- [x] **Штрих (Сургут):** `fr_elves-12`; также `fr_elves_test` (**не** `test_check`); в **`ExtForms\`**:  
  `permissive_regime_2024`, `razresh_regim_check`, `razresh_regim_dialog_error`  
  (в CP1 в companions ошибочно попал `module-form-of-check` — это код формы конфигурации, не ExtForms-обработка; вне updater)
- [x] **Исторически в CP1:** обновление по кнопкам — только ATOL `frATOL54*`; остальные строки — просмотр  
  → в CP2 ограничение **снимается**: все ERT равноправны, обновление по наличию id в `stable.json` (см. PLAN / CP2_TECH_PLAN)

### CP1+.B — Видимость полей путей (Titles)

- [x] Злобин **и** Стрелец есть, Сургута нет → скрыть Сургут (поля + строки грида)
- [x] Сургут есть, Злобина и Стрельца нет → скрыть ATOL
- [x] Иначе — показывать всё
- [x] «Найдена» = база в Titles; при старте и «Найти базы в реестре»

### CP1+.C — Снимок рабочей конфигурации

- [x] Unit `WorkingSnapshot`
- [x] Кнопки снимок / откат; `%ProgramData%\1C77KKTUpdater\snapshots\<label>\working\`
- [x] Строка грида → label ИБ (не один модуль); сохраняется весь набор ERT этой ИБ
- [x] В снимок: все модули линейки ИБ + **`1Cv7.MD`** (только архив)
- [x] При восстановлении: **никогда** не восстанавливать `1Cv7.MD`
- [x] Version в манифесте снимка может быть пустой
- [x] Подсказка в UI про полный набор файлов ИБ

### CP1+.D — Версия updater

- [x] Версия в заголовке окна (`FileVersion` / `AppVersion`)
- [x] `ProductVersion` в `.dproj` синхронен с `FileVersion`

### Критерий готовности дополнений

- [x] ATOL-only ПК — без полей Сургута; Штрих-only — без полей ATOL
- [x] Снимок = полный набор ERT + MD; откат = только ERT
- [x] В заголовке видна версия updater

---

## Порядок реализации

- [x] **CP0.1** — consts + ProgramData bootstrap
- [x] **CP0.2** — Config load/save + schema
- [x] **CP0.3** — RegistryBases + маппинг labels
- [x] **CP0.4** — UI выбора path / save config
- [x] **CP1.0** — техтест ERT roundtrip (`tests/ErtRoundtripTest.dpr`)
- [x] **CP1.1** — `stable.json` (боевой) + `stable.example.json`
- [x] **CP1.2** — Manifest HTTPS + parse
- [x] **CP1.3** — ErtStorage / Codec + VersionParse
- [x] **CP1.4** — UI таблица + «Проверить»
- [x] **CP1.5** — Download + SHA + TXT header check
- [x] **CP1.6** — component gate до записи (строгий legacy)
- [x] **CP1.7** — Backup после exclusive probe
- [x] **CP1.8** — write stream (Seek/SetSize)
- [x] **CP1.9** — post-verify + rollback
- [x] **CP1.10** — «Обновить выбранное/всё» + логи + занятый файл + no-downgrade
- [x] **CP1+.A–D** — набор модулей в гриде, видимость, снимок, версия exe
- [x] **CP1.11** — прогон тест-плана на машине с двумя ИБ (ручной)

---

## Тест-план CP1 (ручной) — закрыт

- [x] Две базы ATOL в Titles → строки после настройки path (все модули линейки)
- [x] «Проверить» → «Установлено» из ERT, «Доступно» из manifest
- [x] Legacy ERT только с `//frATOL54_comm ver:` → обновление допускается; после — есть `component` + новая `version`
- [x] Чужой ERT с чужим `ver:` (без ATOL-маркера) → отказ до записи
- [x] Чужой ERT с другим `component` → отказ до записи
- [x] Успешное обновление выбранного; второй instance без изменений
- [x] «Обновить всё» — оба ATOL обновлены
- [x] Локальная version новее channel → «локальная версия новее», без записи
- [x] Неверный SHA / битый TXT / Unicode вне CP1251 → ERT не изменён
- [x] Провал verify после записи → rollback, файл = backup
- [x] ERT открыт в 1С → сообщение «занят»
- [x] Paths в `config.json` не изменились от `stable.json`
- [x] Лог и backup на месте в ProgramData
- [x] `tests/ErtRoundtripTest` — long/short write, side-stream SHA неизменен
- [x] ATOL-only / Штрих-only → корректная видимость полей
- [x] Снимок ИБ → полный набор ERT + MD; откат → только ERT, MD на месте

---

## Unit’ы

| Unit | Ответственность | Этап |
|---|---|---|
| `AppConsts` | URL, ProgramData, component id, labels, ERT names, legacy marker, `AppVersion` | CP0 |
| `AppPaths` | bootstrap dirs (logs/backup/cache/snapshots) | CP0 |
| `Config` | schema, load/save, instances | CP0 |
| `RegistryBases` | Titles, фильтры Злобин/Стрелец/Сургут, кандидаты ERT | CP0 |
| `kktUpdater1c77` | главная форма | CP0/CP1/+ |
| `Manifest` | HTTPS GET stable.json, parse | CP1 |
| `HttpDownload` | GET asset в cache | CP1 |
| `HashUtil` | SHA-256 | CP1 |
| `VersionParse` | component/version/legacy ATOL marker, compare | CP1 |
| `ErtStorage` | OLE open/read/write stream (Seek/SetSize) | CP1 |
| `ErtCodec` | raw DEFLATE ↔ CRLF + strict CP1251 | CP1 |
| `UpdateErt` | exclusive→backup→write→verify→rollback | CP1 |
| `Backup` | copy + retention (цикл обновления) | CP1 |
| `AppLog` | daily log | CP1 |
| `WorkingSnapshot` | снимок/откат рабочей конфигурации ИБ | CP1+ |
| `tests/ErtRoundtripTest` | техтест OLE roundtrip | CP1 |
