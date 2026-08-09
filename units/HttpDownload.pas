unit HttpDownload;

interface

function DownloadToFile(const Url, DestFile: string; out ErrorMsg: string): Boolean;
function DownloadToString(const Url: string; out Content: string; out ErrorMsg: string): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  System.IOUtils,
  System.Net.HttpClient,
  System.Net.URLClient,
  AppLog;

function CreateClient: THTTPClient;
begin
  Result := THTTPClient.Create;
  Result.ConnectionTimeout := 30000;
  Result.ResponseTimeout := 120000;
  Result.UserAgent := '1C77-KKT-Updater/1.0';
  Result.HandleRedirects := True;
end;

function EnsureHttps(const Url: string; out ErrorMsg: string): Boolean;
begin
  Result := StartsText('https://', LowerCase(Url));
  if not Result then
    ErrorMsg := 'Разрешён только HTTPS: ' + Url;
end;

function DownloadToFile(const Url, DestFile: string; out ErrorMsg: string): Boolean;
var
  Client: THTTPClient;
  Resp: IHTTPResponse;
  Stream: TFileStream;
  Dir: string;
begin
  Result := False;
  ErrorMsg := '';
  if not EnsureHttps(Url, ErrorMsg) then
    Exit;

  Dir := ExtractFilePath(DestFile);
  if Dir <> '' then
    ForceDirectories(Dir);

  Client := CreateClient;
  try
    try
      LogInfo('HTTP GET file: ' + Url);
      Resp := Client.Get(Url);
      if Resp.StatusCode <> 200 then
      begin
        ErrorMsg := Format('HTTP %d при загрузке %s', [Resp.StatusCode, Url]);
        LogError(ErrorMsg);
        Exit;
      end;
      Stream := TFileStream.Create(DestFile, fmCreate);
      try
        Stream.CopyFrom(Resp.ContentStream, 0);
      finally
        Stream.Free;
      end;
      Result := True;
    except
      on E: Exception do
      begin
        ErrorMsg := E.Message;
        LogError('DownloadToFile: ' + ErrorMsg);
      end;
    end;
  finally
    Client.Free;
  end;
end;

function DownloadToString(const Url: string; out Content: string; out ErrorMsg: string): Boolean;
var
  Client: THTTPClient;
  Resp: IHTTPResponse;
begin
  Result := False;
  Content := '';
  ErrorMsg := '';
  if not EnsureHttps(Url, ErrorMsg) then
    Exit;

  Client := CreateClient;
  try
    try
      LogInfo('HTTP GET text: ' + Url);
      Resp := Client.Get(Url);
      if Resp.StatusCode <> 200 then
      begin
        ErrorMsg := Format('HTTP %d при загрузке %s', [Resp.StatusCode, Url]);
        LogError(ErrorMsg);
        Exit;
      end;
      Content := Resp.ContentAsString(TEncoding.UTF8);
      Result := True;
    except
      on E: Exception do
      begin
        ErrorMsg := E.Message;
        LogError('DownloadToString: ' + ErrorMsg);
      end;
    end;
  finally
    Client.Free;
  end;
end;

end.
