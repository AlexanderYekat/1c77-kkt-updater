unit WorkingSnapshot;

interface

uses
  System.SysUtils;

type
  TSnapshotFileKind = (sfErt, sfMd);

  TSnapshotFileItem = record
    Stem: string;
    Kind: TSnapshotFileKind;
    OriginalPath: string;
    StoredAs: string;
    Version: string; // может быть пусто (legacy без версий)
    Restorable: Boolean; // False для 1Cv7.MD
  end;

  TWorkingSnapshotInfo = record
    IbLabel: string;
    LineId: string;
    IbRoot: string;
    ExtFormsRoot: string;
    CreatedAt: string;
    Files: TArray<TSnapshotFileItem>;
    SnapshotDir: string;
  end;

/// Снимок рабочей конфигурации: ERT-обработки + 1Cv7.MD (MD только архивируется).
function CreateWorkingSnapshot(
  const IbLabel, LineId, MainErtPath: string;
  out Info: TWorkingSnapshotInfo;
  out ErrorMsg: string
): Boolean;

function WorkingSnapshotExists(const IbLabel: string): Boolean;
function WorkingSnapshotDir(const IbLabel: string): string;
function LoadWorkingSnapshotManifest(const IbLabel: string;
  out Info: TWorkingSnapshotInfo; out ErrorMsg: string): Boolean;

/// Восстанавливает только ERT (никогда не 1Cv7.MD).
function RestoreWorkingSnapshot(
  const IbLabel: string;
  out RestoredCount: Integer;
  out ErrorMsg: string
): Boolean;

/// <ИБ>\ExtForms для ERT из ExtForms или ExtForms\Equip, иначе ''.
function ExtFormsRootFromErt(const ErtPath: string): string;
function IbRootFromExtForms(const ExtFormsRoot: string): string;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.StrUtils,
  AppConsts,
  AppPaths,
  AppLog,
  VersionParse,
  ModuleCatalog,
  ErtStorage;

function SafeToken(const S: string): string;
var
  I: Integer;
  Ch: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    if CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) or (Ord(Ch) > 127) then
      Result := Result + Ch
    else
      Result := Result + '_';
  end;
  if Result = '' then
    Result := 'instance';
end;

function WorkingSnapshotDir(const IbLabel: string): string;
begin
  Result := TPath.Combine(TPath.Combine(SnapshotsDir, SafeToken(IbLabel)), 'working');
end;

function WorkingSnapshotExists(const IbLabel: string): Boolean;
begin
  Result := TFile.Exists(TPath.Combine(WorkingSnapshotDir(IbLabel), 'manifest.json'));
end;

function ExtFormsRootFromErt(const ErtPath: string): string;
var
  Dir, Parent, Leaf: string;
begin
  Result := '';
  if Trim(ErtPath) = '' then
    Exit;
  Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(ErtPath));
  Leaf := TPath.GetFileName(Dir);
  if SameText(Leaf, 'Equip') then
  begin
    Parent := ExcludeTrailingPathDelimiter(ExtractFilePath(Dir));
    if SameText(TPath.GetFileName(Parent), 'ExtForms') then
      Exit(Parent);
  end;
  if SameText(Leaf, 'ExtForms') then
    Exit(Dir);
end;

function IbRootFromExtForms(const ExtFormsRoot: string): string;
begin
  if ExtFormsRoot = '' then
    Result := ''
  else
    Result := ExcludeTrailingPathDelimiter(ExtractFilePath(ExtFormsRoot));
end;

function TryReadVersion(const ErtPath: string): string;
var
  Text: string;
  Id: TModuleIdentity;
  Legacy: string;
  Stem: string;
begin
  Result := '';
  if not TFile.Exists(ErtPath) then
    Exit;
  try
    Text := ReadErtModuleText(ErtPath);
    Id := ExtractModuleIdentity(Text);
    if Id.HasComponent and Id.HasVersion then
      Exit(Id.VersionRaw);
    Stem := ChangeFileExt(TPath.GetFileName(ErtPath), '');
    if HasLegacyStemVerMarker(Text, Stem, Legacy) then
      Exit(Legacy);
    // frATOL54_comm.ert может иметь legacy //frATOL54 ver:
    if SameText(Stem, 'frATOL54_comm') and HasLegacyStemVerMarker(Text, 'frATOL54', Legacy) then
      Exit(Legacy);
    if Id.HasVersion then
      Exit(Id.VersionRaw);
  except
    Result := '';
  end;
