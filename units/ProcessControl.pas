unit ProcessControl;

interface

/// Управление процессом Delphi-приложения ККТ (не Windows Service).
function IsProcessRunningForExe(const ExePath: string; out PidCount: Integer;
  out ErrorMsg: string): Boolean;
function StopProcessForExe(const ExePath: string; TimeoutMs: Integer;
  out ErrorMsg: string): Boolean;
function StartProcessExe(const ExePath: string; out ErrorMsg: string): Boolean;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  Winapi.Messages,
  Winapi.TlHelp32,
  AppLog;

const
  // В части SDK/Delphi-юнитов константа отсутствует
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

function NormalizeExePath(const Path: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(ExpandFileName(Trim(Path)));
end;

function SameExePath(const A, B: string): Boolean;
begin
  Result := SameText(NormalizeExePath(A), NormalizeExePath(B));
end;

function QueryProcessImagePath(Pid: DWORD; out ImagePath: string): Boolean;
type
  TQueryFullProcessImageName = function(hProcess: THandle; dwFlags: DWORD;
    lpExeName: LPWSTR; var lpdwSize: DWORD): BOOL; stdcall;
var
  H: THandle;
  Buf: array[0..4095] of Char;
  Len: DWORD;
  ModKernel: HMODULE;
  QueryFn: TQueryFullProcessImageName;
begin
  Result := False;
  ImagePath := '';
  H := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, Pid);
  if H = 0 then
    H := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, Pid);
  if H = 0 then
    Exit;
  try
    ModKernel := GetModuleHandle('kernel32.dll');
    if ModKernel <> 0 then
    begin
      @QueryFn := GetProcAddress(ModKernel, 'QueryFullProcessImageNameW');
      if Assigned(QueryFn) then
      begin
        Len := Length(Buf);
        if QueryFn(H, 0, Buf, Len) then
        begin
          SetString(ImagePath, Buf, Len);
          Exit(ImagePath <> '');
        end;
      end;
    end;
  finally
    CloseHandle(H);
  end;
end;

type
  TPidList = TArray<DWORD>;

function CollectPidsForExe(const ExePath: string; out Pids: TPidList;
  out ErrorMsg: string): Boolean;
var
  Snap: THandle;
  Pe: TProcessEntry32;
  WantName, Image: string;
  Pid: DWORD;
begin
  Result := False;
  SetLength(Pids, 0);
  ErrorMsg := '';
  WantName := TPath.GetFileName(ExePath);
  if WantName = '' then
  begin
    ErrorMsg := 'Имя exe пусто';
    Exit;
  end;

  Snap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snap = INVALID_HANDLE_VALUE then
  begin
    ErrorMsg := 'CreateToolhelp32Snapshot failed: ' + SysErrorMessage(GetLastError);
    Exit;
  end;
  try
    Pe.dwSize := SizeOf(Pe);
    if not Process32First(Snap, Pe) then
    begin
      ErrorMsg := 'Process32First failed: ' + SysErrorMessage(GetLastError);
      Exit;
    end;
    repeat
      if SameText(string(Pe.szExeFile), WantName) then
      begin
        Pid := Pe.th32ProcessID;
        if QueryProcessImagePath(Pid, Image) and SameExePath(Image, ExePath) then
        begin
          SetLength(Pids, Length(Pids) + 1);
          Pids[High(Pids)] := Pid;
        end;
      end;
    until not Process32Next(Snap, Pe);
    Result := True;
  finally
    CloseHandle(Snap);
  end;
end;

function IsProcessRunningForExe(const ExePath: string; out PidCount: Integer;
  out ErrorMsg: string): Boolean;
var
  Pids: TPidList;
begin
  PidCount := 0;
  Result := CollectPidsForExe(ExePath, Pids, ErrorMsg);
  if Result then
    PidCount := Length(Pids);
end;

type
  TCloseCtx = record
    Pid: DWORD;
  end;
  PCloseCtx = ^TCloseCtx;

function EnumCloseProc(Wnd: HWND; LParam: LPARAM): BOOL; stdcall;
var
  Ctx: PCloseCtx;
  WPid: DWORD;
begin
  Ctx := PCloseCtx(LParam);
  WPid := 0;
  GetWindowThreadProcessId(Wnd, WPid);
  if (WPid = Ctx.Pid) and IsWindowVisible(Wnd) then
    PostMessage(Wnd, WM_CLOSE, 0, 0);
  Result := True;
end;

procedure RequestCloseProcessWindows(Pid: DWORD);
var
  Ctx: TCloseCtx;
begin
  Ctx.Pid := Pid;
  EnumWindows(@EnumCloseProc, LPARAM(@Ctx));
end;

