unit ErtStorage;

interface

uses
  System.SysUtils;

type
  EErtStorageError = class(Exception)
  public
    LockedByOther: Boolean;
  end;

  TErtStreamInfo = record
    Name: string;
    Size: Int64;
    Sha256Hex: string;
  end;

function ReadErtModuleText(const FileName: string): string;
/// Открывает ERT эксклюзивно, читает модуль, закрывает. Для precheck exclusive access.
function ReadErtModuleTextExclusive(const FileName: string): string;
/// Перед записью: exclusive open → повторное чтение → сверка prior version → Seek(0)/SetSize/Write/Commit.
procedure WriteErtModuleTextInPlace(
  const FileName, ModuleText: string;
  const ExpectedPriorVersion: string = '';
  const ExpectedComponentId: string = ''
);
function CollectErtStreamInfos(const FileName: string): TArray<TErtStreamInfo>;
function IsLikelyShareViolation(Code: HRESULT): Boolean;

implementation

uses
  Winapi.Windows,
  Winapi.ActiveX,
  System.Win.ComObj,
  System.Classes,
  AppConsts,
  ErtCodec,
  HashUtil,
  VersionParse;

function IsLikelyShareViolation(Code: HRESULT): Boolean;
const
  STG_E_SHAREVIOLATION_LOCAL = HRESULT($80030020);
  STG_E_LOCKVIOLATION_LOCAL = HRESULT($80030021);
begin
  Result :=
    (Code = STG_E_SHAREVIOLATION_LOCAL) or
    (Code = STG_E_LOCKVIOLATION_LOCAL) or
    (Code = HRESULT($80070020)) or
    (Code = HRESULT($80070021));
end;

procedure RaiseErt(const Msg: string; Code: HRESULT);
var
  E: EErtStorageError;
begin
  E := EErtStorageError.Create(Msg + Format(' (HRESULT=0x%x)', [Code]));
  E.LockedByOther := IsLikelyShareViolation(Code);
  raise E;
end;

function StatByteCount(const Stat: TStatStg): Int64;
begin
  Result := PInt64(@Stat.cbSize)^;
  if Result < 0 then
    Result := 0;
end;

function ReadStreamBytes(Stream: IStream): TBytes;
var
  Stat: TStatStg;
  Read: LongInt;
  ByteCount: Int64;
  MovePos: Int64;
  NewPos: UInt64;
begin
  FillChar(Stat, SizeOf(Stat), 0);
  OleCheck(Stream.Stat(Stat, STATFLAG_NONAME));
  ByteCount := StatByteCount(Stat);
  SetLength(Result, ByteCount);
  if Length(Result) = 0 then
    Exit;
  MovePos := 0;
  OleCheck(Stream.Seek(MovePos, STREAM_SEEK_SET, NewPos));
  OleCheck(Stream.Read(@Result[0], Length(Result), @Read));
  if Read <> Length(Result) then
    SetLength(Result, Read);
end;

procedure WriteStreamBytes(Stream: IStream; const Data: TBytes);
var
  MovePos: Int64;
  NewPos: UInt64;
  NewSize: UInt64;
  Written: LongInt;
begin
  // Норма: Seek(0) → SetSize(new) → Write → Commit stream
  MovePos := 0;
  OleCheck(Stream.Seek(MovePos, STREAM_SEEK_SET, NewPos));
  NewSize := Length(Data);
  OleCheck(Stream.SetSize(NewSize));
  MovePos := 0;
  OleCheck(Stream.Seek(MovePos, STREAM_SEEK_SET, NewPos));
  if Length(Data) > 0 then
  begin
    OleCheck(Stream.Write(@Data[0], Length(Data), @Written));
    if Written <> Length(Data) then
      raise EErtStorageError.CreateFmt(
        'Записано %d из %d байт потока MD Programm text', [Written, Length(Data)]);
  end;
  OleCheck(Stream.Commit(STGC_DEFAULT));
end;

function OpenStorage(const FileName: string; Mode: LongInt; out Storage: IStorage): HRESULT;
begin
  Result := StgOpenStorage(
    PWideChar(FileName),
    nil,
    Mode,
    nil,
    0,
    Storage
  );
end;

function DecodeProgrammStream(Stream: IStream): string;
var
  Compressed, Plain: TBytes;
begin
  Compressed := ReadStreamBytes(Stream);
  Plain := InflateRawDeflate(Compressed);
  Result := Cp1251BytesToString(Plain);
end;

function ReadErtModuleText(const FileName: string): string;
var
  Storage: IStorage;
  Stream: IStream;
  Hr: HRESULT;
begin
  if not FileExists(FileName) then
    raise EErtStorageError.Create('Файл не найден: ' + FileName);

  Hr := OpenStorage(FileName, STGM_READ or STGM_SHARE_DENY_WRITE, Storage);
  if Failed(Hr) then
    Hr := OpenStorage(FileName, STGM_READ or STGM_SHARE_EXCLUSIVE, Storage);
  if Failed(Hr) then
    RaiseErt('Не удалось открыть ERT для чтения: ' + FileName, Hr);

  Hr := Storage.OpenStream(
    PWideChar(ErtStreamProgrammText),
    nil,
    STGM_READ or STGM_SHARE_EXCLUSIVE,
    0,
    Stream
  );
  if Failed(Hr) then
    RaiseErt('Не удалось открыть поток "' + ErtStreamProgrammText + '"', Hr);

  Result := DecodeProgrammStream(Stream);