end;

procedure AddItem(var Items: TArray<TSnapshotFileItem>; const Item: TSnapshotFileItem);
begin
  SetLength(Items, Length(Items) + 1);
  Items[High(Items)] := Item;
end;

function MakeErtItem(const Stem, Path: string): TSnapshotFileItem;
begin
  Result.Stem := Stem;
  Result.Kind := sfErt;
  Result.OriginalPath := Path;
  Result.StoredAs := Stem + '.ert';
  Result.Version := TryReadVersion(Path);
  Result.Restorable := True;
end;

function CollectSnapshotFiles(
  const LineId, MainErtPath, ExtFormsRoot, IbRoot: string
): TArray<TSnapshotFileItem>;
var
  Line: TModuleLine;
  Entry: TModuleCatalogEntry;
  Path, MainStem: string;
  MdPath: string;
  Item: TSnapshotFileItem;
  Seen: TStringList;
begin
  SetLength(Result, 0);
  Line := LineFromLineId(LineId);
  Seen := TStringList.Create;
  try
    Seen.CaseSensitive := False;
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;

    for Entry in ModulesForLine(Line) do
    begin
      Path := '';
      // Главный якорь линейки — из MainErtPath, если stem совпадает
      MainStem := ChangeFileExt(TPath.GetFileName(Trim(MainErtPath)), '');
      if (Trim(MainErtPath) <> '') and
         (SameText(MainStem, Entry.FileStem) or
          ((SameText(Entry.ComponentId, ComponentAtolModule)) and
           (SameText(MainStem, 'frATOL54') or SameText(MainStem, 'frATOL54_comm')))) then
        Path := Trim(MainErtPath);

      if (Path = '') or (not TFile.Exists(Path)) then
        Path := ResolveModulePath(ExtFormsRoot, '', Entry);

      if (Path = '') or (not TFile.Exists(Path)) then
        Continue;
      if Seen.IndexOf(UpperCase(Path)) >= 0 then
        Continue;
      Seen.Add(UpperCase(Path));
      AddItem(Result, MakeErtItem(ChangeFileExt(TPath.GetFileName(Path), ''), Path));
    end;
  finally
    Seen.Free;
  end;

  // 1Cv7.MD — только в снимок, без restore (не из ModuleCatalog)
  if IbRoot <> '' then
  begin
    MdPath := TPath.Combine(IbRoot, '1Cv7.MD');
    if not TFile.Exists(MdPath) then
      MdPath := TPath.Combine(IbRoot, '1cv7.md');
    if TFile.Exists(MdPath) then
    begin
      Item.Stem := '1Cv7.MD';
      Item.Kind := sfMd;
      Item.OriginalPath := MdPath;
      Item.StoredAs := '1Cv7.MD';
      Item.Version := '';
      Item.Restorable := False;
      AddItem(Result, Item);
    end;
  end;
end;

function KindToStr(K: TSnapshotFileKind): string;
begin
  if K = sfMd then
    Result := 'md'
  else
    Result := 'ert';
end;

function StrToKind(const S: string): TSnapshotFileKind;
begin
  if SameText(S, 'md') then
    Result := sfMd
  else
    Result := sfErt;
end;

function WriteManifest(const Info: TWorkingSnapshotInfo; out ErrorMsg: string): Boolean;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Item: TSnapshotFileItem;
  Path, Text: string;
