unit UpdateService;

interface

uses
  Manifest,
  Config;

type
  TUpdateServiceResult = record
    Ok: Boolean;
    RolledBack: Boolean;
    CriticalRollbackFailed: Boolean;
    SkippedDowngrade: Boolean;
    Message: string;
    InstalledVersion: string;
  end;

/// Чтение установленной версии: HTTP /version, иначе Product/FileVersion exe.
function ReadInstalledServiceVersion(const Svc: TComponentConfig;
  const ComponentId: string; out Version: string; out ErrorMsg: string;
  PreferHttp: Boolean = True): Boolean;

/// Обновление Delphi-приложения ККТ (type windows-service в manifest; процесс, не SCM).
function UpdateWindowsService(
  const Comp: TComponentManifest;
  const Svc: TComponentConfig;
  ForceDowngrade: Boolean = False
): TUpdateServiceResult;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  AppConsts,
  AppPaths,
  AppLog,
  HashUtil,
  HttpDownload,
  VersionParse,
  ExeVersion,
  ProcessControl,
  ServiceHttp,
  ZipUtil,
  ServiceRollbackJournal;

function ReadInstalledServiceVersion(const Svc: TComponentConfig;
  const ComponentId: string; out Version: string; out ErrorMsg: string;
  PreferHttp: Boolean): Boolean;
var
  HttpErr, ExeErr: string;
begin
  Result := False;
  Version := '';
  ErrorMsg := '';
  HttpErr := '';
  ExeErr := '';

  if PreferHttp and (Trim(Svc.BaseUrl) <> '') then
  begin
    if GetServiceVersion(Svc.BaseUrl, ComponentId, Version, HttpErr) then
      Exit(True);
    LogInfo('HTTP /version недоступен, fallback FileVersion: ' + HttpErr);
  end;

  if Trim(Svc.Exe) = '' then
  begin
    ErrorMsg := 'exe не задан в config';
    Exit;
  end;
  if not ReadExeCanonVersion(Svc.Exe, Version, ExeErr) then
  begin
    ErrorMsg := ExeErr;
    if HttpErr <> '' then
      ErrorMsg := HttpErr + '; ' + ExeErr;
    Exit;
  end;
  Result := True;
end;

function CollectRelativePaths(const Entries: TArray<TZipEntryInfo>): TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(Entries));
  for I := 0 to High(Entries) do
    Result[I] := Entries[I].RelativePath;
end;

function TryRestartExe(const ExePath: string; out Err: string): Boolean;
begin
  Result := StartProcessExe(ExePath, Err);
end;

function UpdateWindowsService(
  const Comp: TComponentManifest;
  const Svc: TComponentConfig;
  ForceDowngrade: Boolean
): TUpdateServiceResult;
var
  Err, CachedZip, TempDir, InstallDir, ExpectedExe, ActualSha, PkgVer: string;
  LocalVer: string;
  Entries: TArray<TZipEntryInfo>;
  RelPaths: TArray<string>;
  Journal: TServiceJournal;
  Ei: Integer;
