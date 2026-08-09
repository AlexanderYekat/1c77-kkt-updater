unit Config;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TInstanceConfig = record
    LabelName: string;
    Path: string;
  end;

  TComponentConfig = record
    Instances: TArray<TInstanceConfig>;
  end;

  TAppConfig = class
  private
    FSchemaVersion: Integer;
    FManifestUrl: string; // empty => default const
    FComponents: TDictionary<string, TComponentConfig>;
    function GetComponent(const Id: string): TComponentConfig;
    procedure SetComponent(const Id: string; const Value: TComponentConfig);
  public
    constructor Create;
    destructor Destroy; override;

    property SchemaVersion: Integer read FSchemaVersion write FSchemaVersion;
    property ManifestUrl: string read FManifestUrl write FManifestUrl;
    property Components[const Id: string]: TComponentConfig read GetComponent write SetComponent;

    function EffectiveManifestUrl: string;
    function FindInstanceIndex(const ComponentId, LabelName: string): Integer;
    procedure SetInstancePath(const ComponentId, LabelName, Path: string);
    function GetInstancePath(const ComponentId, LabelName: string): string;
    function ComponentIds: TArray<string>;
    procedure EnsureDefaultSlots;
  end;

function LoadConfig(out Config: TAppConfig; out ErrorMsg: string): Boolean;
function SaveConfig(Config: TAppConfig; out ErrorMsg: string): Boolean;
function LoadOrCreateConfig(out Config: TAppConfig; out ErrorMsg: string): Boolean;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  AppConsts,
  AppPaths,
  ModuleCatalog;

function MakeInstance(const LabelName, Path: string): TInstanceConfig;
begin
  Result.LabelName := LabelName;
  Result.Path := Path;
end;

constructor TAppConfig.Create;
begin
  inherited Create;
  FSchemaVersion := SchemaVersion;
  FManifestUrl := '';
  FComponents := TDictionary<string, TComponentConfig>.Create;
  EnsureDefaultSlots;
end;

destructor TAppConfig.Destroy;
begin
  FComponents.Free;
  inherited;
end;

procedure TAppConfig.EnsureDefaultSlots;
var
  Entry: TModuleCatalogEntry;
  Comp: TComponentConfig;
  Labels: TArray<string>;
  I: Integer;
  Existing: TComponentConfig;
  Lbl: string;
begin
  for Entry in ModuleCatalogEntries do
  begin
    Labels := LabelsForLine(Entry.Line);
    if FComponents.TryGetValue(Entry.ComponentId, Existing) then
    begin
      Comp := Existing;
      for Lbl in Labels do
      begin
        if FindInstanceIndex(Entry.ComponentId, Lbl) < 0 then
        begin
          I := Length(Comp.Instances);
          SetLength(Comp.Instances, I + 1);
          Comp.Instances[I] := MakeInstance(Lbl, '');
        end;
      end;
      FComponents.AddOrSetValue(Entry.ComponentId, Comp);
    end
    else
    begin
      SetLength(Comp.Instances, Length(Labels));
      for I := 0 to High(Labels) do
        Comp.Instances[I] := MakeInstance(Labels[I], '');
      FComponents.AddOrSetValue(Entry.ComponentId, Comp);
    end;
  end;
end;

function TAppConfig.GetComponent(const Id: string): TComponentConfig;
begin
  if not FComponents.TryGetValue(Id, Result) then
    SetLength(Result.Instances, 0);
end;

procedure TAppConfig.SetComponent(const Id: string; const Value: TComponentConfig);
begin
  FComponents.AddOrSetValue(Id, Value);
end;

function TAppConfig.EffectiveManifestUrl: string;
begin
  if Trim(FManifestUrl) = '' then
    Result := DefaultManifestUrl
  else
    Result := Trim(FManifestUrl);
end;

function SameLabel(const A, B: string): Boolean;
begin
  Result := SameText(Trim(A), Trim(B));
end;

function TAppConfig.FindInstanceIndex(const ComponentId, LabelName: string): Integer;
var
  Comp: TComponentConfig;
  I: Integer;
begin
  Result := -1;
  Comp := GetComponent(ComponentId);
  for I := 0 to High(Comp.Instances) do
    if SameLabel(Comp.Instances[I].LabelName, LabelName) then
      Exit(I);
end;

procedure TAppConfig.SetInstancePath(const ComponentId, LabelName, Path: string);
var
  Comp: TComponentConfig;
  Idx: Integer;