begin
  Result := False;
  ErrorMsg := '';
  Root := TJSONObject.Create;
  try
    Root.AddPair('schema_version', TJSONNumber.Create(1));
    Root.AddPair('created_at', Info.CreatedAt);
    Root.AddPair('ib_label', Info.IbLabel);
    Root.AddPair('line_id', Info.LineId);
    Root.AddPair('ib_root', Info.IbRoot);
    Root.AddPair('extforms_root', Info.ExtFormsRoot);
    Root.AddPair('note',
      '1Cv7.MD хранится только как reference; при RestoreWorkingSnapshot не восстанавливается.');

    Arr := TJSONArray.Create;
    Root.AddPair('files', Arr);
    for Item in Info.Files do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('stem', Item.Stem);
      Obj.AddPair('kind', KindToStr(Item.Kind));
      Obj.AddPair('original_path', Item.OriginalPath);
      Obj.AddPair('stored_as', Item.StoredAs);
      if Item.Version = '' then
        Obj.AddPair('version', TJSONNull.Create)
      else
        Obj.AddPair('version', Item.Version);
      Obj.AddPair('restorable', TJSONBool.Create(Item.Restorable));
      Arr.AddElement(Obj);
    end;

    Path := TPath.Combine(Info.SnapshotDir, 'manifest.json');
    Text := Root.Format(2);
    TFile.WriteAllText(Path, Text, TEncoding.UTF8);
    Result := True;
  except
    on E: Exception do
      ErrorMsg := E.Message;
  end;
  Root.Free;
end;

function CreateWorkingSnapshot(
  const IbLabel, LineId, MainErtPath: string;
  out Info: TWorkingSnapshotInfo;
  out ErrorMsg: string
): Boolean;
var
  FilesDir, Dest: string;
  Item: TSnapshotFileItem;
  Copied: Integer;
begin
  Result := False;
  ErrorMsg := '';
  Info := Default(TWorkingSnapshotInfo);

  if Trim(IbLabel) = '' then
  begin
    ErrorMsg := 'Не задан экземпляр (Злобин/Стрелец/Сургут).';
    Exit;
  end;

  Info.IbLabel := IbLabel;
  Info.LineId := LineId;
  Info.ExtFormsRoot := ExtFormsRootFromErt(MainErtPath);
  Info.IbRoot := IbRootFromExtForms(Info.ExtFormsRoot);
  if Info.ExtFormsRoot = '' then
  begin
    ErrorMsg :=
      'Не удалось определить ExtForms по пути модуля. Укажите путь к главному ERT.';
    Exit;
  end;

  Info.Files := CollectSnapshotFiles(LineId, MainErtPath, Info.ExtFormsRoot, Info.IbRoot);
  if Length(Info.Files) = 0 then
  begin
    ErrorMsg := 'Не найдено ни одного файла для снимка.';
    Exit;
  end;

  try
    EnsureAppDirectories;
    Info.SnapshotDir := WorkingSnapshotDir(IbLabel);
    if TDirectory.Exists(Info.SnapshotDir) then
      TDirectory.Delete(Info.SnapshotDir, True);
    FilesDir := TPath.Combine(Info.SnapshotDir, 'files');
    ForceDirectories(FilesDir);

    Copied := 0;
    for Item in Info.Files do
    begin
      if not TFile.Exists(Item.OriginalPath) then
      begin
        LogWarn('Snapshot skip missing: ' + Item.OriginalPath);
        Continue;
      end;
      Dest := TPath.Combine(FilesDir, Item.StoredAs);
      TFile.Copy(Item.OriginalPath, Dest, True);
      Inc(Copied);
      LogInfo(Format('Snapshot %s: %s -> %s (ver=%s)',
        [IbLabel, Item.OriginalPath, Dest, IfThen(Item.Version = '', '-', Item.Version)]));
    end;

    if Copied = 0 then
    begin
      ErrorMsg := 'Не удалось скопировать файлы снимка.';
      Exit;
    end;

    // пересобрать список только реально скопированных
    // (оставляем Info.Files как планировали — manifest отражает intent + paths)

    Info.CreatedAt := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
    if not WriteManifest(Info, ErrorMsg) then
      Exit;

    LogInfo('Working snapshot OK: ' + Info.SnapshotDir);
    Result := True;
  except
    on E: Exception do
    begin
      ErrorMsg := E.Message;
      LogError('CreateWorkingSnapshot: ' + ErrorMsg);
    end;
  end;
end;

function LoadWorkingSnapshotManifest(const IbLabel: string;
  out Info: TWorkingSnapshotInfo; out ErrorMsg: string): Boolean;
var
  Path, Text: string;
  Root: TJSONObject;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  Item: TSnapshotFileItem;
  VerVal: TJSONValue;
