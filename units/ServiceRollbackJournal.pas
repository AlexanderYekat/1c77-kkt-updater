unit ServiceRollbackJournal;

interface

uses
  System.Generics.Collections;

type
  TJournalEntry = record
    RelativePath: string;
    Existed: Boolean;
    BackupPath: string;
  end;

  TServiceJournal = record
    ComponentId: string;
    InstallDir: string;
    Stamp: string;
    JournalPath: string;
    BackupRoot: string;
    Entries: TArray<TJournalEntry>;
  end;

function BeginServiceJournal(const ComponentId, InstallDir: string;
  const RelativePaths: TArray<string>; out Journal: TServiceJournal;
  out ErrorMsg: string): Boolean;
function ApplyServiceReplace(const Journal: TServiceJournal;
  const TempRoot: string; out ErrorMsg: string): Boolean;
function RollbackServiceJournal(const Journal: TServiceJournal;
  out ErrorMsg: string): Boolean;
procedure ClearServiceJournalFile(const Journal: TServiceJournal);
procedure TrimServiceBackupRetention(const ComponentId: string; KeepCount: Integer);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Defaults,
  AppConsts,
  AppPaths,
  AppLog;

function SafeToken(const S: string): string;
var
  I: Integer;
  Ch: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    if CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) or
       (Ord(Ch) > 127) then
      Result := Result + Ch
    else
      Result := Result + '_';
  end;
  if Result = '' then
    Result := 'service';
end;

function ServiceBackupRoot(const ComponentId: string): string;
begin
  Result := TPath.Combine(BackupDir, 'services');
  Result := TPath.Combine(Result, SafeToken(ComponentId));
end;

procedure TrimServiceBackupRetention(const ComponentId: string; KeepCount: Integer);
var
  Dir: string;
  Dirs: TArray<string>;
  I: Integer;
begin
  if KeepCount < 1 then
    KeepCount := ServiceBackupRetention;
  Dir := ServiceBackupRoot(ComponentId);
  if not TDirectory.Exists(Dir) then
    Exit;
  Dirs := TDirectory.GetDirectories(Dir);
  if Length(Dirs) <= KeepCount then
    Exit;
  TArray.Sort<string>(Dirs, TComparer<string>.Construct(
    function(const L, R: string): Integer
    begin
      Result := CompareText(L, R);
    end));
  for I := 0 to Length(Dirs) - KeepCount - 1 do
  begin
    try
      TDirectory.Delete(Dirs[I], True);
      LogInfo('Service backup retention delete: ' + Dirs[I]);
    except
      on E: Exception do
        LogWarn('Не удалось удалить старый service backup: ' + E.Message);
    end;
  end;
end;

function RelToInstall(const InstallDir, Rel: string): string;
begin
  Result := TPath.Combine(
    ExcludeTrailingPathDelimiter(InstallDir),
    StringReplace(Rel, '/', PathDelim, [rfReplaceAll]));
end;

function SaveJournalJson(const Journal: TServiceJournal; out ErrorMsg: string): Boolean;
var
  Root, Obj: TJSONObject;
  Items: TJSONArray;
  E: TJournalEntry;
  Text: string;
begin
  Result := False;
  ErrorMsg := '';
  Root := TJSONObject.Create;
  try
    Root.AddPair('component_id', Journal.ComponentId);
    Root.AddPair('install_dir', Journal.InstallDir);
    Root.AddPair('stamp', Journal.Stamp);
    Items := TJSONArray.Create;
    Root.AddPair('entries', Items);
    for E in Journal.Entries do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('relative_path', E.RelativePath);
      Obj.AddPair('existed', TJSONBool.Create(E.Existed));
      if E.Existed then
        Obj.AddPair('backup_path', E.BackupPath)
      else
        Obj.AddPair('backup_path', TJSONNull.Create);
      Items.AddElement(Obj);
    end;
    Text := Root.Format(2);
    ForceDirectories(ExtractFilePath(Journal.JournalPath));
    TFile.WriteAllText(Journal.JournalPath, Text, TEncoding.UTF8);
    Result := True;
  except
    on Ex: Exception do
      ErrorMsg := Ex.Message;
  end;
  Root.Free;
end;

function BeginServiceJournal(const ComponentId, InstallDir: string;
  const RelativePaths: TArray<string>; out Journal: TServiceJournal;
  out ErrorMsg: string): Boolean;
var
  Stamp, BakRoot, Rel, Target, BakFile: string;
  I: Integer;
  Entry: TJournalEntry;