begin
  Comp := GetComponent(ComponentId);
  Idx := FindInstanceIndex(ComponentId, LabelName);
  if Idx < 0 then
  begin
    Idx := Length(Comp.Instances);
    SetLength(Comp.Instances, Idx + 1);
    Comp.Instances[Idx].LabelName := LabelName;
  end;
  Comp.Instances[Idx].Path := Trim(Path);
  SetComponent(ComponentId, Comp);
end;

function TAppConfig.GetInstancePath(const ComponentId, LabelName: string): string;
var
  Comp: TComponentConfig;
  Idx: Integer;
begin
  Comp := GetComponent(ComponentId);
  Idx := FindInstanceIndex(ComponentId, LabelName);
  if Idx < 0 then
    Result := ''
  else
    Result := Comp.Instances[Idx].Path;
end;

function TAppConfig.ComponentIds: TArray<string>;
begin
  Result := FComponents.Keys.ToArray;
  TArray.Sort<string>(Result);
end;

function ParseInstances(Arr: TJSONArray): TArray<TInstanceConfig>;
var
  I: Integer;
  Obj: TJSONObject;
  Item: TJSONValue;
begin
  SetLength(Result, 0);
  if Arr = nil then
    Exit;
  SetLength(Result, Arr.Count);
  for I := 0 to Arr.Count - 1 do
  begin
    Item := Arr.Items[I];
    if not (Item is TJSONObject) then
      Continue;
    Obj := TJSONObject(Item);
    Result[I].LabelName := Obj.GetValue<string>('label', '');
    Result[I].Path := Obj.GetValue<string>('path', '');
  end;
end;

function EnsureAtolLabels(var Comp: TComponentConfig): Boolean;
var
  PathZ, PathS: string;
  I: Integer;
  AssignedZ, AssignedS: Boolean;
begin
  PathZ := '';
  PathS := '';
  AssignedZ := False;
  AssignedS := False;

  for I := 0 to High(Comp.Instances) do
  begin
    if SameLabel(Comp.Instances[I].LabelName, LabelZlobin) then
    begin
      PathZ := Comp.Instances[I].Path;
      AssignedZ := True;
    end
    else if SameLabel(Comp.Instances[I].LabelName, LabelStrelets) then
    begin
      PathS := Comp.Instances[I].Path;
      AssignedS := True;
    end;
  end;

  // Старый config с битой кодировкой label — берём пути по порядку
  if not AssignedZ or not AssignedS then
  begin
    for I := 0 to High(Comp.Instances) do
    begin
      if Trim(Comp.Instances[I].Path) = '' then
        Continue;
      if not AssignedZ and not SameLabel(Comp.Instances[I].LabelName, LabelStrelets) then
      begin
        if PathZ = '' then
          PathZ := Comp.Instances[I].Path;
        AssignedZ := True;
      end
      else if not AssignedS then
      begin
        if PathS = '' then
          PathS := Comp.Instances[I].Path;
        AssignedS := True;
      end;
    end;
  end;

  SetLength(Comp.Instances, 2);
  Comp.Instances[0] := MakeInstance(LabelZlobin, PathZ);
  Comp.Instances[1] := MakeInstance(LabelStrelets, PathS);
  Result := True;
end;

function EnsureShtrihLabels(var Comp: TComponentConfig): Boolean;
var
  PathS: string;
  I: Integer;
begin
  PathS := '';
  for I := 0 to High(Comp.Instances) do
    if SameLabel(Comp.Instances[I].LabelName, LabelSurgut) then
      PathS := Comp.Instances[I].Path;
  if (PathS = '') and (Length(Comp.Instances) > 0) then
    PathS := Comp.Instances[0].Path;
  SetLength(Comp.Instances, 1);
  Comp.Instances[0] := MakeInstance(LabelSurgut, PathS);
  Result := True;
end;

function LoadConfig(out Config: TAppConfig; out ErrorMsg: string): Boolean;
var
  Text: string;
  Root, CompNode: TJSONObject;
  Components: TJSONObject;
  Pair: TJSONPair;
  Comp: TComponentConfig;
  ManifestVal: TJSONValue;
  Entry: TModuleCatalogEntry;