end;

function ReadErtModuleTextExclusive(const FileName: string): string;
var
  Storage: IStorage;
  Stream: IStream;
  Hr: HRESULT;
begin
  if not FileExists(FileName) then
    raise EErtStorageError.Create('Файл не найден: ' + FileName);

  Hr := OpenStorage(FileName, STGM_READ or STGM_SHARE_EXCLUSIVE, Storage);
  if Failed(Hr) then
    RaiseErt(
      'Нет эксклюзивного доступа к ERT. Закройте 1С 7.7 и повторите: ' + FileName,
      Hr
    );

  Hr := Storage.OpenStream(
    PWideChar(ErtStreamProgrammText),
    nil,
    STGM_READ or STGM_SHARE_EXCLUSIVE,
    0,
    Stream
  );
  if Failed(Hr) then
    RaiseErt('Не удалось открыть поток "' + ErtStreamProgrammText + '"', Hr);

  Result := DecodeProgrammStream(Stream);
  Stream := nil;
  Storage := nil; // release exclusive before caller does backup
end;

procedure WriteErtModuleTextInPlace(
  const FileName, ModuleText: string;
  const ExpectedPriorVersion: string;
  const ExpectedComponentId: string
);
var
  Storage: IStorage;
  Stream: IStream;
  Plain, Compressed: TBytes;
  Hr: HRESULT;
  CurrentText: string;
  Id: TModuleIdentity;
  EncErr: string;
  Normalized: string;
begin
  if not FileExists(FileName) then
    raise EErtStorageError.Create('Файл не найден: ' + FileName);

  Normalized := NormalizeNewlinesToCrlf(ModuleText);
  if not EncodeModuleTextToCp1251(Normalized, Plain, EncErr) then
    raise EErtStorageError.Create(EncErr);

  Hr := OpenStorage(FileName, STGM_READWRITE or STGM_SHARE_EXCLUSIVE, Storage);
  if Failed(Hr) then
    RaiseErt(
      'Не удалось открыть ERT для записи. Закройте 1С 7.7 и повторите: ' + FileName,
      Hr
    );

  Hr := Storage.OpenStream(
    PWideChar(ErtStreamProgrammText),
    nil,
    STGM_READWRITE or STGM_SHARE_EXCLUSIVE,
    0,
    Stream
  );
  if Failed(Hr) then
    RaiseErt('Не удалось открыть поток "' + ErtStreamProgrammText + '" для записи', Hr);

  // Повторная сверка исходника уже под exclusive lock
  CurrentText := DecodeProgrammStream(Stream);
  Id := ExtractModuleIdentity(CurrentText);
  if (ExpectedComponentId <> '') and Id.HasComponent and
     (not SameText(Id.ComponentId, ExpectedComponentId)) then
    raise EErtStorageError.CreateFmt(
      'Перед записью component изменился (%s), ожидался %s. Запись отменена.',
      [Id.ComponentId, ExpectedComponentId]
    );
  if (ExpectedPriorVersion <> '') and Id.HasVersion and
     (not SameText(Id.VersionRaw, ExpectedPriorVersion)) then
    raise EErtStorageError.CreateFmt(
      'Перед записью version изменилась (%s → %s). Запись отменена.',
      [ExpectedPriorVersion, Id.VersionRaw]
    );

  Compressed := DeflateRawDeflate(Plain);
  WriteStreamBytes(Stream, Compressed);
  OleCheck(Storage.Commit(STGC_DEFAULT));
end;

function CollectErtStreamInfos(const FileName: string): TArray<TErtStreamInfo>;
var
  Storage: IStorage;
  Enum: IEnumSTATSTG;
  Stat: TStatStg;
  Fetched: LongInt;
  Hr: HRESULT;
  Stream: IStream;
  Data: TBytes;
  Info: TErtStreamInfo;
  N: Integer;
begin
  SetLength(Result, 0);
  Hr := OpenStorage(FileName, STGM_READ or STGM_SHARE_DENY_WRITE, Storage);
  if Failed(Hr) then
    Hr := OpenStorage(FileName, STGM_READ or STGM_SHARE_EXCLUSIVE, Storage);
  if Failed(Hr) then
    RaiseErt('CollectErtStreamInfos: open failed', Hr);

  OleCheck(Storage.EnumElements(0, nil, 0, Enum));
  N := 0;
  while Enum.Next(1, Stat, @Fetched) = S_OK do
  begin
    try
      if Stat.dwType <> STGTY_STREAM then
        Continue;
      Info.Name := Stat.pwcsName;
      Info.Size := StatByteCount(Stat);
      Info.Sha256Hex := '';
      Hr := Storage.OpenStream(Stat.pwcsName, nil, STGM_READ or STGM_SHARE_EXCLUSIVE, 0, Stream);
      if Succeeded(Hr) then
      begin
        Data := ReadStreamBytes(Stream);
        Info.Size := Length(Data);
        Info.Sha256Hex := Sha256HexOfBytes(Data);
        Stream := nil;
      end;
      SetLength(Result, N + 1);
      Result[N] := Info;
      Inc(N);
    finally
      if Stat.pwcsName <> nil then
        CoTaskMemFree(Stat.pwcsName);
    end;
  end;
end;

end.
