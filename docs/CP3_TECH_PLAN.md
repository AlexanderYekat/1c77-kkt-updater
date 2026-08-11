# Технический план CP3 — Delphi-приложения ККТ (ATOL + Штрих)

Канон: [ARCHITECTURE_AND_UPDATE_SPEC.md](ARCHITECTURE_AND_UPDATE_SPEC.md).  
Задание: [../PLAN.md](../PLAN.md).  
База CP0–CP2: [CP0_CP1_TECH_PLAN.md](CP0_CP1_TECH_PLAN.md), [CP2_TECH_PLAN.md](CP2_TECH_PLAN.md).

Статус: **принят** (пайплайн = процесс, не Windows Service / SCM).

**Суть:** обновление уже установленного Delphi-приложения ККТ через ZIP из GitHub Release.  
Это **не** Inno-установщик, **не** Windows Service и не «переустановка с нуля».  
Настоящая Windows-служба (C# proxy) — **CP4**.

Не в scope: C# proxy (CP4), `requires` (CP5), self-update (CP6), первичная установка, `allow_downgrade`.

**База Delphi:** `ProjectkktUpdater1c77`.

---

## Как это работает (модель)

```text
Разработчик (репо atol / shtrih)
  собрал приложение локально
  → Git tag service-YYYY.MM.DD-NN
  → GitHub Release + asset atol-service-….zip (или shtrih-…)
     (ZIP НЕ содержит клиентских конфигов)
  → FileVersion / ProductVersion по контракту версий
  → посчитали SHA-256
  → (после теста) запись в channels/stable.json updater-репо

Клиент (updater)
  manifest + config (exe, base_url)
  → download ZIP → SHA-256
  → безопасный unpack в temp + preflight пакета (включая version exe)
  → stop process (WM_CLOSE → wait → Terminate) по полному пути config.exe
  → rollback journal + backup только заменяемых файлов
  → replace
  → start exe
  → retry GET /version + GET /health (до 30 с)
  → SUCCESS / иначе rollback по journal
```

### Что в релизе

| Да | Нет |
|---|---|
| ZIP: exe (+ dll / файлы программы) | Полный Inno Setup `.exe` |
| Тег `service-YYYY.MM.DD-NN` | Клиентские конфиги / секреты / пути кассы |
| `ProductVersion` = канон; `FileVersion` = четырёхчисловая | Windows Service / CreateService / SCM |

Первый раз ставит Inno / админ. Updater только **меняет файлы** уже известной установки.

### Откуда updater знает «куда класть»

```text
%ProgramData%\1C77KKTUpdater\config.json

atol-service:
  exe: C:\Program Files\CTO_KSM\kktserver\kktserverindyProject.exe
  base_url: http://127.0.0.1:2580

shtrih-service:
  exe: ...
  base_url: ...
```

### Разведка реп ATOL/Штрих

| | ATOL / Штрих |
|---|---|
| Exe | `kktserverindyProject.exe` |
| Типичный install | `{autopf}\CTO_KSM\kktserver\` |
| Клиентский конфиг | `%ProgramData%\CTO_KSM\kktserver\kktserverindy.ini` (вне каталога exe) |
| Модель | **приложение**; **никогда** Windows Service |
| HTTP | порт **2580**; `/health` есть; `/version` — контракт CP3.6 |

Deny-list: `*.ini`, `config.json`, `settings.*`, `*.log`.

---

## Границы

### В scope

- [x] Parse manifest `windows-service` (`atol-service`, `shtrih-service`)
- [x] UI + Проверить / Обновить
- [x] Пайплайн: preflight → stop process → journal → replace → start → health retry
- [x] Config: `exe`, `base_url`
- [x] `stable.example.json`
- [ ] Контракт реп (`/version`, ZIP без config)

### Вне scope

- C# proxy / SCM (CP4), `requires`, self-update, CreateService для Delphi, `allow_downgrade`

---

## Зафиксированные решения

- type `windows-service` — историческое имя; runtime = **процесс**
- Stop: WM_CLOSE → wait → TerminateProcess (image path = config.exe)
- Start: CreateProcess(exe); если процесс не был запущен — stop = OK
- Нет `service_name` / SCM / BinaryPath
- Auto-downgrade запрещён; `base_url` целиком; endpoints `/version`, `/health`

---

## Канонический пайплайн

```text
0. manifest + config (exe, base_url)
1. exe существует
2. download ZIP → SHA-256
3. safe unpack + deny-list + ожидаемый exe
4. version exe в ZIP == manifest
5. StopProcess
6. journal + backup
7. replace
8. StartProcess
9. retry /version + /health
10. SUCCESS
```

Ветки A/B/C (до replace / после replace / критический rollback) — как раньше, но start = exe, не SCM.

---

## Unit’ы

| Файл | Назначение |
|---|---|
| `ProcessControl` | stop/start процесса |
| `UpdateService` | оркестрация |
| `ZipUtil` / `ServiceHttp` / `ServiceRollbackJournal` / `ExeVersion` | preflight / HTTP / journal / VERSIONINFO |
| `Config` | exe / base_url |

`ServiceControl` (SCM) удалён — SCM только в CP4.
