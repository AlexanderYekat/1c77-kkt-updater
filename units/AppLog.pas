unit AppLog;

interface

procedure LogInfo(const Msg: string);
procedure LogWarn(const Msg: string);
procedure LogError(const Msg: string);

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  AppPaths;

var
  GLogLock: TCriticalSection;

function TodayLogPath: string;
begin
  Result := TPath.Combine(LogsDir, Format('updater-%s.log', [FormatDateTime('yyyy-mm-dd', Date)]));
end;

procedure WriteLine(const Level, Msg: string);
var
  Line: string;
  Stream: TFileStream;
  Bytes: TBytes;
  Encoding: TEncoding;
begin
  EnsureAppDirectories;
  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' [' + Level + '] ' + Msg + sLineBreak;
  Encoding := TEncoding.UTF8;
  Bytes := Encoding.GetBytes(Line);
  GLogLock.Enter;
  try
    if TFile.Exists(TodayLogPath) then
      Stream := TFileStream.Create(TodayLogPath, fmOpenReadWrite or fmShareDenyNone)
    else
      Stream := TFileStream.Create(TodayLogPath, fmCreate or fmShareDenyNone);
    try
      Stream.Seek(0, soEnd);
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
    finally
      Stream.Free;
    end;
  finally
    GLogLock.Leave;
  end;
end;

procedure LogInfo(const Msg: string);
begin
  WriteLine('INFO', Msg);
end;

procedure LogWarn(const Msg: string);
begin
  WriteLine('WARN', Msg);
end;

procedure LogError(const Msg: string);
begin
  WriteLine('ERROR', Msg);
end;

initialization
  GLogLock := TCriticalSection.Create;

finalization
  GLogLock.Free;

end.
