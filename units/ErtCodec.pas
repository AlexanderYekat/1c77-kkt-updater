unit ErtCodec;

interface

uses
  System.SysUtils;

function InflateRawDeflate(const Compressed: TBytes): TBytes;
function DeflateRawDeflate(const Plain: TBytes): TBytes;
function Cp1251BytesToString(const Data: TBytes): string;
function NormalizeNewlinesToCrlf(const S: string): string;
/// UTF-16 → CP1251 без подстановки "?". При непредставимом символе — False.
function EncodeModuleTextToCp1251(const S: string; out Bytes: TBytes;
  out ErrorMsg: string): Boolean;
function Utf8BytesToStringWithoutBom(const Data: TBytes): string;

implementation

uses
  Winapi.Windows,
  System.ZLib;

const
  RAW_WINDOW_BITS = -15;
  CHUNK = 65536;
  WC_NO_BEST_FIT_CHARS = $00000400;

function ZCheck(Code: Integer; const Op: string): Integer;
begin
  if Code <> Z_OK then
    raise Exception.CreateFmt('zlib %s failed: %d', [Op, Code]);
  Result := Code;
end;

function InflateRawDeflate(const Compressed: TBytes): TBytes;
var
  Stream: TZStreamRec;
  Ret: Integer;
  ChunkBuf: TBytes;
  Have: Integer;
  OutLen: Integer;
begin
  if Length(Compressed) = 0 then
    Exit(nil);

  FillChar(Stream, SizeOf(Stream), 0);
  Stream.next_in := @Compressed[0];
  Stream.avail_in := Length(Compressed);
  ZCheck(inflateInit2(Stream, RAW_WINDOW_BITS), 'inflateInit2');
  try
    SetLength(Result, 0);
    OutLen := 0;
    SetLength(ChunkBuf, CHUNK);
    repeat
      Stream.next_out := @ChunkBuf[0];
      Stream.avail_out := CHUNK;
      Ret := inflate(Stream, Z_NO_FLUSH);
      if (Ret <> Z_OK) and (Ret <> Z_STREAM_END) then
        raise Exception.CreateFmt('inflate failed: %d', [Ret]);
      Have := CHUNK - Integer(Stream.avail_out);
      if Have > 0 then
      begin
        SetLength(Result, OutLen + Have);
        Move(ChunkBuf[0], Result[OutLen], Have);
        Inc(OutLen, Have);
      end;
    until Ret = Z_STREAM_END;
  finally
    inflateEnd(Stream);
  end;
end;

function DeflateRawDeflate(const Plain: TBytes): TBytes;
var
  Stream: TZStreamRec;
  Ret: Integer;
  ChunkBuf: TBytes;
  Have: Integer;
  OutLen: Integer;
begin
  if Length(Plain) = 0 then
    Exit(nil);

  FillChar(Stream, SizeOf(Stream), 0);
  Stream.next_in := @Plain[0];
  Stream.avail_in := Length(Plain);
  ZCheck(deflateInit2(Stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, RAW_WINDOW_BITS, 8, Z_DEFAULT_STRATEGY),
    'deflateInit2');
  try
    SetLength(Result, 0);
    OutLen := 0;
    SetLength(ChunkBuf, CHUNK);
    repeat
      Stream.next_out := @ChunkBuf[0];
      Stream.avail_out := CHUNK;
      Ret := deflate(Stream, Z_FINISH);
      if (Ret <> Z_OK) and (Ret <> Z_STREAM_END) then
        raise Exception.CreateFmt('deflate failed: %d', [Ret]);
      Have := CHUNK - Integer(Stream.avail_out);
      if Have > 0 then
      begin
        SetLength(Result, OutLen + Have);
        Move(ChunkBuf[0], Result[OutLen], Have);
        Inc(OutLen, Have);
      end;
    until Ret = Z_STREAM_END;
  finally
    deflateEnd(Stream);
  end;
end;

function Cp1251BytesToString(const Data: TBytes): string;
var
  Enc: TEncoding;
begin
  Enc := TEncoding.GetEncoding(1251);
  try
    Result := Enc.GetString(Data);
  finally
    Enc.Free;
  end;
end;

function NormalizeNewlinesToCrlf(const S: string): string;
begin
  Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #10, #13#10, [rfReplaceAll]);
end;

function EncodeModuleTextToCp1251(const S: string; out Bytes: TBytes;
  out ErrorMsg: string): Boolean;
var
  Needed: Integer;
  UsedDefault: BOOL;
  I: Integer;
  Ch: Char;
  One: array[0..7] of AnsiChar;
  OneUsed: BOOL;
begin
  Result := False;
  SetLength(Bytes, 0);
  ErrorMsg := '';

  if S = '' then
  begin
    Result := True;
    Exit;
  end;

  // Сначала точечная диагностика: какой символ не мапится
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    if Ord(Ch) < 128 then
      Continue;
    UsedDefault := False;
    Needed := WideCharToMultiByte(1251, WC_NO_BEST_FIT_CHARS, @Ch, 1,
      @One[0], SizeOf(One), nil, @OneUsed);
    if (Needed <= 0) or OneUsed then
    begin
      ErrorMsg := Format(
        'Символ U+%0.4X (поз. %d) не представим в Windows-1251. Обновление отменено.',
        [Ord(Ch), I]
      );
      Exit;
    end;
  end;

  UsedDefault := False;
  Needed := WideCharToMultiByte(1251, WC_NO_BEST_FIT_CHARS, PChar(S), Length(S),
    nil, 0, nil, @UsedDefault);
  if (Needed <= 0) or UsedDefault then
  begin
    ErrorMsg := 'Текст модуля содержит символы, непредставимые в Windows-1251.';
    Exit;
  end;

  SetLength(Bytes, Needed);
  UsedDefault := False;
  Needed := WideCharToMultiByte(1251, WC_NO_BEST_FIT_CHARS, PChar(S), Length(S),
    PAnsiChar(@Bytes[0]), Length(Bytes), nil, @UsedDefault);
  if (Needed <= 0) or UsedDefault then
  begin
    ErrorMsg := 'Ошибка кодирования в Windows-1251.';
    SetLength(Bytes, 0);
    Exit;
  end;
  SetLength(Bytes, Needed);
  Result := True;
end;

function Utf8BytesToStringWithoutBom(const Data: TBytes): string;
var
  Offset: Integer;
begin
  Offset := 0;
  if (Length(Data) >= 3) and (Data[0] = $EF) and (Data[1] = $BB) and (Data[2] = $BF) then
    Offset := 3;
  if Offset = 0 then
    Result := TEncoding.UTF8.GetString(Data)
  else
    Result := TEncoding.UTF8.GetString(Data, Offset, Length(Data) - Offset);
end;

end.
