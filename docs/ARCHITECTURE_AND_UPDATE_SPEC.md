# Architecture and Update Spec

Каноническое ТЗ системы обновления 1С 7.7 ↔ ККТ.

Разрозненные заметки (`задача-на-updater.txt`, `описание-как-обновлять.txt`, `описание-модуля-на-Delphi-для-1cv77.txt`, `много-програм-один-репозиторий.txt`, корневые `ТЗ.md` / `ТЗ.txt`) — справочник; требования — только здесь.

Отдельные задания по репозиториям — в их `PLAN.md` (не копировать весь этот документ).

---

## 1. Цель и границы

### Цель

Windows-программа **1C77 KKT Updater** (Delphi) для контроля версий и обновления компонентов системы взаимодействия 1С 7.7 с ККТ.

Updater обслуживает:

```text
1C77 KKT Updater
│
├── Модуль 1С 7.7 ATOL
├── Delphi-служба ATOL
├── Модуль 1С 7.7 Штрих
├── Delphi-служба Штрих
├── C# proxy-1c-fmuapi
└── сам Updater
```

### Границы

- Updater **не зависит от Git** на компьютере клиента (только HTTPS).
- Для **публичных** GitHub-репозиториев клиентский updater **не содержит** GitHub PAT/token.
- В MVP — **только по инициативе пользователя** («Проверить» → «Обновить»). Бесшумный auto-update касс запрещён.
- `sync_modules.py` и прочие dev-tools — инструменты разработчика; в клиентский `stable.json` **не входят**.
- Private GitHub с токеном в клиенте — вне scope.

---

## 2. Клиентский контекст

Базы зависят от линейки компонентов. Названия ищутся в реестре (подстрока в отображаемом названии ИБ).

### ATOL (`1c77-tspiot-atol`)

Две информационные базы:

| Маркер в названии | Смысл |
|---|---|
| **Злобин** | ИБ клиента (ATOL) |
| **Стрелец** | ИБ клиента (ATOL) |

### Штрих (`1c77-tspiot-shtrih`)

Одна информационная база:

| Маркер в названии | Смысл |
|---|---|
| **Сургут** | Единственная ИБ клиента (Штрих); в названии «Сургут», не Злобин/Стрелец |

Как в `installer_1cv77_extforms.iss` для Штрих: фильтр по подстроке «Сургут» (`TitleContainsSurgut`).

### Реестр

```text
HKCU\Software\1C\1Cv7\7.7\Titles
```

Имена значений — пути к ИБ, данные — отображаемые названия. Читать от того же пользователя Windows, под которым работает 1С.

Updater должен уметь:

