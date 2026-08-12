unit AppPaths;

interface

function ProgramDataRoot: string;
function ConfigFilePath: string;
function LogsDir: string;
function BackupDir: string;
function CacheDir: string;
function SnapshotsDir: string;

/// Путь exe по умолчанию — как DefaultDirName в installer_kktserver.iss
/// (Program Files\CTO_KSM\kktserver\kktserverindyProject.exe).
/// Если файл есть в Program Files или Program Files (x86) — возвращает найденный.
function DefaultServiceExePath: string;

procedure EnsureAppDirectories;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  AppConsts;

function ProgramDataRoot: string;
var
  Base: string;
begin
  Base := GetEnvironmentVariable('ProgramData');
  if Base = '' then
    Base := 'C:\ProgramData';
  // Как kktserver: %ProgramData%\CTO_KSM\<app>
  Result := TPath.Combine(TPath.Combine(Base, DefaultServiceVendorDir), AppDataFolderName);
end;

function ConfigFilePath: string;
begin
  Result := TPath.Combine(ProgramDataRoot, 'config.json');
end;

function LogsDir: string;
begin
  Result := TPath.Combine(ProgramDataRoot, 'logs');
end;

function BackupDir: string;
begin
  Result := TPath.Combine(ProgramDataRoot, 'backup');
end;

function CacheDir: string;
begin
  Result := TPath.Combine(ProgramDataRoot, 'cache');
end;

function SnapshotsDir: string;
begin
  Result := TPath.Combine(ProgramDataRoot, 'snapshots');
end;

function CombineServiceExe(const ProgramFilesRoot: string): string;
begin
  if Trim(ProgramFilesRoot) = '' then
    Exit('');
  Result := TPath.Combine(
    TPath.Combine(
      TPath.Combine(ProgramFilesRoot, DefaultServiceVendorDir),
      DefaultServiceAppDir),
    DefaultServiceExeFileName);
end;

function DefaultServiceExePath: string;
var
  Candidates: array[0..2] of string;
  I: Integer;
  Pf: string;
begin
  // Порядок как у 32-bit Inno autopf на x64: сначала ProgramFiles (= x86),
  // затем явный x86, затем ProgramW6432 (настоящий 64-bit PF).
  Pf := GetEnvironmentVariable('ProgramFiles');
  if Pf = '' then
    Pf := 'C:\Program Files';
  Candidates[0] := CombineServiceExe(Pf);
  Candidates[1] := CombineServiceExe(GetEnvironmentVariable('ProgramFiles(x86)'));
  Candidates[2] := CombineServiceExe(GetEnvironmentVariable('ProgramW6432'));

  for I := Low(Candidates) to High(Candidates) do
    if (Candidates[I] <> '') and TFile.Exists(Candidates[I]) then
      Exit(Candidates[I]);

  Result := Candidates[0];
end;

procedure EnsureAppDirectories;
begin
  ForceDirectories(ProgramDataRoot);
  ForceDirectories(LogsDir);
  ForceDirectories(BackupDir);
  ForceDirectories(CacheDir);
  ForceDirectories(SnapshotsDir);
end;

end.
