# PLAN: 1C77 KKT Updater — CP3 (Delphi-приложения ATOL + Штрих)

Канон: [docs/ARCHITECTURE_AND_UPDATE_SPEC.md](docs/ARCHITECTURE_AND_UPDATE_SPEC.md).  
Подробный техплан: [docs/CP3_TECH_PLAN.md](docs/CP3_TECH_PLAN.md).  
Готово ранее: [docs/CP0_CP1_TECH_PLAN.md](docs/CP0_CP1_TECH_PLAN.md), [docs/CP2_TECH_PLAN.md](docs/CP2_TECH_PLAN.md) (ERT ATOL+Штрих приняты).

Этот файл — **задание на updater для CP3**. Не трогать C# proxy (CP4), `requires` (CP5), самообновление updater (CP6). Репозитории ATOL/Штрих — только контракт приложения (версии, ZIP-asset, `/version` `/health`), не бизнес-логика ККТ.

Техплан CP3 принят. Код CP3: пайплайн процесса (не SCM).

---

## Главная идея

Обновление Delphi-приложения ККТ — **не полный установщик** и **не Windows Service** (никогда).  
C# proxy как настоящая Windows-служба — **CP4**.

В GitHub Release — **ZIP с бинарниками** (exe/dll). Клиентские конфиги в ZIP **не входят**. Deny-list в updater — страховка.

Первичная установка (Inno / вручную) — **вне** CP3. Updater обновляет уже установленное приложение.

```text
config (exe + base_url)
  → download ZIP → SHA
  → unpack temp + preflight (пути, exe, version пакета == manifest)
  → stop process (HTTP /exit → wait → WM_CLOSE → Terminate)
  → journal + backup заменяемых файлов
  → replace
  → start exe
  → retry /version + /health (до ~30 с)
  → при ошибке после replace: journal rollback
```

---

## Цель этапа

1. Пайплайн `type: windows-service` для **`atol-service`** и **`shtrih-service`** (имя type историческое; runtime = процесс).
2. UI: строки ATOL/Штрих; Проверить / Обновить выбранное / Обновить всё.
3. `config.json`: `exe`, `base_url` (целиком); пути не из `stable.json`.
4. Контракт с репами ATOL/Штрих: tag `service-*`, ZIP без клиентского конфига, версии exe, HTTP `/version` и `/health`.

---

## Component id

| ID | type | Asset | Репозиторий |
|---|---|---|---|
| `atol-service` | `windows-service` | `atol-service-YYYY.MM.DD-NN.zip` | `1c77-tspiot-atol` |
| `shtrih-service` | `windows-service` | `shtrih-service-YYYY.MM.DD-NN.zip` | `1c77-tspiot-shtrih` |

Тег: `service-YYYY.MM.DD-NN`.  
`fmuapi-proxy` — CP4 (настоящая Windows Service / SCM).

---

## Зафиксированные решения

- Алгоритм по `type`, не по id.
- Канон версии: `YYYY.MM.DD-NN` из `/version` и ProductVersion.  
  FileVersion Windows: `YYYY.M.D.N` → нормализация в канон как fallback.
- ATOL/Штрих **никогда не Windows Service** — stop/start процесса по полному пути `config.exe`.
- ZIP не содержит клиентских конфигов; deny-list — доп. страховка; hit → отказ до stop.
- Preflight пакета **до** остановки процесса (в т.ч. version exe в ZIP == manifest).
- Backup **после** остановки, только затронутые файлы; journal для удаления newly-added при rollback.
- После start: retry `/version`+`/health` (~1 с, макс ~30 с).
- Ветки ошибок: до replace / после replace / критический провал rollback — см. техплан.
- Обычный auto-downgrade запрещён; `allow_downgrade` — не CP3.
- `base_url` целиком; endpoints жёстко `/version`, `/health`.
- Сборка — локально; `requires` — CP5.

Типичный exe: `kktserverindyProject.exe` в `{autopf}\CTO_KSM\kktserver\`.

---

## Вне CP3

- C# proxy (SCM), `requires`, self-update, `allow_downgrade`
- Первая установка (Inno)
- Правки бизнес-логики ККТ (кроме контракта версий/health/ZIP)

---

## CP3 (чеклист)

- [x] Manifest: parse `windows-service`
- [x] `stable.example.json` — примеры service
- [x] Config: `exe`, `base_url` (без `service_name` / SCM)
- [x] UI: строки приложений + критическое состояние отката
- [x] Пайплайн: process stop/start + journal rollback
- [x] Лог: component id + exe + version + journal при сбое
- [ ] Ручной тест-план
- [ ] Контракт реп: `/version` + ZIP без ini

---

## Критерий готовности CP3

На ПК с установленным kktserver: строка в гриде; Проверить / Обновить / journal-rollback; клиентский ini на месте; плохой ZIP ловится до остановки процесса; ERT CP2 без регрессии.