1. перечислить базы из реестра;
2. отфильтровать по линейке: ATOL → Злобин и Стрелец; Штрих → Сургут;
3. найти каталог ИБ и предложить пути `ExtForms\`, `ExtForms\Equip\`;
4. сохранить выбранные пути в **локальном конфиге**.

Пути клиента **нельзя** хранить в GitHub `stable.json`.

### Несколько экземпляров одного компонента

Один `component id` типа `ert-module` может иметь **несколько установленных экземпляров ERT** на одном ПК.

Пример: `1c77-atol-module` стоит и в базе Злобин, и в базе Стрелец — это два независимых пути, две установленные версии, два состояния в UI.

Конфиг и UI **нельзя** моделировать как «один component id = один ERT».

---

## 3. Компоненты и постоянные ID

ID не меняются при переименовании exe/ert.

Каждый `.ert` модуля 1С — **отдельный** продукт `ert-module` (своя version, свой asset). Нет деления «главный / сопутствующий»: все модули линейки равноправны. Одинаковые имена файлов у ATOL и Штрих → **разные** id.

| ID | type | Файл / компонент | Репозиторий |
|---|---|---|---|
| `1c77-atol-module` | `ert-module` | `frATOL54_comm.ert` | `1c77-tspiot-atol` |
| `1c77-atol-permissive_regime_2024` | `ert-module` | `permissive_regime_2024.ert` | `1c77-tspiot-atol` |
| `1c77-atol-razresh_regim_check` | `ert-module` | `razresh_regim_check.ert` | `1c77-tspiot-atol` |
| `1c77-atol-razresh_regim_dialog_error` | `ert-module` | `razresh_regim_dialog_error.ert` | `1c77-tspiot-atol` |
| `1c77-atol-test_check` | `ert-module` | `test_check.ert` | `1c77-tspiot-atol` |
| `1c77-shtrih-module` | `ert-module` | `fr_elves-12.ert` | `1c77-tspiot-shtrih` |
| `1c77-shtrih-fr_elves_test` | `ert-module` | `fr_elves_test.ert` | `1c77-tspiot-shtrih` |
| `1c77-shtrih-permissive_regime_2024` | `ert-module` | `permissive_regime_2024.ert` | `1c77-tspiot-shtrih` |
| `1c77-shtrih-razresh_regim_check` | `ert-module` | `razresh_regim_check.ert` | `1c77-tspiot-shtrih` |
| `1c77-shtrih-razresh_regim_dialog_error` | `ert-module` | `razresh_regim_dialog_error.ert` | `1c77-tspiot-shtrih` |
| `atol-service` | `windows-service` | Delphi-приложение ATOL (процесс, не SCM) | `1c77-tspiot-atol` |
| `shtrih-service` | `windows-service` | Delphi-приложение Штрих (процесс, не SCM) | `1c77-tspiot-shtrih` |
| `fmuapi-proxy` | `windows-service` | C# proxy (Windows Service / SCM) | `proxy-1c-fmuapi` |
| `kkt-updater` | `updater-app` | Сам Updater | `1c77-kkt-updater` |

В одном репозитории (atol / shtrih) — **несколько** независимо версионируемых продуктов: каждый модуль ERT и отдельно service. Updater **не** опирается на «latest release» репозитория.

**Не входят в updater** (код конфигурации 1С, обновляется вручную): модуль формы чека (`module-form-of-check`), глобальный модуль конфигурации (`глобальный-модуль1cv77`). Это не внешние обработки `.ert` в `ExtForms`.

Алгоритм установки выбирается по полю **`type`**, не по разбору строки `id`.

---

## 4. Архитектура

### Источник истины

В репозитории `1c77-kkt-updater`:

```text
channels/
├── stable.json           // только реально разрешённые клиентам версии
├── stable.example.json   // пример полей (не канал клиентов)
└── beta.json             // не обязательно в MVP
```

`stable.json` **не** содержит фиктивных `download_url` / `sha256`. Пока Release нет — `components` может быть пустым; образец полей — в `stable.example.json`.

Updater загружает `stable.json` по HTTPS с **одного** URL (константа/настройка приложения; не строится из `component.repository`). Именно manifest говорит, какую версию каждого компонента ставить, откуда скачать asset и какой SHA-256.

Пример URL (может быть переопределён):

```text
https://raw.githubusercontent.com/AlexanderYekat/1c77-kkt-updater/main/channels/stable.json
```

`Release создан` ≠ `разрешён клиентам`. Клиенты видят обновление только после правки `stable.json`.

### Разделение ответственности

| Где | Что знает |
|---|---|
| `stable.json` | что устанавливать (`type`, `version`, `repository`, `tag`, `asset`, `sha256`, `requires`) |
| Локальный конфиг клиента | куда: список экземпляров (пути к ERT), пути exe, имена Windows service |

### Поток

```text
stable.json (HTTPS)
        │
        ▼
   Updater.exe
        │
        ├── ert-module: для каждого экземпляра ERT → backup → MD Programm text → проверить version
        │
        └── windows-service (Delphi app): ZIP preflight → stop process → journal/backup → replace → start exe → retry /version + /health
            (C# proxy / SCM — CP4)
```

---

## 5. Версионирование

Формат: `YYYY.MM.DD-NN` (пример: `2026.08.09-02`).

Сравнение — по четырём числовым полям `(YYYY, MM, DD, NN)`.

Чтение версии модуля 1С (как в `sync_modules.py`):

1. новый заголовок `// component:` + `// version:`;
2. старый комментарий `ver: YYYY.MM.DD-NN`;
3. при необходимости — `глЭтотМодульВерсияМодуля = "..."`.

Новые релизы модулей:

```1c
// component: 1c77-atol-module
// version: 2026.08.10-01
```

---

## 6. Формат `stable.json`

`schema_version: 1`.

Обязательные поля каждого компонента:

```text
id
type                 // ert-module | windows-service | updater-app
version
repository           // например AlexanderYekat/1c77-tspiot-atol  (не "repo")
tag
asset
download_url
sha256
```

Дополнительно: `min_updater_version`, `requires`, `release_notes_url`.

Пример:

```json
{
  "schema_version": 1,
  "components": {
    "1c77-atol-module": {
      "id": "1c77-atol-module",
      "type": "ert-module",
      "version": "2026.08.10-01",
      "repository": "AlexanderYekat/1c77-tspiot-atol",
      "tag": "module-2026.08.10-01",
      "asset": "1c77-atol-module-2026.08.10-01.txt",
      "download_url": "https://github.com/.../download/...",
      "sha256": "...",
      "requires": {
        "atol-service": ">= 2026.08.09-02"
      }
    },
    "atol-service": {
      "id": "atol-service",
      "type": "windows-service",
      "version": "2026.08.09-02",
      "repository": "AlexanderYekat/1c77-tspiot-atol",
      "tag": "service-2026.08.09-02",
      "asset": "atol-service-2026.08.09-02.zip",
      "download_url": "https://github.com/.../download/...",
      "sha256": "..."
    }
  }
}
```

Зависимости: updater не ставит несовместимый набор; предлагает обновить связанные компоненты одной операцией.

---

## 7. Обновление модуля ERT (`type: ert-module`)

Скачивается **не весь ERT**, а текст модуля (TXT).

### Кодировки (норма)

| Где | Кодировка |
|---|---|
| Release asset TXT на GitHub | **UTF-8 без BOM** |
| Текст модуля внутри ERT | **Windows-1251** |

Перед записью в ERT:

1. нормализовать переводы строк в **CRLF**;
2. кодировать в Windows-1251 **строго** (`WC_NO_BEST_FIT_CHARS`): если символ непредставим — **ошибка**, без подстановки `?`.

### Технология

1. открыть `.ert` как OLE Compound Storage (`IStorage` / `IStream`);
2. поток `MD Programm text`;
3. raw DEFLATE (`windowBits = -15`);
4. после inflate — Windows-1251.

Запись потока (обязательный порядок):

```text
Seek(0) → SetSize(new compressed size) → Write(...) → Commit stream → Commit storage
```

Иначе при укорочении сжатых данных возможен хвост старого потока.

Пайплайн на каждый экземпляр ERT:

```text
скачать UTF-8 без BOM TXT
  → SHA-256
  → проверка component/version в TXT
  → CRLF + строгая проверка CP1251
  → soft precheck path + component identity
  → проверить эксклюзивный доступ (open exclusive + re-read)
  → повторная проверка identity / version snapshot
  → backup именно этой версии файла
  → exclusive open → сверка prior version → Seek(0)/SetSize/Write/Commit
  → повторное чтение: component + version
  → при ошибке чтения или несовпадении → авто-rollback из backup
```

Legacy без `component:`: **не** принимать любой `ver:`. Только маркер **своего** stem файла:  
`//<stem>` или `//<stem>.ert` … `ver: YYYY.MM.DD-NN`  
(например `//fr_elves-12.ert ver:…`, `//permissive_regime_2024 ver:…`).

Для `1c77-atol-module` legacy допускаются **оба** исторических stem: `frATOL54` и `frATOL54_comm`  
(например `//frATOL54_comm ver:…` или `//frATOL54 ver:…`). Произвольный чужой `ver:` по-прежнему запрещён.

Если локальная version **новее** channel — состояние «локальная версия новее», **без** автоматического downgrade.

Форма, реквизиты, таблица и прочие потоки ERT **не меняются**.

Нет эксклюзивного доступа — отказ: закрыть 1С 7.7.

После успешного обновления `component` в ERT обязан совпадать с ожидаемым id этого модуля (из таблицы §3).

---

## 8. Обновление `type: windows-service`

Для Delphi ATOL/Штрих (CP3) — это **приложение** (процесс). Для C# proxy (CP4) — Windows Service / SCM.

Канон бизнес-версии: `YYYY.MM.DD-NN` (из `GET /version` и `ProductVersion`).  
`FileVersion` в exe — четырёхчисловая форма Windows (`2026.8.9.1`); как fallback нормализуется в канон (`2026.08.09-01`).

HTTP:

- `GET /version` → `{ component, version }` (канон)
- `GET /health`

Контракт Release ZIP: **не содержит** клиентских конфигов; deny-list в updater — страховка.

Последовательность (детали и journal rollback — в техплане CP3):

```text
config.exe exists
  → download ZIP → SHA-256 → safe unpack + preflight (в т.ч. version exe == manifest)
  → stop process → journal/backup → replace → start exe
  → retry /version + /health
```

Delphi ATOL/Штрих — **приложение**, не Windows Service (никогда). SCM stop/start — для C# proxy (CP4).

Обычный auto-downgrade запрещён; явный аварийный откат канала (если появится в manifest) — отдельным решением, не «навсегда невозможно».

Сборка Delphi на первом этапе — **локально**. CI Delphi не блокирует updater. C# proxy — Actions по тегу `proxy-*`.

---

## 9. Локальный конфиг клиента

Файл:

```text
%ProgramData%\CTO_KSM\1C77KKTUpdater\config.json
```

JSON, `schema_version: 1`. Пользовательские пути **никогда** не перезаписываются из `stable.json`.

Для каждого `ert-module` — **список экземпляров** по ИБ, не один путь на id:

```text
1c77-atol-module:
  instances:
    - label: Злобин
      path: C:\...\Злобин\ExtForms\Equip\frATOL54_comm.ert
    - label: Стрелец
      path: C:\...\Стрелец\ExtForms\Equip\frATOL54_comm.ert

1c77-atol-permissive_regime_2024:
  instances:
    - label: Злобин
      path: C:\...\Злобин\ExtForms\permissive_regime_2024.ert
    - label: Стрелец
      path: C:\...\Стрелец\ExtForms\permissive_regime_2024.ert

1c77-shtrih-module:
  instances:
    - label: Сургут
      path: C:\...\Сургут\ExtForms\fr_elves-12.ert

1c77-shtrih-permissive_regime_2024:
  instances:
    - label: Сургут
      path: C:\...\Сургут\ExtForms\permissive_regime_2024.ert

atol-service:
  exe: ...
  base_url: ...
```

Пути — вручную и/или из реестра (поиск по известным именам в `ExtForms\` / `ExtForms\Equip\`).

---

## 10. Интерфейс (MVP)

Каждый модуль × каждая ИБ — **отдельная строка**. Обновляется любой модуль, у которого есть запись в `stable.json` (нет «просмотра по рангу файла»).

```text
ИБ / модуль                         Установлено      Доступно       Состояние
---------------------------------------------------------------------------
Злобин / frATOL54_comm              2026.08.06-03    2026.08.10-01  Обновление
Злобин / permissive_regime_2024     2026.07.29-01    2026.08.01-01  Обновление
Стрелец / frATOL54_comm             2026.08.12-01    2026.08.10-01  Локальная версия новее
Сургут / fr_elves-12                2026.07.26-01    2026.08.09-01  Обновление
Сургут / permissive_regime_2024     2026.07.29-01    —              Нет в канале
ATOL Service                        2026.08.09-02    2026.08.09-02  Актуально
...
```

Если локальная version **новее** channel — **не** предлагать и не выполнять automatic downgrade.

Желательно «Что нового». Автообновление без подтверждения — нет.

---

## 11. Логи, backup, безопасность

- Логи: `logs\updater-YYYY-MM-DD.log`.
- Backup: минимум 3–5 комплектов; позже UI «Откатить».
- Перед установкой — обязательный SHA-256.
- В перспективе: подпись `stable.json`, immutable releases.

---

## 12. Самообновление Updater (`type: updater-app`)

Скачать → `UpdateHelper` → выход → замена → запуск нового. MVP — CP6.

---

## 13. Release convention

### Теги

Для **каждого** независимого продукта — свой тег (в одном репозитории несколько ERT не могут делить один `module-*`):

```text
<component-id>-YYYY.MM.DD-NN
service-YYYY.MM.DD-NN
proxy-YYYY.MM.DD-NN
updater-YYYY.MM.DD-NN
```

Примеры ERT:

```text
1c77-atol-module-2026.08.09-01
1c77-atol-permissive_regime_2024-2026.08.09-01
1c77-shtrih-module-2026.08.09-01
1c77-shtrih-permissive_regime_2024-2026.08.09-01
```

Устаревшее общее `module-YYYY.MM.DD-NN` **не использовать** для новых релизов модулей.

### Assets

```text
<component-id>-YYYY.MM.DD-NN.txt        // UTF-8 без BOM; каждый ert-module отдельно
atol-service-YYYY.MM.DD-NN.zip
shtrih-service-YYYY.MM.DD-NN.zip
proxy-1c-fmuapi-YYYY.MM.DD-NN.zip
1c77-kkt-updater-YYYY.MM.DD-NN.zip
```

Примеры: `1c77-atol-module-….txt`, `1c77-atol-permissive_regime_2024-….txt`, `1c77-shtrih-module-….txt`.

В каждом Release: component id, version, notes, asset, SHA-256. Версия внутри артефакта == версия tag.

После теста — правка `channels/stable.json`.

Подробности по репо — `docs/release-convention.md` (можно вынести позже; пока норма — этот раздел).

---

## 14. Рабочий процесс

```text
изменили модуль/службу → commit → tag → GitHub Release (+ SHA-256)
  → тест → stable.json → клиент: Проверить → Обновить
```

---

## 15. Чекпоинты

Отмечать прогресс (`[x]` = сделано). Реализация по репозиториям — в их `PLAN.md`.

### CP0 — Подготовка

- [x] Spec принят; ID, `type`, формат версии зафиксированы
- [x] Чтение баз из реестра (как installer)
- [x] Сопоставление: ATOL — Злобин / Стрелец (два экземпляра); Штрих — Сургут (один)

### CP1 — MVP: пайплайн ERT (первый модуль ATOL)

- [x] Пайплайн для `ert-module`: HTTPS manifest, TXT UTF-8 без BOM, SHA-256, backup, `MD Programm text`, verify/rollback
- [x] UI / config: экземпляры Злобин / Стрелец; Проверить / Обновить
- [x] Ограничение «только `1c77-atol-module`» снято в CP2 (ручной прогон принят)

### CP2 — Все модули ERT ATOL + Штрих

- [x] Каждый `ert-module` из §3 — отдельный id в manifest; один пайплайн на всех
- [x] Линейка Штрих (Сургут) + остальные модули ATOL (не только `frATOL54_comm`)
- [x] Legacy gate по stem (`1c77-atol-module`: `frATOL54` и `frATOL54_comm`); «нет в канале» ≠ «модуль второго сорта»
- [x] `stable.json` / example: реальные публикации по id; asset UTF-8 без BOM
- [x] Код конфигурации (`module-form-of-check`, глобальный модуль) — вне scope updater

### CP3 — Delphi-приложения ККТ (ATOL + Штрих)

- [ ] ProductVersion (канон) + FileVersion + `/version` + `/health` в репах
- [x] Updater: ZIP deny-list; config `exe`/`base_url`; stop/start **процесса** (не SCM)
- [x] Updater: preflight → stop process → journal → replace → start → retry health
- [ ] Локальная сборка + release ZIP без клиентского ini

### CP4 — C# proxy

- [ ] metadata + `/version` + `/health`; tag `proxy-*`; Actions; **Windows Service / SCM**

### CP5 — Зависимости `requires`

- [ ] Разбор `requires`, запрет несовместимого набора, предложение обновить связанные

### CP6 — Самообновление Updater

- [ ] `updater-app`, UpdateHelper, Release `updater-*`

### CP7 — Release hygiene по репозиториям

- [ ] `1c77-tspiot-atol`:
  - каждый модуль ERT: `component` / `version` в тексте;
  - service: FileVersion/ProductVersion + `/version`;
  - теги релизов и asset на **каждый** component id; version == tag;
  - TXT asset: UTF-8 без BOM
- [ ] `1c77-tspiot-shtrih`: аналогично (все модули ERT + service)
- [ ] `proxy-1c-fmuapi`: Actions и теги
- [ ] `1c77-kkt-updater`: `stable.json` только после теста
- [ ] При необходимости вынести `docs/release-convention.md`

---

## 16. Порядок реализации

**CP0 → CP1 → CP2 → CP3 → CP4 → CP5 → CP6**, параллельно **CP7**.

Первый законченный результат:

```text
GitHub Release (TXT модуля, UTF-8 без BOM) → Updater → экземпляры ERT клиента
```

Не отдавать Cursor сразу весь scope: в каждом репозитории свой `PLAN.md` на текущий этап.

---

## 17. Где что лежит

| Путь | Назначение |
|---|---|
| `1c77-kkt-updater/docs/ARCHITECTURE_AND_UPDATE_SPEC.md` | Это ТЗ (канон) |
| `1c77-kkt-updater/PLAN.md` | Задание на реализацию updater (этапы) |
| `1c77-tspiot-atol/PLAN.md` | Только изменения ATOL под updater |
| `1c77-tspiot-shtrih/PLAN.md` | Только изменения Штрих |
| `proxy-1c-fmuapi/PLAN.md` | Только изменения proxy |
| `channels/stable.json` | Канал «разрешено клиентам» |

Корневая папка `1C77 Async Mark Check` может не быть Git-репозиторием: история архитектуры хранится в git `1c77-kkt-updater`.

### Справочник устаревших заметок

| Файл | Зачем |
|---|---|
| `*/описание-модуля-на-Delphi-для-1cv77.txt` | Примеры `IStorage` / zlib |
| `*/описание-как-обновлять.txt` | Ранняя схема latest Release |
| `*/много-програм-один-репозиторий.txt` | Независимые версии |
| `*/задача-на-updater.txt` | Исходная постановка баз |
| `sync_modules.py` | Dev TXT ↔ ERT |
