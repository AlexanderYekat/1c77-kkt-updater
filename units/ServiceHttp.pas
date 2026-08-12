unit ServiceHttp;

interface

/// Локальный HTTP к службе (http://127.0.0.1 / localhost). HTTPS для GitHub — в HttpDownload.
function ServiceHttpGet(const Url: string; out Content: string;
  out ErrorMsg: string): Boolean;
function ServiceHttpPost(const Url, Body: string; out Content: string;
  out StatusCode: Integer; out ErrorMsg: string): Boolean;
function GetServiceVersion(const BaseUrl, ExpectedComponentId: string;
  out Version: string; out ErrorMsg: string): Boolean;
function GetServiceHealthOk(const BaseUrl: string; out ErrorMsg: string): Boolean;
/// POST /exit — штатный stop для сборок с hide-to-tray. True = HTTP 200.
function RequestServiceExit(const BaseUrl: string; out ErrorMsg: string): Boolean;
/// После start: /version + /health. Если /version нет (старые сборки, HTTP 404) —
/// fallback: VERSIONINFO exe + /health.
function WaitServiceVersionAndHealth(const BaseUrl, ExpectedComponentId,
  ExpectedVersion, ExePath: string; IntervalMs, MaxMs: Integer;
  out ErrorMsg: string): Boolean;
function JoinBaseUrl(const BaseUrl, Endpoint: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  AppConsts,
  AppLog,
  VersionParse,
  ExeVersion;

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

function ServiceHttpPost(const Url, Body: string; out Content: string;
  out StatusCode: Integer; out ErrorMsg: string): Boolean;
var
  Client: THTTPClient;
  Resp: IHTTPResponse;
  Stream: TStringStream;
begin
  Result := False;
  Content := '';
  StatusCode := 0;
  ErrorMsg := '';
  if not IsAllowedLocalUrl(Url, ErrorMsg) then
    Exit;

  Client := THTTPClient.Create;
  Stream := TStringStream.Create(Body, TEncoding.UTF8);
  try
    try
      Client.ConnectionTimeout := 5000;
      Client.ResponseTimeout := 10000;
      Client.UserAgent := '1C77-KKT-Updater/1.0';
      Client.HandleRedirects := False;
      Stream.Position := 0;
      Resp := Client.Post(Url, Stream);
      StatusCode := Resp.StatusCode;
      Content := Resp.ContentAsString(TEncoding.UTF8);
      Result := StatusCode = 200;
      if not Result then
        ErrorMsg := Format('HTTP %d: %s', [StatusCode, Url]);
    except
      on E: Exception do
      begin
        // Процесс мог успеть выйти сразу после ответа — соединение рвётся.
        ErrorMsg := E.Message;
      end;
    end;
  finally
    Stream.Free;
    Client.Free;
  end;
end;

function RequestServiceExit(const BaseUrl: string; out ErrorMsg: string): Boolean;
var
  Url, Content: string;
  StatusCode: Integer;
begin
  Result := False;
  ErrorMsg := '';
  if Trim(BaseUrl) = '' then
  begin
    ErrorMsg := 'base_url не задан';
    Exit;
  end;
  Url := JoinBaseUrl(BaseUrl, EndpointExit);
  Result := ServiceHttpPost(Url, '{}', Content, StatusCode, ErrorMsg);
  if Result then
    LogInfo('HTTP /exit OK: ' + Url)
  else
    LogInfo(Format('HTTP /exit не принят (%s): %s', [Url, ErrorMsg]));
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

function IsHttp404(const ErrorMsg: string): Boolean;
begin
  // ServiceHttpGet: 'HTTP 404: url'
  Result := StartsText('HTTP 404:', Trim(ErrorMsg));
end;

function WaitServiceVersionAndHealth(const BaseUrl, ExpectedComponentId,
  ExpectedVersion, ExePath: string; IntervalMs, MaxMs: Integer;
  out ErrorMsg: string): Boolean;
var
  Elapsed: Integer;
  Ver, LastErr, ExeErr: string;
  VersionOk, UsedExeFallback: Boolean;
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
    VersionOk := False;
    UsedExeFallback := False;
    Ver := '';

    if GetServiceVersion(BaseUrl, ExpectedComponentId, Ver, LastErr) then
    begin
      if SameText(Ver, ExpectedVersion) then
        VersionOk := True
      else
        LastErr := Format('/version=%s, ожидается %s', [Ver, ExpectedVersion]);
    end
    else if IsHttp404(LastErr) then
    begin
      // Старые сборки без GET /version: канон из VERSIONINFO exe
      ExeErr := '';
      if Trim(ExePath) = '' then
        LastErr := 'GET /version=404 и exe не задан для fallback'
      else if not ReadExeCanonVersion(ExePath, Ver, ExeErr) then
        LastErr := 'GET /version=404; fallback FileVersion: ' + ExeErr
      else if not SameText(Ver, ExpectedVersion) then
        LastErr := Format(
          'GET /version=404; exe version=%s, ожидается %s',
          [Ver, ExpectedVersion])
      else
      begin
        VersionOk := True;
        UsedExeFallback := True;
      end;
    end;
    // иначе: соединение ещё не поднялось / 5xx — ждём дальше

    if VersionOk then
    begin
      if GetServiceHealthOk(BaseUrl, LastErr) then
      begin
        if UsedExeFallback then
          LogInfo(Format(
            'Verify OK (legacy: /version отсутствует, FileVersion=%s) /health',
            [Ver]))
        else
          LogInfo(Format('Verify OK /version=%s /health', [Ver]));
        Exit(True);
      end;
    end;

    Sleep(IntervalMs);
    Inc(Elapsed, IntervalMs);
  end;
  ErrorMsg := 'Проверка /version+/health не прошла за ' + IntToStr(MaxMs) +
    ' мс. Последняя ошибка: ' + LastErr;
  LogError(ErrorMsg);
end;

end.
