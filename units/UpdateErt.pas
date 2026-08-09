unit UpdateErt;

interface

uses
  Manifest;

type
  TUpdateErtResult = record
    Ok: Boolean;
    RolledBack: Boolean;
    Locked: Boolean;
    SkippedDowngrade: Boolean;
    Message: string;
    BackupPath: string;
    InstalledVersion: string;
  end;

function CheckComponentGate(const ModuleText, ExpectedComponentId: string;
  out ErrorMsg: string): Boolean;

function PrepareAssetText(const Comp: TComponentManifest; out ModuleText: string;
  out CachedFile: string; out ErrorMsg: string): Boolean;

function UpdateErtInstance(
  const ErtPath, InstanceLabel: string;
  const Comp: TComponentManifest;
  const PreparedText: string
): TUpdateErtResult;

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
  ModuleCatalog,
  ErtStorage,
  ErtCodec,
  Backup;

function CheckComponentGate(const ModuleText, ExpectedComponentId: string;
  out ErrorMsg: string): Boolean;
var
  Id: TModuleIdentity;
  LegacyVer: string;
  Entry: TModuleCatalogEntry;
  StemList: string;
  Stem: string;
begin
  Result := False;
  ErrorMsg := '';
  Id := ExtractModuleIdentity(ModuleText);
  if Id.HasComponent then
  begin
    if not SameText(Id.ComponentId, ExpectedComponentId) then
    begin
      ErrorMsg := Format(
        'Файл относится к другому component (%s), ожидается %s. Запись отменена.',
        [Id.ComponentId, ExpectedComponentId]
      );
      Exit;
    end;
    Result := True;
    Exit;
  end;

  // Legacy: только маркер своего stem (для 1c77-atol-module — frATOL54 / frATOL54_comm).
  // Произвольный чужой ver: — отказ.
  if not TryFindModuleById(ExpectedComponentId, Entry) then
  begin
    ErrorMsg :=
      'Неизвестный component id: ' + ExpectedComponentId + '. Запись отменена.';
    Exit;
  end;

  if HasAnyLegacyStemVerMarker(ModuleText, Entry.LegacyStems, LegacyVer) then
  begin
    Result := True;
    Exit;
  end;

  StemList := '';
  for Stem in Entry.LegacyStems do
  begin
    if StemList <> '' then
      StemList := StemList + ' / ';
    StemList := StemList + '//' + Stem + '[.ert] ver:';
  end;

  ErrorMsg := Format(
    'Не удалось подтвердить модуль %s: нет component: и нет legacy-маркера %s. Запись отменена.',
    [ExpectedComponentId, StemList]
  );
end;

function PrepareAssetText(const Comp: TComponentManifest; out ModuleText: string;
  out CachedFile: string; out ErrorMsg: string): Boolean;
var
  ActualSha: string;
  Bytes: TBytes;
  Id: TModuleIdentity;
  Encoded: TBytes;
  EncErr: string;
begin
  Result := False;
  ModuleText := '';
  CachedFile := '';
  ErrorMsg := '';
  EnsureAppDirectories;

  CachedFile := TPath.Combine(CacheDir, Comp.Asset);
  if not DownloadToFile(Comp.DownloadUrl, CachedFile, ErrorMsg) then
    Exit;

  ActualSha := Sha256HexOfFile(CachedFile);
  LogInfo('SHA-256 asset: ' + ActualSha + ' (ожидается ' + Comp.Sha256 + ')');
  if not SameSha256Hex(ActualSha, Comp.Sha256) then
  begin
    ErrorMsg := Format(
      'SHA-256 не совпал. Ожидалось %s, получено %s. ERT не будет изменён.',
      [Comp.Sha256, ActualSha]
    );
    LogError(ErrorMsg);
    Exit;
  end;

  Bytes := TFile.ReadAllBytes(CachedFile);
  ModuleText := NormalizeNewlinesToCrlf(Utf8BytesToStringWithoutBom(Bytes));
  Id := ExtractModuleIdentity(ModuleText);
  if not Id.HasComponent or not SameText(Id.ComponentId, Comp.Id) then
  begin
    ErrorMsg := Format(
      'В TXT нет ожидаемого component (%s).',
      [Comp.Id]
    );
    Exit;
  end;
  if not Id.HasVersion or not SameText(Id.VersionRaw, Comp.Version) then
  begin
    ErrorMsg := Format(
      'В TXT version=%s, в manifest=%s.',
      [Id.VersionRaw, Comp.Version]
    );
    Exit;
  end;

  // Ранний отказ, если Unicode не ляжет в CP1251
  if not EncodeModuleTextToCp1251(ModuleText, Encoded, EncErr) then
  begin
    ErrorMsg := EncErr;
    LogError(ErrorMsg);
    Exit;
  end;
  Result := True;
end;

function UpdateErtInstance(
  const ErtPath, InstanceLabel: string;
  const Comp: TComponentManifest;
  const PreparedText: string
): TUpdateErtResult;
var
  SoftText, SnapshotText: string;
  SoftId, SnapId, After: TModuleIdentity;
  GateErr, BakErr, RollErr: string;
  Wrote: Boolean;
  Normalized: string;
