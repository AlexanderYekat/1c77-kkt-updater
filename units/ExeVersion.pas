unit ExeVersion;

interface

/// Читает ProductVersion / FileVersion из VERSIONINFO exe.
/// Предпочтение: ProductVersion при валидном каноне; иначе нормализованный FileVersion.
function ReadExeCanonVersion(const ExePath: string; out Version: string;
  out ErrorMsg: string): Boolean;
function ReadExeProductVersion(const ExePath: string; out ProductVersion: string): Boolean;
function ReadExeFileVersionRaw(const ExePath: string; out FileVersion: string): Boolean;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  VersionParse,
  AppLog;

function QueryVersionString(const ExePath, Key: string; out Value: string): Boolean;
var
  InfoSize, Dummy, Len: DWORD;
  Buffer: Pointer;
  TransPtr: Pointer;
  Lang, CodePage: Word;
  LangCode: string;
  P: Pointer;
  Query: string;
begin
  Result := False;
  Value := '';
  InfoSize := GetFileVersionInfoSize(PChar(ExePath), Dummy);
  if InfoSize = 0 then
    Exit;
  GetMem(Buffer, InfoSize);
  try
    if not GetFileVersionInfo(PChar(ExePath), 0, InfoSize, Buffer) then
      Exit;
    if not VerQueryValue(Buffer, '\VarFileInfo\Translation', TransPtr, Len) or
       (TransPtr = nil) or (Len < 4) then
      Exit;
    Lang := PWordArray(TransPtr)^[0];
    CodePage := PWordArray(TransPtr)^[1];
    LangCode := Format('%.4x%.4x', [Lang, CodePage]);
    Query := '\StringFileInfo\' + LangCode + '\' + Key;
    if VerQueryValue(Buffer, PChar(Query), P, Len) and (P <> nil) then
    begin
      Value := string(PChar(P));
      Result := Trim(Value) <> '';
    end;
  finally
    FreeMem(Buffer);
  end;
end;

function ReadExeFileVersionRaw(const ExePath: string; out FileVersion: string): Boolean;
var
  InfoSize, Dummy, Len: DWORD;
  Buffer: Pointer;
  Fixed: PVSFixedFileInfo;
begin
  Result := False;
  FileVersion := '';
  InfoSize := GetFileVersionInfoSize(PChar(ExePath), Dummy);
  if InfoSize = 0 then
    Exit;
  GetMem(Buffer, InfoSize);
  try
    if not GetFileVersionInfo(PChar(ExePath), 0, InfoSize, Buffer) then
      Exit;
    if VerQueryValue(Buffer, '\', Pointer(Fixed), Len) and (Fixed <> nil) then
    begin
      FileVersion := Format('%d.%d.%d.%d', [
        HiWord(Fixed.dwFileVersionMS),
        LoWord(Fixed.dwFileVersionMS),
        HiWord(Fixed.dwFileVersionLS),
        LoWord(Fixed.dwFileVersionLS)]);
      Result := True;
    end;
  finally
    FreeMem(Buffer);
  end;
end;

function ReadExeProductVersion(const ExePath: string; out ProductVersion: string): Boolean;
begin
  Result := QueryVersionString(ExePath, 'ProductVersion', ProductVersion);
end;

function ReadExeCanonVersion(const ExePath: string; out Version: string;
  out ErrorMsg: string): Boolean;
var
  Product, FileRaw, CanonFromFile: string;
  Key: TVersionKey;
begin
  Result := False;
  Version := '';
  ErrorMsg := '';
  if not FileExists(ExePath) then
  begin
    ErrorMsg := 'EXE не найден: ' + ExePath;
    Exit;
  end;

  Product := '';
  FileRaw := '';
  ReadExeProductVersion(ExePath, Product);
  ReadExeFileVersionRaw(ExePath, FileRaw);

  if (Product <> '') and ParseVersionKey(Product, Key) then
  begin
    Version := Product;
    if (FileRaw <> '') and NormalizeFileVersionToCanon(FileRaw, CanonFromFile) and
       (not SameText(CanonFromFile, Product)) then
      LogWarn(Format(
        'VERSIONINFO конфликт ProductVersion=%s vs FileVersion=%s (нормализовано %s); для UI берём ProductVersion',
        [Product, FileRaw, CanonFromFile]));
    Exit(True);
  end;

  if (FileRaw <> '') and NormalizeFileVersionToCanon(FileRaw, CanonFromFile) then
  begin
    if Product <> '' then
      LogWarn(Format(
        'ProductVersion=%s не канон; используем нормализованный FileVersion=%s → %s',
        [Product, FileRaw, CanonFromFile]));
    Version := CanonFromFile;
    Exit(True);
  end;

  ErrorMsg := Format(
    'Не удалось прочитать каноническую версию exe (ProductVersion=%s FileVersion=%s)',
    [Product, FileRaw]);
end;

end.
