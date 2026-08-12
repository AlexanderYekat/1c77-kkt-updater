unit AppElevation;

interface

/// True, если процесс уже запущен с повышенными правами (UAC elevated).
function IsProcessElevated: Boolean;
/// Перезапуск текущего exe через UAC (runas). False — пользователь отказал / ошибка.
function RelaunchElevated(out ErrorMsg: string): Boolean;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Winapi.ShellAPI;

function IsProcessElevated: Boolean;
type
  TTokenElevationInfo = record
    TokenIsElevated: DWORD;
  end;
var
  Token: THandle;
  Elevation: TTokenElevationInfo;
  Size: DWORD;
begin
  Result := False;
  Token := 0;
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then
    Exit;
  try
    Size := 0;
    if GetTokenInformation(Token, TokenElevation, @Elevation, SizeOf(Elevation), Size) then
      Result := Elevation.TokenIsElevated <> 0;
  finally
    CloseHandle(Token);
  end;
end;

function RelaunchElevated(out ErrorMsg: string): Boolean;
var
  Exe, Params: string;
  Info: TShellExecuteInfo;
  I: Integer;
begin
  Result := False;
  ErrorMsg := '';
  Exe := ParamStr(0);
  Params := '';
  for I := 1 to ParamCount do
  begin
    if Params <> '' then
      Params := Params + ' ';
    if Pos(' ', ParamStr(I)) > 0 then
      Params := Params + '"' + ParamStr(I) + '"'
    else
      Params := Params + ParamStr(I);
  end;

  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  Info.lpVerb := 'runas';
  Info.lpFile := PChar(Exe);
  if Params <> '' then
    Info.lpParameters := PChar(Params);
  Info.nShow := SW_SHOWNORMAL;

  if ShellExecuteEx(@Info) then
    Exit(True);

  case GetLastError of
    ERROR_CANCELLED:
      ErrorMsg := 'Повышение прав отменено в UAC.';
  else
    ErrorMsg := 'Не удалось запросить права администратора: ' + SysErrorMessage(GetLastError);
  end;
end;

end.