begin
  Result := False;
  Config := nil;
  ErrorMsg := '';
  if not TFile.Exists(ConfigFilePath) then
  begin
    ErrorMsg := 'Файл конфигурации не найден: ' + ConfigFilePath;
    Exit;
  end;

  Text := TFile.ReadAllText(ConfigFilePath, TEncoding.UTF8);
  Root := TJSONObject.ParseJSONValue(Text) as TJSONObject;
  if Root = nil then
  begin
    ErrorMsg := 'Некорректный JSON в config.json';
    Exit;
  end;
  try
    Config := TAppConfig.Create;
    Config.SchemaVersion := Root.GetValue<Integer>('schema_version', 0);
    if Config.SchemaVersion <> SchemaVersion then
    begin
      ErrorMsg := Format(
        'Неподдерживаемый schema_version=%d (ожидается %d)',
        [Config.SchemaVersion, SchemaVersion]
      );
      FreeAndNil(Config);
      Exit;
    end;

    ManifestVal := Root.Values['manifest_url'];
    if (ManifestVal = nil) or (ManifestVal is TJSONNull) then
      Config.ManifestUrl := ''
    else
      Config.ManifestUrl := ManifestVal.Value;

    Components := Root.Values['components'] as TJSONObject;
    if Components <> nil then
    begin
      for Pair in Components do
      begin
        CompNode := Pair.JsonValue as TJSONObject;
        if CompNode = nil then
          Continue;
        Comp.Instances := ParseInstances(CompNode.Values['instances'] as TJSONArray);
        Config.SetComponent(Pair.JsonString.Value, Comp);
      end;
    end;

    // Старый config: нормализуем labels для модулей из каталога
    for Entry in ModuleCatalogEntries do
    begin
      Comp := Config.Components[Entry.ComponentId];
      if Length(Comp.Instances) = 0 then
        Continue;
      if Entry.Line = mlAtol then
        EnsureAtolLabels(Comp)
      else
        EnsureShtrihLabels(Comp);
      Config.SetComponent(Entry.ComponentId, Comp);
    end;

    Config.EnsureDefaultSlots;
    Result := True;
  finally
    Root.Free;
  end;
end;

function BuildConfigJson(Config: TAppConfig): string;
var
  Root, Components, CompObj, InstObj: TJSONObject;
  InstArr: TJSONArray;
  Ids: TArray<string>;
  Id: string;
  Comp: TComponentConfig;
  Inst: TInstanceConfig;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('schema_version', TJSONNumber.Create(Config.SchemaVersion));
    if Trim(Config.ManifestUrl) = '' then
      Root.AddPair('manifest_url', TJSONNull.Create)
    else
      Root.AddPair('manifest_url', Config.ManifestUrl);

    Components := TJSONObject.Create;
    Root.AddPair('components', Components);

    Ids := Config.ComponentIds;
    for Id in Ids do
    begin
      Comp := Config.Components[Id];
      CompObj := TJSONObject.Create;
      InstArr := TJSONArray.Create;
      CompObj.AddPair('instances', InstArr);
      for Inst in Comp.Instances do
      begin
        InstObj := TJSONObject.Create;
        InstObj.AddPair('label', Inst.LabelName);
        InstObj.AddPair('path', Inst.Path);
        InstArr.AddElement(InstObj);
      end;
      Components.AddPair(Id, CompObj);
    end;

    Result := Root.Format(2);
  finally
    Root.Free;
  end;
end;

function SaveConfig(Config: TAppConfig; out ErrorMsg: string): Boolean;
var
  TempPath, FinalPath, Text: string;
begin
  Result := False;
  ErrorMsg := '';
  TempPath := '';
  try
    EnsureAppDirectories;
    Config.SchemaVersion := SchemaVersion;
    Config.EnsureDefaultSlots;
    FinalPath := ConfigFilePath;
    TempPath := FinalPath + '.tmp';
    Text := BuildConfigJson(Config);
    TFile.WriteAllText(TempPath, Text, TEncoding.UTF8);
    if TFile.Exists(FinalPath) then
      TFile.Delete(FinalPath);
    TFile.Move(TempPath, FinalPath);
    Result := True;
  except
    on E: Exception do
    begin
      ErrorMsg := E.Message;
      if (TempPath <> '') and TFile.Exists(TempPath) then
        try
          TFile.Delete(TempPath);
        except
        end;
    end;
  end;
end;

function LoadOrCreateConfig(out Config: TAppConfig; out ErrorMsg: string): Boolean;
begin
  ErrorMsg := '';
  if TFile.Exists(ConfigFilePath) then
    Exit(LoadConfig(Config, ErrorMsg));

  Config := TAppConfig.Create;
  Result := SaveConfig(Config, ErrorMsg);
  if not Result then
    FreeAndNil(Config);
end;

end.
