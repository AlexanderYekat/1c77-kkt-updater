unit Backup;

interface

function BackupErtFile(const ErtPath, InstanceLabel: string; out BackupPath: string;
  out ErrorMsg: string): Boolean;
procedure TrimBackupRetention(const InstanceLabel: string; KeepCount: Integer);
function RestoreErtFromBackup(const BackupPath, ErtPath: string; out ErrorMsg: string): Boolean;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
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
    Result := 'instance';
end;

function BackupErtFile(const ErtPath, InstanceLabel: string; out BackupPath: string;
  out ErrorMsg: string): Boolean;
var
  Stamp, FileName, DestDir: string;
begin
  Result := False;
  BackupPath := '';
  ErrorMsg := '';
  try
    EnsureAppDirectories;
    if not TFile.Exists(ErtPath) then
    begin
      ErrorMsg := 'ERT не найден для backup: ' + ErtPath;
      Exit;
    end;
    Stamp := FormatDateTime('yyyymmdd_hhnnss_zzz', Now);
    DestDir := TPath.Combine(BackupDir, SafeToken(InstanceLabel));
    ForceDirectories(DestDir);
    FileName := Stamp + '_' + TPath.GetFileName(ErtPath);
    BackupPath := TPath.Combine(DestDir, FileName);
    TFile.Copy(ErtPath, BackupPath, True);
    LogInfo('Backup: ' + ErtPath + ' -> ' + BackupPath);
    TrimBackupRetention(InstanceLabel, BackupRetentionPerInstance);
    Result := True;
  except
    on E: Exception do
    begin
      ErrorMsg := E.Message;
      LogError('Backup failed: ' + ErrorMsg);
    end;
  end;
end;

procedure TrimBackupRetention(const InstanceLabel: string; KeepCount: Integer);
var
  Dir: string;
  Files: TArray<string>;
  I: Integer;
begin
  if KeepCount < 1 then
    KeepCount := BackupRetentionPerInstance;
  Dir := TPath.Combine(BackupDir, SafeToken(InstanceLabel));
  if not TDirectory.Exists(Dir) then
    Exit;
  Files := TDirectory.GetFiles(Dir, '*.*');
  if Length(Files) <= KeepCount then
    Exit;
  TArray.Sort<string>(Files, TComparer<string>.Construct(
    function(const L, R: string): Integer
    begin
      Result := CompareText(L, R); // timestamp prefix sorts chronologically
    end));
  for I := 0 to Length(Files) - KeepCount - 1 do
  begin
    try
      TFile.Delete(Files[I]);
      LogInfo('Backup retention delete: ' + Files[I]);
    except
      on E: Exception do
        LogWarn('Не удалось удалить старый backup: ' + E.Message);
    end;
  end;
end;

function RestoreErtFromBackup(const BackupPath, ErtPath: string; out ErrorMsg: string): Boolean;
begin
  Result := False;
  ErrorMsg := '';
  try
    if not TFile.Exists(BackupPath) then
    begin
      ErrorMsg := 'Backup не найден: ' + BackupPath;
      Exit;
    end;
    TFile.Copy(BackupPath, ErtPath, True);
    LogInfo('Rollback: ' + BackupPath + ' -> ' + ErtPath);
    Result := True;
  except
    on E: Exception do
    begin
      ErrorMsg := E.Message;
      LogError('Rollback failed: ' + ErrorMsg);
    end;
  end;
end;

end.