begin
  Result.Ok := False;
  Result.RolledBack := False;
  Result.CriticalRollbackFailed := False;
  Result.SkippedDowngrade := False;
  Result.Message := '';
  Result.InstalledVersion := '';
  TempDir := '';
  Journal := Default(TServiceJournal);

  if not Comp.IsValidWindowsService then
  begin
    Result.Message := 'Manifest: некорректный windows-service ' + Comp.Id;
    Exit;
  end;
  if Trim(Svc.Exe) = '' then
  begin
    Result.Message := 'config.exe не задан для ' + Comp.Id;
    Exit;
  end;
  if Trim(Svc.BaseUrl) = '' then
  begin
    Result.Message :=
      'config.base_url не задан для ' + Comp.Id +
      '. Укажите URL в поле base_url (например ' + DefaultServiceBaseUrl +
      ') и нажмите «Сохранить пути». Серый текст в поле — только подсказка, не значение.';
    Exit;
  end;
  if not TFile.Exists(Svc.Exe) then
  begin
    Result.Message := 'exe не найден: ' + Svc.Exe;
    Exit;
  end;

  InstallDir := ExcludeTrailingPathDelimiter(ExtractFilePath(Svc.Exe));
  ExpectedExe := TPath.GetFileName(Svc.Exe);
  LogInfo(Format('UpdateService %s exe=%s base_url=%s',
    [Comp.Id, Svc.Exe, Svc.BaseUrl]));

  // --- soft version / downgrade ---
  if ReadInstalledServiceVersion(Svc, Comp.Id, LocalVer, Err, True) then
  begin
    Result.InstalledVersion := LocalVer;
    if CompareVersionStrings(LocalVer, Comp.Version) > 0 then
    begin
      if not ForceDowngrade then
      begin
        Result.SkippedDowngrade := True;
        Result.Message := Format(
          'Локальная версия новее (%s > %s). Автоматический downgrade запрещён.',
          [LocalVer, Comp.Version]);
        LogWarn(Result.Message);
        Exit;
      end;
      LogWarn(Format('Принудительный downgrade %s: %s → %s',
        [Comp.Id, LocalVer, Comp.Version]));
    end
    else if SameText(LocalVer, Comp.Version) and (not ForceDowngrade) then
    begin
      Result.Ok := True;
      Result.Message := Format('%s уже актуален (%s).', [Comp.Id, LocalVer]);
      Exit;
    end;
  end
  else
    LogInfo('Локальная version не прочитана до обновления: ' + Err);

  // --- download + sha (до остановки процесса) ---
  EnsureAppDirectories;
  CachedZip := TPath.Combine(CacheDir, Comp.Asset);
  if not DownloadToFile(Comp.DownloadUrl, CachedZip, Err) then
  begin
    Result.Message := Err;
    Exit;
  end;
  ActualSha := Sha256HexOfFile(CachedZip);
  LogInfo('SHA-256 zip: ' + ActualSha + ' (ожидается ' + Comp.Sha256 + ')');
  if not SameSha256Hex(ActualSha, Comp.Sha256) then
  begin
    Result.Message := Format(
      'SHA-256 не совпал. Ожидалось %s, получено %s. Файлы не будут изменены.',
      [Comp.Sha256, ActualSha]);
    LogError(Result.Message);
    Exit;
  end;

  // --- unpack + preflight (до Stop) ---
  TempDir := TPath.Combine(CacheDir, 'svc_unpack_' + Comp.Id + '_' +
    FormatDateTime('hhnnsszzz', Now));
  if TDirectory.Exists(TempDir) then
    TDirectory.Delete(TempDir, True);
  ForceDirectories(TempDir);

  if not SafeUnpackServiceZip(CachedZip, TempDir, ExpectedExe, Entries, Err) then
  begin
    Result.Message := Err;
    Exit;
  end;

  PkgVer := '';
  Err := '';
  for Ei := 0 to High(Entries) do
    if SameText(TPath.GetFileName(Entries[Ei].RelativePath), ExpectedExe) then
    begin
      if not ReadExeCanonVersion(Entries[Ei].LocalPath, PkgVer, Err) then
        PkgVer := '';
      Break;
    end;
  if PkgVer = '' then
  begin
    Result.Message := 'Не удалось прочитать version exe из ZIP: ' + Err;
    Exit;
  end;
  if not SameText(PkgVer, Comp.Version) then
  begin
    Result.Message := Format(
      'version exe в ZIP (%s) != manifest (%s). Stop/replace не выполнялись.',
      [PkgVer, Comp.Version]);
    Exit;
  end;

  // --- Stop process ---
  if not StopProcessForExe(Svc.Exe, ServiceProcessWaitTimeoutMs, Err) then
  begin
    Result.Message := 'Не удалось остановить процесс, диск не изменён: ' + Err;
    Exit;
  end;

  // --- journal + backup ---
  RelPaths := CollectRelativePaths(Entries);
  if not BeginServiceJournal(Comp.Id, InstallDir, RelPaths, Journal, Err) then
  begin
    TryRestartExe(Svc.Exe, Err);
    Result.Message :=
      'Backup/journal не создан, replace отменён. Процесс запущен обратно. ' + Err;
    Exit;
  end;

  // --- replace ---
  if not ApplyServiceReplace(Journal, TempDir, Err) then
  begin
    if RollbackServiceJournal(Journal, Err) then
    begin
      Result.RolledBack := True;
      TryRestartExe(Svc.Exe, Err);
      Result.Message := 'Replace failed, выполнен rollback. ' + Err;
    end
    else
    begin
      Result.CriticalRollbackFailed := True;
      Result.Message :=
        'КРИТИЧЕСКАЯ ОШИБКА: обновление не удалось и автоматическое восстановление ' +
        'завершилось ошибкой. Процесс остановлен / состояние неизвестно. ' + Err;
      LogError(Result.Message + ' journal=' + Journal.JournalPath);
    end;
    Exit;
  end;

  // --- Start process ---
  if not StartProcessExe(Svc.Exe, Err) then
  begin
    if RollbackServiceJournal(Journal, Err) then
    begin
      Result.RolledBack := True;
      TryRestartExe(Svc.Exe, Err);
      Result.Message := 'Запуск exe не удался, выполнен rollback. ' + Err;
    end
    else
    begin
      Result.CriticalRollbackFailed := True;
      Result.Message :=
        'КРИТИЧЕСКАЯ ОШИБКА: запуск exe не удался, rollback тоже. ' + Err +
        ' journal=' + Journal.JournalPath;
    end;
    Exit;
  end;

  // --- verify ---
  // /version предпочтителен; при 404 (старые сборки) — FileVersion exe + /health
  if not WaitServiceVersionAndHealth(Svc.BaseUrl, Comp.Id, Comp.Version, Svc.Exe,
    ServiceHealthRetryIntervalMs, ServiceHealthRetryMaxMs, Err) then
  begin
    if not StopProcessForExe(Svc.Exe, ServiceProcessWaitTimeoutMs, Err) then
      LogWarn('Stop перед rollback verify: ' + Err);
    if RollbackServiceJournal(Journal, Err) then
    begin
      Result.RolledBack := True;
      TryRestartExe(Svc.Exe, Err);
      Result.Message := 'Проверка /version+/health не прошла, выполнен rollback. ' + Err;
    end
    else
    begin
      Result.CriticalRollbackFailed := True;
      Result.Message :=
        'КРИТИЧЕСКАЯ ОШИБКА: verify не прошёл и rollback failed. ' + Err +
        ' journal=' + Journal.JournalPath;
    end;
    Exit;
  end;

  ClearServiceJournalFile(Journal);
  Result.Ok := True;
  Result.InstalledVersion := Comp.Version;
  Result.Message := Format('%s обновлён → %s', [Comp.Id, Comp.Version]);
  LogInfo(Result.Message);

  if (TempDir <> '') and TDirectory.Exists(TempDir) then
    try
      TDirectory.Delete(TempDir, True);
    except
    end;
end;

end.
