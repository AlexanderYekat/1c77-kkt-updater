unit ZipUtil;

interface

type
  TZipEntryInfo = record
    RelativePath: string; // внутри архива, с '/'
    LocalPath: string;    // после unpack
  end;

function IsDeniedPackageFileName(const FileName: string): Boolean;
/// Безопасная распаковка ZIP в DestDir + deny-list + ожидаемый exe.
function SafeUnpackServiceZip(const ZipPath, DestDir, ExpectedExeFileName: string;
  out Entries: TArray<TZipEntryInfo>; out ErrorMsg: string): Boolean;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Zip,
  System.Masks,
  System.Generics.Collections,
  AppLog;

function NormalizeZipEntryPath(const Raw: string): string;
begin
  Result := StringReplace(Trim(Raw), '\', '/', [rfReplaceAll]);
  while (Length(Result) > 0) and (Result[1] = '/') do
    Delete(Result, 1, 1);
end;

function IsDeniedPackageFileName(const FileName: string): Boolean;
var
  Name: string;
begin
  Name := TPath.GetFileName(FileName);
  if Name = '' then
    Exit(False);
  Result :=
    MatchesMask(Name, '*.ini') or
    MatchesMask(Name, '*.log') or
    SameText(Name, 'config.json') or
    MatchesMask(Name, 'settings.*');
end;

function PathHasDotDot(const Rel: string): Boolean;
var
  Parts: TArray<string>;
  P: string;
begin
  Parts := Rel.Replace('\', '/').Split(['/']);
  for P in Parts do
    if SameText(P, '..') then
      Exit(True);
  Result := False;
end;

function SafeUnpackServiceZip(const ZipPath, DestDir, ExpectedExeFileName: string;
  out Entries: TArray<TZipEntryInfo>; out ErrorMsg: string): Boolean;
var
  Zip: TZipFile;
  I: Integer;
  EntryName, Rel, DestRoot, FullLocal, LocalDir: string;
  FoundExe: Boolean;
  List: TList<TZipEntryInfo>;
  Info: TZipEntryInfo;
  Stream: TStream;
  FileStream: TFileStream;
begin
  Result := False;
  SetLength(Entries, 0);
  ErrorMsg := '';
  FoundExe := False;
  DestRoot := ExcludeTrailingPathDelimiter(ExpandFileName(DestDir));

  if not TFile.Exists(ZipPath) then
  begin
    ErrorMsg := 'ZIP не найден: ' + ZipPath;
    Exit;
  end;
  if Trim(ExpectedExeFileName) = '' then
  begin
    ErrorMsg := 'Ожидаемое имя exe пусто';
    Exit;
  end;

  ForceDirectories(DestRoot);
  List := TList<TZipEntryInfo>.Create;
  Zip := TZipFile.Create;
  try
    try
      Zip.Open(ZipPath, zmRead);
      for I := 0 to Zip.FileCount - 1 do
      begin
        EntryName := Zip.FileNames[I];
        Rel := NormalizeZipEntryPath(EntryName);
        if Rel = '' then
          Continue;
        if Rel[Length(Rel)] = '/' then
          Continue;

        if (Pos(':', Rel) > 0) or TPath.IsPathRooted(StringReplace(Rel, '/', PathDelim, [rfReplaceAll])) then
        begin
          ErrorMsg := 'В ZIP запрещён абсолютный путь: ' + EntryName;
          Exit;
        end;
        if PathHasDotDot(Rel) then
        begin
          ErrorMsg := 'В ZIP запрещён путь с .. : ' + EntryName;
          Exit;
        end;
        if IsDeniedPackageFileName(Rel) then
        begin
          ErrorMsg := 'В ZIP найден запрещённый клиентский файл (deny-list): ' + Rel;
          Exit;
        end;

        FullLocal := TPath.Combine(DestRoot,
          StringReplace(Rel, '/', PathDelim, [rfReplaceAll]));
        FullLocal := ExpandFileName(FullLocal);
        if not SameText(Copy(FullLocal, 1, Length(DestRoot)), DestRoot) then
        begin
          ErrorMsg := 'Распаковка выходит за temp: ' + Rel;
          Exit;
        end;
        if (Length(FullLocal) > Length(DestRoot)) and
           (FullLocal[Length(DestRoot) + 1] <> PathDelim) then
        begin
          ErrorMsg := 'Распаковка выходит за temp: ' + Rel;
          Exit;
        end;

        LocalDir := ExtractFilePath(FullLocal);
        ForceDirectories(LocalDir);
        Zip.Read(EntryName, Stream);
        try
          FileStream := TFileStream.Create(FullLocal, fmCreate);
          try
            FileStream.CopyFrom(Stream, 0);
          finally
            FileStream.Free;
          end;
        finally
          Stream.Free;
        end;

        if SameText(TPath.GetFileName(Rel), ExpectedExeFileName) then
          FoundExe := True;

        Info.RelativePath := Rel;
        Info.LocalPath := FullLocal;
        List.Add(Info);
      end;

      if not FoundExe then
      begin
        ErrorMsg := Format('В ZIP нет ожидаемого exe «%s»', [ExpectedExeFileName]);
        Exit;
      end;
      if List.Count = 0 then
      begin
        ErrorMsg := 'ZIP пуст';
        Exit;
      end;

      Entries := List.ToArray;
      Result := True;
      LogInfo(Format('ZIP unpack OK: %d file(s) → %s', [Length(Entries), DestRoot]));
    except
      on E: Exception do
      begin
        ErrorMsg := 'Ошибка распаковки ZIP: ' + E.Message;
        LogError(ErrorMsg);
      end;
    end;
  finally
    Zip.Free;
    List.Free;
  end;
end;

end.
