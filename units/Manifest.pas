unit Manifest;

interface

uses
  System.Generics.Collections,
  VersionParse;

type
  TComponentManifest = record
    Id: string;
    Typ: string;
    Version: string;
    Repository: string;
    Tag: string;
    Asset: string;
    DownloadUrl: string;
    Sha256: string;
    function IsValidErtModule: Boolean;
  end;

  TStableManifest = record
    SchemaVersion: Integer;
    Components: TDictionary<string, TComponentManifest>;
    procedure Init;
    procedure Clear;
    function TryGet(const Id: string; out Comp: TComponentManifest): Boolean;
    function Count: Integer;
  end;

function LoadManifestFromUrl(const Url: string; out Manifest: TStableManifest;
  out ErrorMsg: string): Boolean;
function LoadManifestFromJson(const JsonText: string; out Manifest: TStableManifest;
  out ErrorMsg: string): Boolean;

implementation

uses
  System.SysUtils,
  System.JSON,
  AppConsts,
  AppLog,
  HttpDownload;

function TComponentManifest.IsValidErtModule: Boolean;
begin
  Result :=
    (Id <> '') and
    SameText(Typ, ComponentTypeErtModule) and
    (Version <> '') and
    (Repository <> '') and
    (Tag <> '') and
    (Asset <> '') and
    (DownloadUrl <> '') and
    (Sha256 <> '');
end;

procedure TStableManifest.Init;
begin
  SchemaVersion := 0;
  if Components = nil then
    Components := TDictionary<string, TComponentManifest>.Create
  else
    Components.Clear;
end;

procedure TStableManifest.Clear;
begin
  SchemaVersion := 0;
  FreeAndNil(Components);
end;

function TStableManifest.TryGet(const Id: string; out Comp: TComponentManifest): Boolean;
begin
  Comp := Default(TComponentManifest);
  Result := (Components <> nil) and Components.TryGetValue(Id, Comp);
end;

function TStableManifest.Count: Integer;
begin
  if Components = nil then
    Result := 0
  else
    Result := Components.Count;
end;

function ParseComponent(Obj: TJSONObject; out Comp: TComponentManifest;
  out ErrorMsg: string): Boolean;
begin
  Result := False;
  Comp := Default(TComponentManifest);
  if Obj = nil then
  begin
    ErrorMsg := 'Компонент отсутствует в manifest';
    Exit;
  end;
  Comp.Id := Obj.GetValue<string>('id', '');
  Comp.Typ := Obj.GetValue<string>('type', '');
  Comp.Version := Obj.GetValue<string>('version', '');
  Comp.Repository := Obj.GetValue<string>('repository', '');
  Comp.Tag := Obj.GetValue<string>('tag', '');
  Comp.Asset := Obj.GetValue<string>('asset', '');
  Comp.DownloadUrl := Obj.GetValue<string>('download_url', '');
  Comp.Sha256 := Obj.GetValue<string>('sha256', '');
  if not Comp.IsValidErtModule then
  begin
    ErrorMsg := 'Неполные или неверные поля компонента ' + Comp.Id +
      ' (нужны id/type/version/repository/tag/asset/download_url/sha256, type=ert-module)';
    Exit;
  end;
  Result := True;
end;

function LoadManifestFromJson(const JsonText: string; out Manifest: TStableManifest;
  out ErrorMsg: string): Boolean;
var
  Root, Components, CompObj: TJSONObject;
  Pair: TJSONPair;
  Comp: TComponentManifest;
  Key: TVersionKey;
  CompType, CompKey: string;
begin
  Result := False;
  ErrorMsg := '';
  // out-параметр не инициализирован — не вызывать Clear по мусорному указателю
  Manifest.SchemaVersion := 0;
  Manifest.Components := nil;
  Manifest.Init;
  Root := TJSONObject.ParseJSONValue(JsonText) as TJSONObject;
  if Root = nil then
  begin
    ErrorMsg := 'Некорректный JSON manifest';
    Manifest.Clear;
    Exit;
  end;
  try
    Manifest.SchemaVersion := Root.GetValue<Integer>('schema_version', 0);
    if Manifest.SchemaVersion <> SchemaVersion then
    begin
      ErrorMsg := Format(
        'Неподдерживаемый schema_version manifest=%d (ожидается %d)',
        [Manifest.SchemaVersion, SchemaVersion]
      );
      Manifest.Clear;
      Exit;
    end;

    Components := Root.Values['components'] as TJSONObject;
    if Components = nil then
    begin
      ErrorMsg := 'В manifest нет объекта components';
      Manifest.Clear;
      Exit;
    end;

    // Пустой {} допустим. Битый присутствующий ert-module — ошибка.
    for Pair in Components do
    begin
      CompKey := Pair.JsonString.Value;
      CompObj := Pair.JsonValue as TJSONObject;
      if CompObj = nil then
      begin
        ErrorMsg := 'Компонент ' + CompKey + ': ожидается объект JSON';
        Manifest.Clear;
        Exit;
      end;

      CompType := CompObj.GetValue<string>('type', '');
      if not SameText(CompType, ComponentTypeErtModule) then
      begin
        LogInfo('Manifest: пропуск type=' + CompType + ' id=' + CompKey + ' (CP2: только ert-module)');
        Continue;
      end;

      if not ParseComponent(CompObj, Comp, ErrorMsg) then
      begin
        Manifest.Clear;
        Exit;
      end;

      if not SameText(Comp.Id, CompKey) then
      begin
        ErrorMsg := Format(
          'id компонента (%s) не совпадает с ключом (%s)',
          [Comp.Id, CompKey]
        );
        Manifest.Clear;
        Exit;
      end;

      if not ParseVersionKey(Comp.Version, Key) then
      begin
        ErrorMsg := 'Некорректный version в manifest для ' + Comp.Id + ': ' + Comp.Version;
        Manifest.Clear;
        Exit;
      end;

      Manifest.Components.AddOrSetValue(Comp.Id, Comp);
    end;

    Result := True;
  finally
    Root.Free;
  end;
end;

function LoadManifestFromUrl(const Url: string; out Manifest: TStableManifest;
  out ErrorMsg: string): Boolean;
var
  Text: string;
  Pair: TPair<string, TComponentManifest>;
  Summary: string;
begin
  Result := False;
  LogInfo('Загрузка manifest: ' + Url);
  if not DownloadToString(Url, Text, ErrorMsg) then
    Exit;
  Result := LoadManifestFromJson(Text, Manifest, ErrorMsg);
  if Result then
  begin
    Summary := '';
    if Manifest.Components <> nil then
      for Pair in Manifest.Components do
      begin
        if Summary <> '' then
          Summary := Summary + '; ';
        Summary := Summary + Pair.Key + '=' + Pair.Value.Version;
      end;
    if Summary = '' then
      Summary := '(пусто)';
    LogInfo('Manifest OK: ' + IntToStr(Manifest.Count) + ' ert-module: ' + Summary);
  end
  else
    LogError('Manifest parse: ' + ErrorMsg);
end;

end.
