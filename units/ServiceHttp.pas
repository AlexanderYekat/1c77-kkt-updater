unit ServiceHttp;

interface

/// Локальный HTTP к службе (http://127.0.0.1 / localhost). HTTPS для GitHub — в HttpDownload.
function ServiceHttpGet(const Url: string; out Content: string;
  out ErrorMsg: string): Boolean;
function GetServiceVersion(const BaseUrl, ExpectedComponentId: string;
  out Version: string; out ErrorMsg: string): Boolean;
function GetServiceHealthOk(const BaseUrl: string; out ErrorMsg: string): Boolean;
function WaitServiceVersionAndHealth(const BaseUrl, ExpectedComponentId,
  ExpectedVersion: string; IntervalMs, MaxMs: Integer;
  out ErrorMsg: string): Boolean;
function JoinBaseUrl(const BaseUrl, Endpoint: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  AppConsts,
  AppLog,
  VersionParse;

function JoinBaseUrl(const BaseUrl, Endpoint: string): string;
var
  Base, Ep: string;
begin
  Base := Trim(BaseUrl);
  while (Length(Base) > 0) and (Base[Length(Base)] = '/') do
    Delete(Base, Length(Base), 1);
  Ep := Trim(Endpoint);
  if (Ep <> '') and (Ep[1] <> '/') then
    Ep := '/' + Ep;
  Result := Base + Ep;
end;

function IsAllowedLocalUrl(const Url: string; out ErrorMsg: string): Boolean;
var
  Lower: string;
begin
  Lower := LowerCase(Trim(Url));
  Result :=
    StartsText('http://127.0.0.1', Lower) or
    StartsText('http://localhost', Lower) or
    StartsText('https://127.0.0.1', Lower) or
    StartsText('https://localhost', Lower);
  if not Result then
    ErrorMsg :=
      'Для службы разрешён только локальный URL (http://127.0.0.1 или localhost): ' + Url;
end;

function ServiceHttpGet(const Url: string; out Content: string;
  out ErrorMsg: string): Boolean;
var
  Client: THTTPClient;
  Resp: IHTTPResponse;
begin
  Result := False;
  Content := '';
  ErrorMsg := '';
  if not IsAllowedLocalUrl(Url, ErrorMsg) then
    Exit;

  Client := THTTPClient.Create;
  try
    try
      Client.ConnectionTimeout := 5000;
      Client.ResponseTimeout := 10000;
      Client.UserAgent := '1C77-KKT-Updater/1.0';
      Client.HandleRedirects := False;
      Resp := Client.Get(Url);
      if Resp.StatusCode <> 200 then
      begin
        ErrorMsg := Format('HTTP %d: %s', [Resp.StatusCode, Url]);
        Exit;
      end;
      Content := Resp.ContentAsString(TEncoding.UTF8);
      Result := True;
    except
      on E: Exception do
      begin
        ErrorMsg := E.Message;
      end;
    end;
  finally
    Client.Free;
  end;
end;

function GetServiceVersion(const BaseUrl, ExpectedComponentId: string;
  out Version: string; out ErrorMsg: string): Boolean;
var
  Url, Text, Comp, Ver: string;
  Root: TJSONObject;
  Key: TVersionKey;
begin
  Result := False;
  Version := '';
  ErrorMsg := '';
  Url := JoinBaseUrl(BaseUrl, EndpointVersion);
  if not ServiceHttpGet(Url, Text, ErrorMsg) then
    Exit;

  Root := TJSONObject.ParseJSONValue(Text) as TJSONObject;
  if Root = nil then
  begin
    ErrorMsg := 'Некорректный JSON /version';
    Exit;
  end;
  try
    Comp := Root.GetValue<string>('component', '');
    Ver := Root.GetValue<string>('version', '');
    if (ExpectedComponentId <> '') and (Comp <> '') and
       (not SameText(Comp, ExpectedComponentId)) then
    begin
      ErrorMsg := Format(
        '/version component=%s, ожидается %s',
        [Comp, ExpectedComponentId]);
      Exit;
    end;
    if not ParseVersionKey(Ver, Key) then
    begin
      ErrorMsg := 'Некорректный version в /version: ' + Ver;
      Exit;
    end;
    Version := Ver;
    Result := True;
  finally
    Root.Free;
  end;
end;

function GetServiceHealthOk(const BaseUrl: string; out ErrorMsg: string): Boolean;
var
  Url, Text, Status: string;
  Root: TJSONObject;
  ResultVal: Integer;
begin
  Result := False;
  ErrorMsg := '';
  Url := JoinBaseUrl(BaseUrl, EndpointHealth);
  if not ServiceHttpGet(Url, Text, ErrorMsg) then
    Exit;

  Root := TJSONObject.ParseJSONValue(Text) as TJSONObject;
  if Root = nil then
  begin
    ErrorMsg := 'Некорректный JSON /health';
    Exit;
  end;
  try
    ResultVal := Root.GetValue<Integer>('result', 0);
    Status := Root.GetValue<string>('status', '');
    if (ResultVal = 1) or SameText(Status, 'up') or SameText(Status, 'ok') then
      Result := True
    else
      ErrorMsg := 'health не OK: ' + Text;
  finally
    Root.Free;
  end;
end;

function WaitServiceVersionAndHealth(const BaseUrl, ExpectedComponentId,
  ExpectedVersion: string; IntervalMs, MaxMs: Integer;
  out ErrorMsg: string): Boolean;
var
  Elapsed: Integer;
  Ver, LastErr: string;
begin
  Result := False;
  ErrorMsg := '';
  LastErr := '';
  Elapsed := 0;
  if IntervalMs < 100 then
    IntervalMs := 1000;
  if MaxMs < IntervalMs then
    MaxMs := ServiceHealthRetryMaxMs;

  while Elapsed <= MaxMs do
  begin
    if GetServiceVersion(BaseUrl, ExpectedComponentId, Ver, LastErr) then
    begin
      if SameText(Ver, ExpectedVersion) then
      begin
        if GetServiceHealthOk(BaseUrl, LastErr) then
        begin
          LogInfo(Format('Verify OK /version=%s /health', [Ver]));
          Exit(True);
        end;
      end
      else
        LastErr := Format('/version=%s, ожидается %s', [Ver, ExpectedVersion]);
    end;
    Sleep(IntervalMs);
    Inc(Elapsed, IntervalMs);
  end;
  ErrorMsg := 'Проверка /version+/health не прошла за ' + IntToStr(MaxMs) +
    ' мс. Последняя ошибка: ' + LastErr;
  LogError(ErrorMsg);
end;

end.