begin
  Result := False;
  ErrorMsg := '';
  Journal := Default(TServiceJournal);
  try
    EnsureAppDirectories;
    Stamp := FormatDateTime('yyyymmdd_hhnnss_zzz', Now);
    BakRoot := TPath.Combine(ServiceBackupRoot(ComponentId), Stamp);
    ForceDirectories(BakRoot);

    Journal.ComponentId := ComponentId;
    Journal.InstallDir := ExcludeTrailingPathDelimiter(InstallDir);
    Journal.Stamp := Stamp;
    Journal.BackupRoot := BakRoot;
    Journal.JournalPath := TPath.Combine(BakRoot, 'journal.json');
    SetLength(Journal.Entries, Length(RelativePaths));

    for I := 0 to High(RelativePaths) do
    begin
      Rel := RelativePaths[I];
      Target := RelToInstall(Journal.InstallDir, Rel);
      Entry.RelativePath := Rel;
      Entry.Existed := TFile.Exists(Target);
      Entry.BackupPath := '';
      if Entry.Existed then
      begin
        BakFile := TPath.Combine(BakRoot, StringReplace(Rel, '/', PathDelim, [rfReplaceAll]));
        ForceDirectories(ExtractFilePath(BakFile));
        TFile.Copy(Target, BakFile, True);
        Entry.BackupPath := BakFile;
      end;
      Journal.Entries[I] := Entry;
    end;

    if not SaveJournalJson(Journal, ErrorMsg) then
      Exit;

    LogInfo(Format('Service journal: %s (%d files)',
      [Journal.JournalPath, Length(Journal.Entries)]));
    Result := True;
  except
    on E: Exception do
    begin
      ErrorMsg := 'Не удалось создать journal/backup: ' + E.Message;
      LogError(ErrorMsg);
    end;
  end;
end;

function ApplyServiceReplace(const Journal: TServiceJournal;
  const TempRoot: string; out ErrorMsg: string): Boolean;
var
  E: TJournalEntry;
  Src, Dst: string;
begin
  Result := False;
  ErrorMsg := '';
  try
    for E in Journal.Entries do
    begin
      Src := TPath.Combine(
        ExcludeTrailingPathDelimiter(TempRoot),
        StringReplace(E.RelativePath, '/', PathDelim, [rfReplaceAll]));
      if not TFile.Exists(Src) then
      begin
        ErrorMsg := 'Нет файла в temp для replace: ' + E.RelativePath;
        Exit;
      end;
      Dst := RelToInstall(Journal.InstallDir, E.RelativePath);
      ForceDirectories(ExtractFilePath(Dst));
      TFile.Copy(Src, Dst, True);
      LogInfo('Replace: ' + Dst);
    end;
    Result := True;
  except
    on Ex: Exception do
    begin
      ErrorMsg := 'Ошибка replace: ' + Ex.Message;
      LogError(ErrorMsg);
    end;
  end;
end;

function RollbackServiceJournal(const Journal: TServiceJournal;
  out ErrorMsg: string): Boolean;
var
  E: TJournalEntry;
  Dst: string;
  Failures: TStringList;
begin
  Result := False;
  ErrorMsg := '';
  Failures := TStringList.Create;
  try
    for E in Journal.Entries do
    begin
      Dst := RelToInstall(Journal.InstallDir, E.RelativePath);
      try
        if E.Existed then
        begin
          if not TFile.Exists(E.BackupPath) then
          begin
            Failures.Add('нет backup: ' + E.RelativePath);
            Continue;
          end;
          ForceDirectories(ExtractFilePath(Dst));
          TFile.Copy(E.BackupPath, Dst, True);
          LogInfo('Rollback restore: ' + Dst);
        end
        else
        begin
          if TFile.Exists(Dst) then
          begin
            TFile.Delete(Dst);
            LogInfo('Rollback delete new: ' + Dst);
          end;
        end;
      except
        on Ex: Exception do
          Failures.Add(E.RelativePath + ': ' + Ex.Message);
      end;
    end;

    if Failures.Count > 0 then
    begin
      ErrorMsg := 'Rollback частично/полностью провален:'#13#10 + Failures.Text;
      LogError(ErrorMsg);
      Exit;
    end;
    Result := True;
    LogInfo('Service rollback OK: ' + Journal.ComponentId);
  finally
    Failures.Free;
  end;
end;

procedure ClearServiceJournalFile(const Journal: TServiceJournal);
begin
  // файл journal оставляем в backup-комплекте для аудита; retention чистит комплекты
  TrimServiceBackupRetention(Journal.ComponentId, ServiceBackupRetention);
end;

end.
