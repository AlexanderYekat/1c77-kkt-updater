program ErtRoundtripTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  Winapi.ActiveX,
  System.Win.ComObj,
  AppConsts in '..\units\AppConsts.pas',
  AppPaths in '..\units\AppPaths.pas',
  AppLog in '..\units\AppLog.pas',
  HashUtil in '..\units\HashUtil.pas',
  VersionParse in '..\units\VersionParse.pas',
  ErtCodec in '..\units\ErtCodec.pas',
  ErtStorage in '..\units\ErtStorage.pas';

function Fail(const Msg: string): Integer;
begin
  Writeln('FAIL: ', Msg);
  Result := 1;
end;

function StreamMap(const Infos: TArray<TErtStreamInfo>): TStringList;
var
  Info: TErtStreamInfo;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupError;
  for Info in Infos do
    if not SameText(Info.Name, ErtStreamProgrammText) then
      Result.Values[Info.Name] := Info.Sha256Hex + '|' + IntToStr(Info.Size);
end;

function SameOtherStreams(const A, B: TArray<TErtStreamInfo>): Boolean;
var
  MA, MB: TStringList;
  I: Integer;
begin
  MA := StreamMap(A);
  MB := StreamMap(B);
  try
    if MA.Count <> MB.Count then
      Exit(False);
    for I := 0 to MA.Count - 1 do
      if not SameText(MA.Names[I], MB.Names[I]) or
         not SameText(MA.ValueFromIndex[I], MB.ValueFromIndex[I]) then
        Exit(False);
    Result := True;
  finally
    MA.Free;
    MB.Free;
  end;
end;

procedure CreateMinimalErt(const FileName, OtherPayload, ModuleText: string);
var
  Storage: IStorage;
  Stream: IStream;
  Plain, Compressed, OtherBytes: TBytes;
  Pos: Largeint;
  Written: LongInt;
  EncErr: string;
begin
  if TFile.Exists(FileName) then
    TFile.Delete(FileName);

  OleCheck(StgCreateDocfile(
    PWideChar(FileName),
    STGM_READWRITE or STGM_SHARE_EXCLUSIVE or STGM_CREATE,
    0,
    Storage
  ));

  // side stream — должен остаться нетронутым после replace MD Programm text
  OleCheck(Storage.CreateStream(
    'SideMeta',
    STGM_READWRITE or STGM_SHARE_EXCLUSIVE or STGM_CREATE,
    0, 0, Stream
  ));
  OtherBytes := TEncoding.ANSI.GetBytes(OtherPayload);
  Pos := 0;
  OleCheck(Stream.Seek(Pos, STREAM_SEEK_SET, nil));
  OleCheck(Stream.SetSize(Length(OtherBytes)));
  OleCheck(Stream.Seek(Pos, STREAM_SEEK_SET, nil));
  if Length(OtherBytes) > 0 then
    OleCheck(Stream.Write(@OtherBytes[0], Length(OtherBytes), @Written));
  OleCheck(Stream.Commit(STGC_DEFAULT));
  Stream := nil;

  OleCheck(Storage.CreateStream(
    PWideChar(ErtStreamProgrammText),
    STGM_READWRITE or STGM_SHARE_EXCLUSIVE or STGM_CREATE,
    0, 0, Stream
  ));
  if not EncodeModuleTextToCp1251(NormalizeNewlinesToCrlf(ModuleText), Plain, EncErr) then
    raise Exception.Create(EncErr);
  Compressed := DeflateRawDeflate(Plain);
  Pos := 0;
  OleCheck(Stream.Seek(Pos, STREAM_SEEK_SET, nil));
  OleCheck(Stream.SetSize(Length(Compressed)));
  OleCheck(Stream.Seek(Pos, STREAM_SEEK_SET, nil));
  if Length(Compressed) > 0 then
    OleCheck(Stream.Write(@Compressed[0], Length(Compressed), @Written));
  OleCheck(Stream.Commit(STGC_DEFAULT));
  Stream := nil;
  OleCheck(Storage.Commit(STGC_DEFAULT));
end;

function MakeLongText: string;
var
  I: Integer;
begin
  Result :=
    '// component: 1c77-atol-module' + sLineBreak +
    '// version: 2026.08.10-01' + sLineBreak +
    '//frATOL54_comm ver: 2026.08.10-01' + sLineBreak;
  for I := 1 to 200 do
    Result := Result + Format('// pad line %d ABCDEFGHIJKLMNOPQRSTUVWXYZ', [I]) + sLineBreak;
  Result := Result + 'Процедура Тест() Экспорт Сообщить("длинный"); КонецПроцедуры' + sLineBreak;
end;

function MakeShortText: string;
begin
  Result :=
    '// component: 1c77-atol-module' + sLineBreak +
    '// version: 2026.08.10-02' + sLineBreak +
    '// short' + sLineBreak +
    'Процедура Тест() Экспорт Сообщить("короткий"); КонецПроцедуры' + sLineBreak;
end;

var
  Path: string;
  Text: string;
  Before, AfterLong, AfterShort: TArray<TErtStreamInfo>;
  ExitCode: Integer;
begin
  ExitCode := 0;
  CoInitialize(nil);
  try
    try
      Path := TPath.Combine(TPath.GetTempPath, 'ert_roundtrip_test.ert');
      Writeln('Fixture: ', Path);

      CreateMinimalErt(Path, 'SIDE-PAYLOAD-V1',
        '// component: 1c77-atol-module' + sLineBreak +
        '// version: 2026.08.09-01' + sLineBreak +
        'Процедура Тест() Экспорт Сообщить("старт"); КонецПроцедуры');

      Text := ReadErtModuleText(Path);
      if Pos('старт', Text) = 0 then
        Exit(Fail('initial read mismatch'));

      Before := CollectErtStreamInfos(Path);

      WriteErtModuleTextInPlace(Path, MakeLongText, '2026.08.09-01', ComponentAtolModule);
      Text := ReadErtModuleText(Path);
      if Pos('длинный', Text) = 0 then
        Exit(Fail('long write/read mismatch'));
      AfterLong := CollectErtStreamInfos(Path);
      if not SameOtherStreams(Before, AfterLong) then
        Exit(Fail('other OLE streams changed after LONG write'));

      WriteErtModuleTextInPlace(Path, MakeShortText, '2026.08.10-01', ComponentAtolModule);
      Text := ReadErtModuleText(Path);
      if Pos('короткий', Text) = 0 then
        Exit(Fail('short write/read mismatch'));
      if Pos('длинный', Text) > 0 then
        Exit(Fail('short write left long-text tail'));
      AfterShort := CollectErtStreamInfos(Path);
      if not SameOtherStreams(Before, AfterShort) then
        Exit(Fail('other OLE streams changed after SHORT write'));

      Writeln('OK: ERT roundtrip (long→short) + other streams intact');
      ExitCode := 0;
    except
      on E: Exception do
        ExitCode := Fail(E.Message);
    end;
  finally
    CoUninitialize;
  end;
  Halt(ExitCode);
end.