function WaitPidsExit(const Pids: TPidList; TimeoutMs: Integer): Boolean;
var
  Handles: array of THandle;
  I, N: Integer;
  Wait: DWORD;
begin
  N := 0;
  SetLength(Handles, Length(Pids));
  for I := 0 to High(Pids) do
  begin
    Handles[N] := OpenProcess(SYNCHRONIZE, False, Pids[I]);
    if Handles[N] <> 0 then
      Inc(N);
  end;
  if N = 0 then
    Exit(True);
  try
    Wait := WaitForMultipleObjects(N, @Handles[0], True, DWORD(TimeoutMs));
    Result := Wait <> WAIT_TIMEOUT;
  finally
    for I := 0 to N - 1 do
      CloseHandle(Handles[I]);
  end;
end;

function ForceTerminatePids(const Pids: TPidList; out ErrorMsg: string): Boolean;
var
  I: Integer;
  H: THandle;
  Failures: Integer;
begin
  Result := True;
  Failures := 0;
  ErrorMsg := '';
  for I := 0 to High(Pids) do
  begin
    H := OpenProcess(PROCESS_TERMINATE or SYNCHRONIZE, False, Pids[I]);
    if H = 0 then
    begin
      Inc(Failures);
      Continue;
    end;
    try
      if not TerminateProcess(H, 1) then
        Inc(Failures);
    finally
      CloseHandle(H);
    end;
  end;
  if Failures > 0 then
  begin
    Result := False;
    ErrorMsg := Format(
      'Не удалось принудительно завершить %d процесс(ов). Запустите updater от администратора.',
      [Failures]);
  end;
end;

function StopProcessForExe(const ExePath: string; TimeoutMs: Integer;
  out ErrorMsg: string): Boolean;
var
  Pids, Left: TPidList;
  SoftWait: Integer;
  I: Integer;
begin
  Result := False;
  ErrorMsg := '';
  if Trim(ExePath) = '' then
  begin
    ErrorMsg := 'exe не задан';
    Exit;
  end;
  if not CollectPidsForExe(ExePath, Pids, ErrorMsg) then
    Exit;
  if Length(Pids) = 0 then
  begin
    LogInfo('Процесс не запущен: ' + ExePath);
    Exit(True);
  end;

  LogInfo(Format('Остановка процесса %s (pid count=%d)', [ExePath, Length(Pids)]));
  for I := 0 to High(Pids) do
    RequestCloseProcessWindows(Pids[I]);

  SoftWait := TimeoutMs div 2;
  if SoftWait < 2000 then
    SoftWait := 2000;
  if WaitPidsExit(Pids, SoftWait) then
  begin
    LogInfo('Процесс завершён (WM_CLOSE): ' + ExePath);
    Exit(True);
  end;

  if not CollectPidsForExe(ExePath, Left, ErrorMsg) then
    Exit;
  if Length(Left) = 0 then
    Exit(True);

  LogWarn('Принудительное завершение: ' + ExePath);
  if not ForceTerminatePids(Left, ErrorMsg) then
    Exit;
  if not WaitPidsExit(Left, TimeoutMs - SoftWait) then
  begin
    if CollectPidsForExe(ExePath, Left, ErrorMsg) and (Length(Left) > 0) then
    begin
      ErrorMsg := Format(
        'Процесс не завершился за %d мс: %s (осталось pid=%d)',
        [TimeoutMs, ExePath, Length(Left)]);
      LogError(ErrorMsg);
      Exit;
    end;
  end;
  LogInfo('Процесс завершён (Terminate): ' + ExePath);
  Result := True;
end;

function StartProcessExe(const ExePath: string; out ErrorMsg: string): Boolean;
var
  Si: TStartupInfo;
  Pi: TProcessInformation;
  Dir, Cmd: string;
begin
  Result := False;
  ErrorMsg := '';
  if not TFile.Exists(ExePath) then
  begin
    ErrorMsg := 'EXE не найден для запуска: ' + ExePath;
    Exit;
  end;
  Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(ExePath));
  Cmd := '"' + ExePath + '"';
  UniqueString(Cmd);
  FillChar(Si, SizeOf(Si), 0);
  Si.cb := SizeOf(Si);
  FillChar(Pi, SizeOf(Pi), 0);
  if not CreateProcess(
    PChar(ExePath),
    PChar(Cmd),
    nil,
    nil,
    False,
    0,
    nil,
    PChar(Dir),
    Si,
    Pi
  ) then
  begin
    ErrorMsg := 'CreateProcess failed: ' + SysErrorMessage(GetLastError);
    LogError(ErrorMsg);
    Exit;
  end;
  CloseHandle(Pi.hThread);
  CloseHandle(Pi.hProcess);
  LogInfo('Процесс запущен: ' + ExePath);
  Result := True;
end;

end.
