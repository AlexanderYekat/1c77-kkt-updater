unit AppPaths;

interface

function ProgramDataRoot: string;
function ConfigFilePath: string;
function LogsDir: string;
function BackupDir: string;
function CacheDir: string;
function SnapshotsDir: string;

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
  Result := TPath.Combine(Base, AppDataFolderName);
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

procedure EnsureAppDirectories;
begin
  ForceDirectories(ProgramDataRoot);
  ForceDirectories(LogsDir);
  ForceDirectories(BackupDir);
  ForceDirectories(CacheDir);
  ForceDirectories(SnapshotsDir);
end;

end.