begin
  Result.Ok := False;
  Result.RolledBack := False;
  Result.Locked := False;
  Result.SkippedDowngrade := False;
  Result.Message := '';
  Result.BackupPath := '';
  Result.InstalledVersion := '';

  if Trim(ErtPath) = '' then
  begin
    Result.Message := 'Путь к ERT не задан (' + InstanceLabel + ')';
    Exit;
  end;
  if not TFile.Exists(ErtPath) then
  begin
    Result.Message := 'ERT не найден: ' + ErtPath;
    Exit;
  end;

  Normalized := NormalizeNewlinesToCrlf(PreparedText);

  // --- soft precheck ---
  try
    SoftText := ReadErtModuleText(ErtPath);
  except
    on E: EErtStorageError do
    begin
      Result.Locked := E.LockedByOther;
      Result.Message := E.Message;
      if Result.Locked then
        Result.Message :=
          'ERT занят (вероятно открыт в 1С 7.7). Закройте 1С и повторите: ' + ErtPath;
      LogError(Result.Message);
      Exit;
    end;
    on E: Exception do
    begin
      Result.Message := 'Не удалось прочитать ERT: ' + E.Message;
      LogError(Result.Message);
      Exit;
    end;
  end;

  if not CheckComponentGate(SoftText, Comp.Id, GateErr) then
  begin
    Result.Message := GateErr;
    LogWarn(GateErr);
    Exit;
  end;

  SoftId := ExtractModuleIdentity(SoftText);
  if SoftId.HasVersion and (CompareVersionStrings(SoftId.VersionRaw, Comp.Version) > 0) then
  begin
    Result.SkippedDowngrade := True;
    Result.InstalledVersion := SoftId.VersionRaw;
    Result.Message := Format(
      'Локальная версия новее (%s > %s). Автоматический downgrade запрещён.',
      [SoftId.VersionRaw, Comp.Version]
    );
    LogWarn(Result.Message);
    Exit;
  end;
  if SoftId.HasVersion and SameText(SoftId.VersionRaw, Comp.Version) then
  begin
    Result.Ok := True;
    Result.InstalledVersion := SoftId.VersionRaw;
    Result.Message := Format('%s уже актуален (%s).', [InstanceLabel, SoftId.VersionRaw]);
    Exit;
  end;

  // --- exclusive probe + re-read ---
  try
    SnapshotText := ReadErtModuleTextExclusive(ErtPath);
  except
    on E: EErtStorageError do
    begin
      Result.Locked := True;
      Result.Message :=
        'Нет эксклюзивного доступа к ERT. Закройте 1С 7.7 и повторите: ' + ErtPath;
      LogError(Result.Message + ' | ' + E.Message);
      Exit;
    end;
  end;

  if not CheckComponentGate(SnapshotText, Comp.Id, GateErr) then
  begin
    Result.Message := GateErr;
    LogWarn(GateErr);
    Exit;
  end;

  SnapId := ExtractModuleIdentity(SnapshotText);
  if SoftId.HasVersion and SnapId.HasVersion and
     (not SameText(SoftId.VersionRaw, SnapId.VersionRaw)) then
  begin
    Result.Message := Format(
      'ERT изменился между проверками (%s → %s). Повторите обновление.',
      [SoftId.VersionRaw, SnapId.VersionRaw]
    );
    LogWarn(Result.Message);
    Exit;
  end;

  if SnapId.HasVersion and (CompareVersionStrings(SnapId.VersionRaw, Comp.Version) > 0) then
  begin
    Result.SkippedDowngrade := True;
    Result.InstalledVersion := SnapId.VersionRaw;
    Result.Message := Format(
      'Локальная версия новее (%s > %s). Автоматический downgrade запрещён.',
      [SnapId.VersionRaw, Comp.Version]
    );
    LogWarn(Result.Message);
    Exit;
  end;

  // --- backup именно этой версии файла (после подтверждения exclusive) ---
  if not BackupErtFile(ErtPath, InstanceLabel, Result.BackupPath, BakErr) then
  begin
    Result.Message := 'Backup не создан, запись отменена: ' + BakErr;
    Exit;
  end;

  Wrote := False;
  try
    try
      WriteErtModuleTextInPlace(
        ErtPath,
        Normalized,
        SnapId.VersionRaw,
        Comp.Id
      );
      Wrote := True;
      LogInfo('Записан MD Programm text: ' + ErtPath);
    except
      on E: EErtStorageError do
      begin
        Result.Locked := E.LockedByOther;
        Result.Message := E.Message;
        if Result.Locked then
          Result.Message :=
            'ERT занят (вероятно открыт в 1С 7.7). Закройте 1С и повторите: ' + ErtPath;
        LogError(Result.Message);
        Exit;
      end;
    end;

    After := ExtractModuleIdentity(ReadErtModuleText(ErtPath));
    if (not After.HasComponent) or (not SameText(After.ComponentId, Comp.Id)) or
       (not After.HasVersion) or (not SameText(After.VersionRaw, Comp.Version)) then
    begin
      Result.Message := Format(
        'Проверка после записи не пройдена (component=%s version=%s). Выполняется rollback.',
        [After.ComponentId, After.VersionRaw]
      );
      LogError(Result.Message);
      if RestoreErtFromBackup(Result.BackupPath, ErtPath, RollErr) then
      begin
        Result.RolledBack := True;
        Result.Message := Result.Message + ' Rollback выполнен.';
      end
      else
        Result.Message := Result.Message + ' Rollback ОШИБКА: ' + RollErr;
      Exit;
    end;

    Result.Ok := True;
    Result.InstalledVersion := After.VersionRaw;
    Result.Message := Format('Обновлено %s → %s', [InstanceLabel, After.VersionRaw]);
    LogInfo(Result.Message);
  except
    on E: Exception do
    begin
      Result.Message := 'Ошибка обновления: ' + E.Message;
      LogError(Result.Message);
      if Wrote then
      begin
        if RestoreErtFromBackup(Result.BackupPath, ErtPath, RollErr) then
        begin
          Result.RolledBack := True;
          Result.Message := Result.Message + ' Rollback выполнен.';
        end
        else
          Result.Message := Result.Message + ' Rollback ОШИБКА: ' + RollErr;
      end;
    end;
  end;
end;

end.