begin
  Result := False;
  ErrorMsg := '';
  Info := Default(TWorkingSnapshotInfo);
  Info.SnapshotDir := WorkingSnapshotDir(IbLabel);
  Path := TPath.Combine(Info.SnapshotDir, 'manifest.json');
  if not TFile.Exists(Path) then
  begin
    ErrorMsg := 'Снимок не найден: ' + Path;
    Exit;
  end;

  Text := TFile.ReadAllText(Path, TEncoding.UTF8);
  Root := TJSONObject.ParseJSONValue(Text) as TJSONObject;
  if Root = nil then
  begin
    ErrorMsg := 'Некорректный manifest.json снимка';
    Exit;
  end;
  try
    Info.IbLabel := Root.GetValue<string>('ib_label', IbLabel);
    Info.LineId := Root.GetValue<string>('line_id', '');
    Info.IbRoot := Root.GetValue<string>('ib_root', '');
    Info.ExtFormsRoot := Root.GetValue<string>('extforms_root', '');
    Info.CreatedAt := Root.GetValue<string>('created_at', '');
    Arr := Root.Values['files'] as TJSONArray;
    SetLength(Info.Files, 0);
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
      begin
        Obj := Arr.Items[I] as TJSONObject;
        if Obj = nil then
          Continue;
        Item.Stem := Obj.GetValue<string>('stem', '');
        Item.Kind := StrToKind(Obj.GetValue<string>('kind', 'ert'));
        Item.OriginalPath := Obj.GetValue<string>('original_path', '');
        Item.StoredAs := Obj.GetValue<string>('stored_as', '');
        VerVal := Obj.Values['version'];
        if (VerVal = nil) or (VerVal is TJSONNull) then
          Item.Version := ''
        else
          Item.Version := VerVal.Value;
        Item.Restorable := Obj.GetValue<Boolean>('restorable', Item.Kind = sfErt);
        // страховка: MD никогда не restorable
        if Item.Kind = sfMd then
          Item.Restorable := False;
        AddItem(Info.Files, Item);
      end;
    Result := True;
  finally
    Root.Free;
  end;
end;

function RestoreWorkingSnapshot(
  const IbLabel: string;
  out RestoredCount: Integer;
  out ErrorMsg: string
): Boolean;
var
  Info: TWorkingSnapshotInfo;
  Item: TSnapshotFileItem;
  Src, DestDir: string;
begin
  Result := False;
  RestoredCount := 0;
  ErrorMsg := '';

  if not LoadWorkingSnapshotManifest(IbLabel, Info, ErrorMsg) then
    Exit;

  try
    for Item in Info.Files do
    begin
      // Жёсткое правило: 1Cv7.MD и любые non-restorable не трогаем
      if not Item.Restorable then
      begin
        LogInfo('Restore skip (not restorable): ' + Item.Stem);
        Continue;
      end;
      if Item.Kind = sfMd then
      begin
        LogInfo('Restore skip MD: ' + Item.Stem);
        Continue;
      end;
      if SameText(Item.Stem, '1Cv7.MD') or EndsText('.MD', UpperCase(Item.StoredAs)) then
      begin
        LogWarn('Restore blocked for MD file: ' + Item.StoredAs);
        Continue;
      end;

      Src := TPath.Combine(TPath.Combine(Info.SnapshotDir, 'files'), Item.StoredAs);
      if not TFile.Exists(Src) then
      begin
        LogWarn('Restore missing stored file: ' + Src);
        Continue;
      end;
      if Trim(Item.OriginalPath) = '' then
      begin
        LogWarn('Restore no original_path for ' + Item.Stem);
        Continue;
      end;

      DestDir := ExtractFilePath(Item.OriginalPath);
      if DestDir <> '' then
        ForceDirectories(DestDir);
      TFile.Copy(Src, Item.OriginalPath, True);
      Inc(RestoredCount);
      LogInfo('Restore ERT: ' + Src + ' -> ' + Item.OriginalPath);
    end;

    if RestoredCount = 0 then
    begin
      ErrorMsg := 'Не восстановлено ни одного ERT (проверьте снимок).';
      Exit;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      ErrorMsg := E.Message;
      LogError('RestoreWorkingSnapshot: ' + ErrorMsg);
    end;
  end;
end;

end.
