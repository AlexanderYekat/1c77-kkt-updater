unit kktUpdater1c77;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Grids,
  Config, Manifest, ModuleCatalog, UpdateErt, UpdateService;

type
  TGridRowKind = (gkErt, gkService);

  TGridRowInfo = record
    Kind: TGridRowKind;
    IbLabel: string;
    ComponentId: string;
    ModuleStem: string;
    ErtPath: string;
    LineId: string; // LineIdAtol / LineIdShtrih; для службы — пусто
  end;

  TfrmMain = class(TForm)
    pnlPaths: TPanel;
    lblPaths: TLabel;
    lblZlobin: TLabel;
    edtZlobin: TEdit;
    btnBrowseZlobin: TButton;
    lblStrelets: TLabel;
    edtStrelets: TEdit;
    btnBrowseStrelets: TButton;
    lblSurgut: TLabel;
    edtSurgut: TEdit;
    btnBrowseSurgut: TButton;
    btnDetectRegistry: TButton;
    btnSavePaths: TButton;
    pnlServices: TPanel;
    lblServices: TLabel;
    lblAtolSvc: TLabel;
    edtAtolExe: TEdit;
    btnBrowseAtolExe: TButton;
    edtAtolBaseUrl: TEdit;
    lblShtrihSvc: TLabel;
    edtShtrihExe: TEdit;
    btnBrowseShtrihExe: TButton;
    edtShtrihBaseUrl: TEdit;
    grdUpdates: TStringGrid;
    btnCheck: TButton;
    btnUpdateSelected: TButton;
    btnUpdateAll: TButton;
    btnForceDowngrade: TButton;
    btnSnapshotWorking: TButton;
    btnRestoreWorking: TButton;
    btnOpenSnapshots: TButton;
    lblSnapshotHint: TLabel;
    memLog: TMemo;
    dlgOpen: TOpenDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnBrowseZlobinClick(Sender: TObject);
    procedure btnBrowseStreletsClick(Sender: TObject);
    procedure btnBrowseSurgutClick(Sender: TObject);
    procedure btnBrowseAtolExeClick(Sender: TObject);
    procedure btnBrowseShtrihExeClick(Sender: TObject);
    procedure btnDetectRegistryClick(Sender: TObject);
    procedure btnSavePathsClick(Sender: TObject);
    procedure btnCheckClick(Sender: TObject);
    procedure btnUpdateSelectedClick(Sender: TObject);
    procedure btnUpdateAllClick(Sender: TObject);
    procedure btnForceDowngradeClick(Sender: TObject);
    procedure btnSnapshotWorkingClick(Sender: TObject);
    procedure btnRestoreWorkingClick(Sender: TObject);
    procedure btnOpenSnapshotsClick(Sender: TObject);
  private
    FConfig: TAppConfig;
    FManifest: TStableManifest;
    FHasManifest: Boolean;
    FRows: TArray<TGridRowInfo>;
    FShowAtol: Boolean;
    FShowSurgut: Boolean;
    procedure InitUiCaptions;
    procedure InitGridHeader;
    procedure AppendStatus(const Msg: string);
    procedure LoadPathsFromConfig;
    procedure ApplyPathsToConfig;
    procedure DiscoverAndStoreLineModules(Line: TModuleLine; const IbLabel, AnchorPath: string);
    function BrowseErt(var Edit: TEdit): Boolean;
    function BrowseExe(var Edit: TEdit): Boolean;
    function ExtFormsRootFromErtOrEmpty(const ErtPath: string): string;
    procedure AddIbModulesFromCatalog(const IbLabel: string; Line: TModuleLine;
      const AnchorPath: string; var Rows: TArray<TGridRowInfo>; var N: Integer);
    procedure AddServiceRowIfConfigured(const ComponentId, DisplayName: string;
      var Rows: TArray<TGridRowInfo>; var N: Integer);
    procedure RebuildRows;
    procedure RefreshGrid;
    function ReadInstalledVersion(const ErtPath, ComponentId: string;
      out VerText: string; out ErrText: string): Boolean;
    function RowInChannel(const Row: TGridRowInfo; out Comp: TComponentManifest): Boolean;
    function UpdateOneRow(const Row: TGridRowInfo; const Comp: TComponentManifest;
      const PreparedText: string; ForceDowngrade: Boolean = False): TUpdateErtResult;
    function UpdateOneServiceRow(const Row: TGridRowInfo; const Comp: TComponentManifest;
      ForceDowngrade: Boolean = False): TUpdateServiceResult;
    procedure RunUpdates(OnlySelected: Boolean; ForceDowngrade: Boolean = False);
    function SelectedIbContext(out IbLabel, LineId, MainPath: string): Boolean;
    procedure ApplyPathPanelVisibility(const HasZlobin, HasStrelets, HasSurgut: Boolean);
    procedure LayoutPanels;
    procedure DetectBasesInRegistry(out HasZlobin, HasStrelets, HasSurgut: Boolean;
      FillPaths: Boolean);
    procedure RefreshSnapshotStatusHint;
  public
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses
  System.Generics.Collections,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  Winapi.ShellAPI,
  AppConsts,
  AppPaths,
  AppLog,
  RegistryBases,
  VersionParse,
  ErtStorage,
  WorkingSnapshot;

const
  COL_INSTANCE = 0;
  COL_INSTALLED = 1;
  COL_AVAILABLE = 2;
  COL_STATE = 3;

function ReadExeFileVersion: string;
var
  InfoSize, Dummy: DWORD;
  Buffer: Pointer;
  Fixed: PVSFixedFileInfo;
  Len: UINT;
begin
  Result := '';
  InfoSize := GetFileVersionInfoSize(PChar(ParamStr(0)), Dummy);
  if InfoSize = 0 then
    Exit;
  GetMem(Buffer, InfoSize);
  try
    if not GetFileVersionInfo(PChar(ParamStr(0)), 0, InfoSize, Buffer) then
      Exit;
    if VerQueryValue(Buffer, '\', Pointer(Fixed), Len) and (Fixed <> nil) then
      Result := Format('%d.%d.%d.%d', [
        HiWord(Fixed.dwFileVersionMS),
        LoWord(Fixed.dwFileVersionMS),
        HiWord(Fixed.dwFileVersionLS),
        LoWord(Fixed.dwFileVersionLS)]);
  finally
    FreeMem(Buffer);
  end;
end;

function AppVersionCaption: string;
var
  Ver: string;
begin
  Ver := ReadExeFileVersion;
  if Ver = '' then
    Ver := AppVersion;
  Result := AppName + '  v' + Ver;
end;

procedure TfrmMain.FormCreate(Sender: TObject);
var
  Err: string;
  HasZ, HasS, HasG: Boolean;
begin
  Caption := AppVersionCaption;
  InitUiCaptions;
  EnsureAppDirectories;
  InitGridHeader;
  FHasManifest := False;
  FManifest.Init;
  FShowAtol := True;
  FShowSurgut := True;
  SetLength(FRows, 0);

  if not LoadOrCreateConfig(FConfig, Err) then
  begin
    AppendStatus('Ошибка config: ' + Err);
    FConfig := TAppConfig.Create;
  end
  else
    AppendStatus('Конфиг: ' + ConfigFilePath);

  LoadPathsFromConfig;
  ApplyPathsToConfig; // подставить дефолты installer в память (на диск — по «Сохранить»)
  DetectBasesInRegistry(HasZ, HasS, HasG, False);
  ApplyPathPanelVisibility(HasZ, HasS, HasG);
  LayoutPanels;
  RefreshGrid;
  RefreshSnapshotStatusHint;
  LogInfo('Updater started');
end;

procedure TfrmMain.InitUiCaptions;
begin
  lblPaths.Caption := 'Пути модулей (локальный конфиг)';
  lblZlobin.Caption := LabelZlobin + ' (ATOL)';
  lblStrelets.Caption := LabelStrelets + ' (ATOL)';
  lblSurgut.Caption := LabelSurgut + ' (Штрих)';
  btnBrowseZlobin.Caption := 'Обзор...';
  btnBrowseStrelets.Caption := 'Обзор...';
  btnBrowseSurgut.Caption := 'Обзор...';
  btnDetectRegistry.Caption := 'Найти базы в реестре';
  btnSavePaths.Caption := 'Сохранить пути';
  btnCheck.Caption := 'Проверить обновления';
  btnUpdateSelected.Caption := 'Обновить выбранное';
  btnUpdateAll.Caption := 'Обновить всё';
  btnForceDowngrade.Caption := 'Принуд. downgrade';
  btnForceDowngrade.Hint :=
    'Только для выделенной строки со статусом «локальная версия новее».'#13#10 +
    'Запишет версию из канала, даже если она старше локальной (после подтверждения).';
  btnForceDowngrade.ShowHint := True;
  btnSnapshotWorking.Caption := 'Снимок базы';
  btnSnapshotWorking.Hint :=
    'Строка в таблице выбирает только базу (Злобин/Стрелец/Сургут).'#13#10 +
    'В снимок попадают все ERT из ModuleCatalog этой базы + 1Cv7.MD (MD только архив).';
  btnSnapshotWorking.ShowHint := True;
  btnRestoreWorking.Caption := 'Откат снимка базы';
  btnRestoreWorking.Hint :=
    'Восстанавливает все ERT из снимка выбранной базы. 1Cv7.MD не восстанавливается.';
  btnRestoreWorking.ShowHint := True;
  btnOpenSnapshots.Caption := 'Папка снимков';
  btnOpenSnapshots.Hint :=
    'Открыть каталог со снимками в Проводнике.'#13#10 +
    'Если выделена строка базы и снимок есть — откроется папка этой базы.';
  btnOpenSnapshots.ShowHint := True;
  if Assigned(lblSnapshotHint) then
    lblSnapshotHint.Caption :=
      'Снимок/откат: выделите любую строку нужной базы. Статус снимков — в строке ниже после обновления списка.';
  if Assigned(lblServices) then
    lblServices.Caption := 'Приложения ККТ (exe / base_url)';
  if Assigned(lblAtolSvc) then
    lblAtolSvc.Caption := LabelAtolService;
  if Assigned(lblShtrihSvc) then
    lblShtrihSvc.Caption := LabelShtrihService;
  if Assigned(edtAtolBaseUrl) then
    edtAtolBaseUrl.TextHint := DefaultServiceBaseUrl;
  if Assigned(edtShtrihBaseUrl) then
    edtShtrihBaseUrl.TextHint := DefaultServiceBaseUrl;
  if Assigned(edtAtolExe) then
    edtAtolExe.TextHint := DefaultServiceExePath;
  if Assigned(edtShtrihExe) then
    edtShtrihExe.TextHint := DefaultServiceExePath;
  dlgOpen.Title := 'Выберите файл ERT';
  dlgOpen.Filter := 'ERT|*.ert|Все файлы|*.*';
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FManifest.Clear;
  FConfig.Free;
end;

procedure TfrmMain.InitGridHeader;
begin
  grdUpdates.ColCount := 4;
  grdUpdates.RowCount := 2;
  grdUpdates.FixedRows := 1;
  grdUpdates.FixedCols := 0;
  grdUpdates.Options := grdUpdates.Options + [goRowSelect, goThumbTracking] - [goRangeSelect];
  grdUpdates.Cells[COL_INSTANCE, 0] := 'Экземпляр / модуль';
  grdUpdates.Cells[COL_INSTALLED, 0] := 'Установлено';
  grdUpdates.Cells[COL_AVAILABLE, 0] := 'Доступно';
  grdUpdates.Cells[COL_STATE, 0] := 'Состояние';
  grdUpdates.ColWidths[COL_INSTANCE] := 340;
  grdUpdates.ColWidths[COL_INSTALLED] := 150;
  grdUpdates.ColWidths[COL_AVAILABLE] := 140;
  grdUpdates.ColWidths[COL_STATE] := 200;
end;

procedure TfrmMain.AppendStatus(const Msg: string);
begin
  memLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + Msg);
  LogInfo(Msg);
end;

procedure TfrmMain.LoadPathsFromConfig;
var
  Svc: TComponentConfig;
  DefExe: string;
begin
  edtZlobin.Text := FConfig.GetInstancePath(ComponentAtolModule, LabelZlobin);
  edtStrelets.Text := FConfig.GetInstancePath(ComponentAtolModule, LabelStrelets);
  edtSurgut.Text := FConfig.GetInstancePath(ComponentShtrihModule, LabelSurgut);

  // Пустые поля — как installer_kktserver.iss: Program Files\CTO_KSM\kktserver + :2580
  DefExe := DefaultServiceExePath;

  Svc := FConfig.GetServiceConfig(ComponentAtolService);
  if Trim(Svc.Exe) <> '' then
    edtAtolExe.Text := Svc.Exe
  else
    edtAtolExe.Text := DefExe;
  if Trim(Svc.BaseUrl) <> '' then
    edtAtolBaseUrl.Text := Svc.BaseUrl
  else
    edtAtolBaseUrl.Text := DefaultServiceBaseUrl;

  Svc := FConfig.GetServiceConfig(ComponentShtrihService);
  if Trim(Svc.Exe) <> '' then
    edtShtrihExe.Text := Svc.Exe
  else
    edtShtrihExe.Text := DefExe;
  if Trim(Svc.BaseUrl) <> '' then
    edtShtrihBaseUrl.Text := Svc.BaseUrl
  else
    edtShtrihBaseUrl.Text := DefaultServiceBaseUrl;
end;

procedure TfrmMain.DiscoverAndStoreLineModules(Line: TModuleLine;
  const IbLabel, AnchorPath: string);
var
  Root: string;
  Entry: TModuleCatalogEntry;
  Path, ConfigPath: string;
begin
  Root := ExtFormsRootFromErtOrEmpty(AnchorPath);
  for Entry in ModulesForLine(Line) do
  begin
    ConfigPath := FConfig.GetInstancePath(Entry.ComponentId, IbLabel);
    if SameText(Entry.ComponentId, ComponentAtolModule) or
       SameText(Entry.ComponentId, ComponentShtrihModule) then
      Path := ResolveModulePath(Root, AnchorPath, Entry)
    else
      Path := ResolveModulePath(Root, ConfigPath, Entry);

    // Не затираем сохранённый путь пустым, если файл временно не найден
    if Trim(Path) <> '' then
      FConfig.SetInstancePath(Entry.ComponentId, IbLabel, Path)
    else if Trim(ConfigPath) = '' then
      FConfig.SetInstancePath(Entry.ComponentId, IbLabel, '');
  end;
end;

function EffectiveServiceBaseUrl(const Exe, BaseUrl: string): string;
begin
  Result := Trim(BaseUrl);
  if Result = '' then
    Result := DefaultServiceBaseUrl;
end;

function EffectiveServiceExe(const Exe: string): string;
begin
  Result := Trim(Exe);
  if Result = '' then
    Result := DefaultServiceExePath;
end;

procedure TfrmMain.ApplyPathsToConfig;
begin
  FConfig.SetInstancePath(ComponentAtolModule, LabelZlobin, edtZlobin.Text);
  FConfig.SetInstancePath(ComponentAtolModule, LabelStrelets, edtStrelets.Text);
  FConfig.SetInstancePath(ComponentShtrihModule, LabelSurgut, edtSurgut.Text);

  FConfig.SetServiceConfig(ComponentAtolService,
    EffectiveServiceExe(edtAtolExe.Text),
    EffectiveServiceBaseUrl(edtAtolExe.Text, edtAtolBaseUrl.Text));
  FConfig.SetServiceConfig(ComponentShtrihService,
    EffectiveServiceExe(edtShtrihExe.Text),
    EffectiveServiceBaseUrl(edtShtrihExe.Text, edtShtrihBaseUrl.Text));

  if FShowAtol then
  begin
    DiscoverAndStoreLineModules(mlAtol, LabelZlobin, Trim(edtZlobin.Text));
    DiscoverAndStoreLineModules(mlAtol, LabelStrelets, Trim(edtStrelets.Text));
  end;
  if FShowSurgut then
    DiscoverAndStoreLineModules(mlShtrih, LabelSurgut, Trim(edtSurgut.Text));
end;

function TfrmMain.BrowseErt(var Edit: TEdit): Boolean;
begin
  Result := False;
  dlgOpen.Title := 'Выберите файл ERT';
  dlgOpen.Filter := 'ERT|*.ert|Все файлы|*.*';
  dlgOpen.FileName := Edit.Text;
  if dlgOpen.Execute then
  begin
    Edit.Text := dlgOpen.FileName;
    Result := True;
  end;
end;

function TfrmMain.BrowseExe(var Edit: TEdit): Boolean;
begin
  Result := False;
  dlgOpen.Title := 'Выберите EXE службы';
  dlgOpen.Filter := 'EXE|*.exe|Все файлы|*.*';
  dlgOpen.FileName := Edit.Text;
  if dlgOpen.Execute then
  begin
    Edit.Text := dlgOpen.FileName;
    Result := True;
  end;
end;

function TfrmMain.ExtFormsRootFromErtOrEmpty(const ErtPath: string): string;
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
  Result := '';
end;

procedure TfrmMain.AddIbModulesFromCatalog(const IbLabel: string; Line: TModuleLine;
  const AnchorPath: string; var Rows: TArray<TGridRowInfo>; var N: Integer);
var
  Root: string;
  Entry: TModuleCatalogEntry;
  Row: TGridRowInfo;
  Path, ConfigPath: string;
begin
  Root := ExtFormsRootFromErtOrEmpty(AnchorPath);
  for Entry in ModulesForLine(Line) do
  begin
    ConfigPath := FConfig.GetInstancePath(Entry.ComponentId, IbLabel);
    if SameText(Entry.ComponentId, ComponentAtolModule) or
       SameText(Entry.ComponentId, ComponentShtrihModule) then
      Path := ResolveModulePath(Root, AnchorPath, Entry)
    else
      Path := ResolveModulePath(Root, ConfigPath, Entry);

    // Показываем строку, если есть путь/якорь ИБ или файл найден рядом
    if (Trim(AnchorPath) = '') and (Trim(Path) = '') then
      Continue;

    Row.Kind := gkErt;
    Row.IbLabel := IbLabel;
    Row.ComponentId := Entry.ComponentId;
    Row.ModuleStem := Entry.FileStem;
    Row.ErtPath := Path;
    Row.LineId := LineIdOf(Line);
    SetLength(Rows, N + 1);
    Rows[N] := Row;
    Inc(N);
  end;
end;

procedure TfrmMain.AddServiceRowIfConfigured(const ComponentId, DisplayName: string;
  var Rows: TArray<TGridRowInfo>; var N: Integer);
var
  Svc: TComponentConfig;
  Row: TGridRowInfo;
begin
  Svc := FConfig.GetServiceConfig(ComponentId);
  if not Svc.HasServiceConfig then
    Exit;
  Row.Kind := gkService;
  Row.IbLabel := DisplayName;
  Row.ComponentId := ComponentId;
  Row.ModuleStem := DisplayName;
  Row.ErtPath := Svc.Exe;
  Row.LineId := '';
  SetLength(Rows, N + 1);
  Rows[N] := Row;
  Inc(N);
end;

procedure TfrmMain.RebuildRows;
var
  Rows: TArray<TGridRowInfo>;
  N: Integer;
begin
  // Сначала из UI в FConfig — иначе свежие exe/base_url не попадут в грид
  ApplyPathsToConfig;

  SetLength(Rows, 0);
  N := 0;

  // Приложения ККТ сверху — иначе их не видно за списком ERT
  AddServiceRowIfConfigured(ComponentAtolService, LabelAtolService, Rows, N);
  AddServiceRowIfConfigured(ComponentShtrihService, LabelShtrihService, Rows, N);

  if FShowAtol then
  begin
    AddIbModulesFromCatalog(LabelZlobin, mlAtol, Trim(edtZlobin.Text), Rows, N);
    AddIbModulesFromCatalog(LabelStrelets, mlAtol, Trim(edtStrelets.Text), Rows, N);
  end;
  if FShowSurgut then
    AddIbModulesFromCatalog(LabelSurgut, mlShtrih, Trim(edtSurgut.Text), Rows, N);

  FRows := Rows;
end;

function TfrmMain.ReadInstalledVersion(const ErtPath, ComponentId: string;
  out VerText: string; out ErrText: string): Boolean;
var
  Text: string;
  Id: TModuleIdentity;
  LegacyVer: string;
  Entry: TModuleCatalogEntry;
begin
  Result := False;
  VerText := '—';
  ErrText := '';
  if Trim(ErtPath) = '' then
    Exit;
  if not TFile.Exists(ErtPath) then
  begin
    VerText := 'файл не найден';
    Exit;
  end;
  try
    Text := ReadErtModuleText(ErtPath);
    Id := ExtractModuleIdentity(Text);
    if Id.HasComponent and Id.HasVersion then
    begin
      VerText := Id.VersionRaw;
      Result := True;
      Exit;
    end;

    if TryFindModuleById(ComponentId, Entry) and
       HasAnyLegacyStemVerMarker(Text, Entry.LegacyStems, LegacyVer) then
    begin
      VerText := LegacyVer + ' (legacy)';
      Result := True;
      Exit;
    end;

    if Id.HasVersion then
      VerText := Id.VersionRaw
    else
      VerText := 'в ERT нет version';
    Result := True;
  except
    on E: Exception do
    begin
      VerText := 'ошибка чтения';
      ErrText := E.Message;
    end;
  end;
end;

function TfrmMain.RowInChannel(const Row: TGridRowInfo;
  out Comp: TComponentManifest): Boolean;
begin
  Comp := Default(TComponentManifest);
  Result := FHasManifest and FManifest.TryGet(Row.ComponentId, Comp);
end;

procedure TfrmMain.RefreshGrid;
var
  R, GridRow: Integer;
  Ver, Err, Available, State, InstalledClean: string;
  Comp: TComponentManifest;
  InChannel: Boolean;
  Cmp: Integer;
  Svc: TComponentConfig;
begin
  RebuildRows;
  if Length(FRows) = 0 then
    grdUpdates.RowCount := 2
  else
    grdUpdates.RowCount := Length(FRows) + 1;

  for R := 0 to High(FRows) do
  begin
    GridRow := R + 1;
    Ver := '—';
    Err := '';
    if FRows[R].Kind = gkService then
      grdUpdates.Cells[COL_INSTANCE, GridRow] := FRows[R].IbLabel
    else
      grdUpdates.Cells[COL_INSTANCE, GridRow] :=
        FRows[R].IbLabel + ' / ' + FRows[R].ModuleStem;

    if FRows[R].Kind = gkService then
    begin
      Svc := FConfig.GetServiceConfig(FRows[R].ComponentId);
      if ReadInstalledServiceVersion(Svc, FRows[R].ComponentId, Ver, Err, True) then
        { ok }
      else if Trim(Svc.Exe) = '' then
        Ver := '—'
      else if not TFile.Exists(Svc.Exe) then
        Ver := 'файл не найден'
      else if Err <> '' then
        Ver := 'нет version'
      else
        Ver := 'нет version';
    end
    else
      ReadInstalledVersion(FRows[R].ErtPath, FRows[R].ComponentId, Ver, Err);

    grdUpdates.Cells[COL_INSTALLED, GridRow] := Ver;

    InChannel := RowInChannel(FRows[R], Comp);
    if InChannel then
      Available := Comp.Version
    else
      Available := '—';
    grdUpdates.Cells[COL_AVAILABLE, GridRow] := Available;

    if FRows[R].Kind = gkService then
    begin
      Svc := FConfig.GetServiceConfig(FRows[R].ComponentId);
      if Trim(Svc.Exe) = '' then
        State := 'нет пути'
      else if SameText(Ver, 'файл не найден') then
        State := 'файл не найден'
      else if (Err <> '') and SameText(Ver, 'нет version') then
        State := 'ошибка'
      else if not FHasManifest then
        State := 'не проверен'
      else if not InChannel then
        State := 'нет в канале'
      else if SameText(Ver, 'нет version') or (Ver = '—') then
        State := 'обновление'
      else
      begin
        Cmp := CompareVersionStrings(Available, Ver);
        if Cmp > 0 then
          State := 'обновление'
        else if Cmp = 0 then
          State := 'актуально'
        else
          State := 'локальная версия новее';
      end;
    end
    else if Trim(FRows[R].ErtPath) = '' then
      State := 'нет пути'
    else if SameText(Ver, 'файл не найден') then
      State := 'файл не найден'
    else if SameText(Ver, 'ошибка чтения') then
      State := 'ошибка'
    else if not FHasManifest then
      State := 'не проверен'
    else if not InChannel then
    begin
      // В канале нет — даже если локально без version
      if SameText(Ver, 'нет version') or SameText(Ver, 'в ERT нет version') then
        State := 'версия не задана'
      else
        State := 'нет в канале';
    end
    else if SameText(Ver, 'в ERT нет version') or SameText(Ver, 'нет version') then
      // В канале есть, локально version нет (старый ERT) — можно ставить
      State := 'обновление'
    else
    begin
      InstalledClean := StringReplace(Ver, ' (legacy)', '', []);
      Cmp := CompareVersionStrings(Available, InstalledClean);
      if Cmp > 0 then
        State := 'обновление'
      else if Cmp = 0 then
        State := 'актуально'
      else
        State := 'локальная версия новее';
    end;
    grdUpdates.Cells[COL_STATE, GridRow] := State;

    if Err <> '' then
      AppendStatus(FRows[R].IbLabel + '/' + FRows[R].ModuleStem + ': ' + Err);
  end;
end;

procedure TfrmMain.btnBrowseZlobinClick(Sender: TObject);
begin
  if BrowseErt(edtZlobin) then
    RefreshGrid;
end;

procedure TfrmMain.btnBrowseStreletsClick(Sender: TObject);
begin
  if BrowseErt(edtStrelets) then
    RefreshGrid;
end;

procedure TfrmMain.btnBrowseSurgutClick(Sender: TObject);
begin
  if BrowseErt(edtSurgut) then
    RefreshGrid;
end;

procedure TfrmMain.btnBrowseAtolExeClick(Sender: TObject);
begin
  if BrowseExe(edtAtolExe) then
    RefreshGrid;
end;

procedure TfrmMain.btnBrowseShtrihExeClick(Sender: TObject);
begin
  if BrowseExe(edtShtrihExe) then
    RefreshGrid;
end;

procedure TfrmMain.RefreshSnapshotStatusHint;
var
  Labels: TArray<string>;
  Lbl, Part, Err, Line: string;
  Info: TWorkingSnapshotInfo;
  N: Integer;
begin
  if not Assigned(lblSnapshotHint) then
    Exit;

  SetLength(Labels, 0);
  if FShowAtol then
  begin
    N := Length(Labels);
    SetLength(Labels, N + 2);
    Labels[N] := LabelZlobin;
    Labels[N + 1] := LabelStrelets;
  end;
  if FShowSurgut then
  begin
    N := Length(Labels);
    SetLength(Labels, N + 1);
    Labels[N] := LabelSurgut;
  end;

  Line := '';
  for Lbl in Labels do
  begin
    if WorkingSnapshotExists(Lbl) and LoadWorkingSnapshotManifest(Lbl, Info, Err) then
      Part := Lbl + ': снимок ' + Info.CreatedAt
    else if WorkingSnapshotExists(Lbl) then
      Part := Lbl + ': снимок есть'
    else
      Part := Lbl + ': снимка нет';
    if Line <> '' then
      Line := Line + ' | ';
    Line := Line + Part;
  end;

  if Line = '' then
    lblSnapshotHint.Caption :=
      'Снимок базы: выделите строку ИБ → «Снимок базы». Откат — «Откат снимка базы».'
  else
    lblSnapshotHint.Caption := 'Рабочий снимок (откат): ' + Line;
end;

procedure TfrmMain.ApplyPathPanelVisibility(const HasZlobin, HasStrelets, HasSurgut: Boolean);
var
  ShowAtol, ShowSurgut: Boolean;
  RowTop: Integer;
const
  RowH = 29;
  FirstRowTop = 25;
begin
  ShowAtol := not (HasSurgut and (not HasZlobin) and (not HasStrelets));
  ShowSurgut := not (HasZlobin and HasStrelets and (not HasSurgut));

  FShowAtol := ShowAtol;
  FShowSurgut := ShowSurgut;

  lblZlobin.Visible := ShowAtol;
  edtZlobin.Visible := ShowAtol;
  btnBrowseZlobin.Visible := ShowAtol;
  lblStrelets.Visible := ShowAtol;
  edtStrelets.Visible := ShowAtol;
  btnBrowseStrelets.Visible := ShowAtol;

  lblSurgut.Visible := ShowSurgut;
  edtSurgut.Visible := ShowSurgut;
  btnBrowseSurgut.Visible := ShowSurgut;

  RowTop := FirstRowTop;
  if ShowAtol then
  begin
    lblZlobin.Top := RowTop + 3;
    edtZlobin.Top := RowTop;
    btnBrowseZlobin.Top := RowTop - 1;
    Inc(RowTop, RowH);
    lblStrelets.Top := RowTop + 3;
    edtStrelets.Top := RowTop;
    btnBrowseStrelets.Top := RowTop - 1;
    Inc(RowTop, RowH);
  end;
  if ShowSurgut then
  begin
    lblSurgut.Top := RowTop + 3;
    edtSurgut.Top := RowTop;
    btnBrowseSurgut.Top := RowTop - 1;
    Inc(RowTop, RowH);
  end;

  btnDetectRegistry.Top := RowTop + 4;
  btnSavePaths.Top := RowTop + 4;
  pnlPaths.Height := RowTop + 34;
  LayoutPanels;
  RefreshSnapshotStatusHint;
end;

procedure TfrmMain.LayoutPanels;
var
  Y, BottomOfButtons: Integer;
begin
  if not Assigned(pnlServices) then
  begin
    grdUpdates.Top := pnlPaths.Top + pnlPaths.Height + 8;
    Exit;
  end;
  pnlServices.Top := pnlPaths.Top + pnlPaths.Height + 4;
  pnlServices.Left := pnlPaths.Left;
  pnlServices.Width := pnlPaths.Width;
  Y := pnlServices.Top + pnlServices.Height + 8;
  grdUpdates.Top := Y;
  BottomOfButtons := btnCheck.Top - 8;
  if BottomOfButtons > Y + 80 then
    grdUpdates.Height := BottomOfButtons - Y;
end;

procedure TfrmMain.DetectBasesInRegistry(out HasZlobin, HasStrelets, HasSurgut: Boolean;
  FillPaths: Boolean);
var
  Items: TIbInfoArray;
  Err: string;
  Info: TIbInfo;
  Candidates: TArray<string>;
  Best: string;
begin
  HasZlobin := False;
  HasStrelets := False;
  HasSurgut := False;

  if FindAtolBases(Items, Err) then
  begin
    for Info in Items do
    begin
      if SameText(Info.MatchedLabel, LabelZlobin) then
      begin
        HasZlobin := True;
        if FillPaths then
        begin
          Candidates := SuggestErtCandidates(Info.Path, DefaultAtolErtFileName);
          Best := PickBestErtCandidate(Candidates);
          if Best <> '' then
          begin
            edtZlobin.Text := Best;
            AppendStatus('Злобин: ' + Info.Title + ' → ' + Best);
          end
          else
            AppendStatus('Злобин: ' + Info.Title + ' — frATOL54_comm.ert не найден');
        end;
      end
      else if SameText(Info.MatchedLabel, LabelStrelets) then
      begin
        HasStrelets := True;
        if FillPaths then
        begin
          Candidates := SuggestErtCandidates(Info.Path, DefaultAtolErtFileName);
          Best := PickBestErtCandidate(Candidates);
          if Best <> '' then
          begin
            edtStrelets.Text := Best;
            AppendStatus('Стрелец: ' + Info.Title + ' → ' + Best);
          end
          else
            AppendStatus('Стрелец: ' + Info.Title + ' — frATOL54_comm.ert не найден');
        end;
      end;
    end;
  end
  else if FillPaths then
    AppendStatus('ATOL: ' + Err);

  if FindSurgutBases(Items, Err) then
  begin
    for Info in Items do
    begin
      HasSurgut := True;
      if FillPaths then
      begin
        Candidates := SuggestErtCandidates(Info.Path, DefaultShtrihErtFileName);
        Best := PickBestShtrihErtCandidate(Candidates);
        if Best <> '' then
        begin
          edtSurgut.Text := Best;
          AppendStatus('Сургут: ' + Info.Title + ' → ' + Best);
        end
        else
          AppendStatus('Сургут: ' + Info.Title + ' — fr_elves-12.ert не найден');
      end;
    end;
  end
  else if FillPaths then
    AppendStatus('Сургут: ' + Err);
end;

procedure TfrmMain.btnDetectRegistryClick(Sender: TObject);
var
  HasZ, HasS, HasG: Boolean;
begin
  DetectBasesInRegistry(HasZ, HasS, HasG, True);
  ApplyPathPanelVisibility(HasZ, HasS, HasG);
  ApplyPathsToConfig;
  RefreshGrid;

  if not HasZ and not HasS and not HasG then
    MessageDlg(
      'Базы Злобин/Стрелец/Сургут в Titles не найдены.',
      mtInformation, [mbOK], 0);
end;

procedure TfrmMain.btnSavePathsClick(Sender: TObject);
var
  Err: string;
begin
  ApplyPathsToConfig;
  if SaveConfig(FConfig, Err) then
  begin
    AppendStatus('Пути сохранены в config.json');
    RefreshGrid;
  end
  else
  begin
    AppendStatus('Ошибка сохранения: ' + Err);
    MessageDlg(Err, mtError, [mbOK], 0);
  end;
end;

procedure TfrmMain.btnCheckClick(Sender: TObject);
var
  Err: string;
  Url: string;
  Pair: TPair<string, TComponentManifest>;
  Summary: string;
begin
  ApplyPathsToConfig;
  Url := FConfig.EffectiveManifestUrl;
  AppendStatus('Проверка: ' + Url);
  // Освободить предыдущий словарь до загрузки (Load* считает out неинициализированным)
  FManifest.Clear;
  FHasManifest := LoadManifestFromUrl(Url, FManifest, Err);
  if not FHasManifest then
  begin
    AppendStatus('Manifest: ' + Err);
    MessageDlg(Err, mtError, [mbOK], 0);
    RefreshGrid;
    Exit;
  end;
  Summary := '';
  if FManifest.Components <> nil then
    for Pair in FManifest.Components do
    begin
      if Summary <> '' then
        Summary := Summary + '; ';
      Summary := Summary + Pair.Key + '=' + Pair.Value.Version;
    end;
  if Summary = '' then
    Summary := '(пусто)';
  AppendStatus('Доступно в канале: ' + Summary);
  RefreshGrid;
end;

function TfrmMain.UpdateOneRow(const Row: TGridRowInfo; const Comp: TComponentManifest;
  const PreparedText: string; ForceDowngrade: Boolean): TUpdateErtResult;
var
  InstanceLabel: string;
begin
  InstanceLabel := Row.IbLabel + '/' + Row.ModuleStem;
  if ForceDowngrade then
    LogInfo(Format('FORCE downgrade %s id=%s path=%s',
      [InstanceLabel, Row.ComponentId, Row.ErtPath]))
  else
    LogInfo(Format('Update %s id=%s path=%s',
      [InstanceLabel, Row.ComponentId, Row.ErtPath]));
  Result := UpdateErtInstance(Row.ErtPath, InstanceLabel, Comp, PreparedText, ForceDowngrade);
  AppendStatus(InstanceLabel + ' [' + Row.ComponentId + ']: ' + Result.Message);
  if Result.Locked then
    MessageDlg(Result.Message, mtWarning, [mbOK], 0);
end;

function TfrmMain.UpdateOneServiceRow(const Row: TGridRowInfo;
  const Comp: TComponentManifest; ForceDowngrade: Boolean): TUpdateServiceResult;
var
  Svc: TComponentConfig;
begin
  Svc := FConfig.GetServiceConfig(Row.ComponentId);
  if ForceDowngrade then
    LogInfo(Format('FORCE downgrade app id=%s exe=%s',
      [Row.ComponentId, Svc.Exe]))
  else
    LogInfo(Format('Update app id=%s exe=%s',
      [Row.ComponentId, Svc.Exe]));
  Result := UpdateWindowsService(Comp, Svc, ForceDowngrade);
  AppendStatus(Row.IbLabel + ' [' + Row.ComponentId + ']: ' + Result.Message);
  if Result.CriticalRollbackFailed then
    MessageDlg(Result.Message, mtError, [mbOK], 0);
end;

procedure TfrmMain.RunUpdates(OnlySelected: Boolean; ForceDowngrade: Boolean);
var
  Err: string;
  Cached: string;
  Indices: TArray<Integer>;
  I, RowIdx, GridRow: Integer;
  State: string;
  Comp: TComponentManifest;
  PreparedById: TDictionary<string, string>;
  FailedPrepare: TStringList;
  OkCount, FailCount, SkipCount: Integer;
  Row: TGridRowInfo;
  PrepText: string;
  Res: TUpdateErtResult;
  SvcRes: TUpdateServiceResult;
begin
  ApplyPathsToConfig;
  if not FHasManifest then
  begin
    MessageDlg('Сначала нажмите «Проверить обновления».', mtInformation, [mbOK], 0);
    Exit;
  end;

  SetLength(Indices, 0);
  if OnlySelected then
  begin
    GridRow := grdUpdates.Row;
    RowIdx := GridRow - 1;
    if (RowIdx < 0) or (RowIdx > High(FRows)) then
    begin
      MessageDlg('Выберите строку модуля или службы.', mtInformation, [mbOK], 0);
      Exit;
    end;
    State := grdUpdates.Cells[COL_STATE, GridRow];
    if ForceDowngrade then
    begin
      if not SameText(State, 'локальная версия новее') then
      begin
        MessageDlg(
          'Принудительный downgrade только для строки со статусом «локальная версия новее».',
          mtInformation, [mbOK], 0);
        Exit;
      end;
    end
    else if SameText(State, 'нет в канале') then
    begin
      MessageDlg(
        '«' + FRows[RowIdx].ModuleStem + '» нет в канале (stable.json). Обновление недоступно.',
        mtInformation, [mbOK], 0);
      Exit;
    end;
    if not RowInChannel(FRows[RowIdx], Comp) then
    begin
      MessageDlg('Компонент отсутствует в manifest.', mtInformation, [mbOK], 0);
      Exit;
    end;
    if FRows[RowIdx].Kind = gkErt then
    begin
      if Trim(FRows[RowIdx].ErtPath) = '' then
      begin
        MessageDlg('Не задан путь к ERT.', mtWarning, [mbOK], 0);
        Exit;
      end;
    end
    else
    begin
      if Trim(FConfig.GetServiceConfig(FRows[RowIdx].ComponentId).Exe) = '' then
      begin
        MessageDlg('Не задан путь к EXE службы.', mtWarning, [mbOK], 0);
        Exit;
      end;
    end;
    if ForceDowngrade then
    begin
      if MessageDlg(
        Format(
          'Принудительный downgrade «%s»?'#13#10#13#10 +
          'Локально: %s'#13#10 +
          'Канал:   %s'#13#10#13#10 +
          'Локальная версия будет заменена более старой из канала.',
          [
            FRows[RowIdx].IbLabel +
              IfThen(FRows[RowIdx].Kind = gkErt, ' / ' + FRows[RowIdx].ModuleStem, ''),
            grdUpdates.Cells[COL_INSTALLED, GridRow],
            Comp.Version
          ]
        ),
        mtWarning, [mbYes, mbNo], 0
      ) <> mrYes then
        Exit;
    end;
    Indices := [RowIdx];
  end
  else
  begin
    if ForceDowngrade then
    begin
      MessageDlg('Принудительный downgrade только для одной выбранной строки.', mtInformation, [mbOK], 0);
      Exit;
    end;
    for I := 0 to High(FRows) do
    begin
      State := grdUpdates.Cells[COL_STATE, I + 1];
      if SameText(State, 'обновление') and RowInChannel(FRows[I], Comp) then
      begin
        SetLength(Indices, Length(Indices) + 1);
        Indices[High(Indices)] := I;
      end;
    end;
  end;

  if Length(Indices) = 0 then
  begin
    MessageDlg('Нет строк для обновления.', mtInformation, [mbOK], 0);
    Exit;
  end;

  OkCount := 0;
  FailCount := 0;
  SkipCount := 0;
  PreparedById := TDictionary<string, string>.Create;
  FailedPrepare := TStringList.Create;
  try
    FailedPrepare.CaseSensitive := False;
    FailedPrepare.Sorted := True;
    FailedPrepare.Duplicates := dupIgnore;

    for I := 0 to High(Indices) do
    begin
      RowIdx := Indices[I];
      Row := FRows[RowIdx];
      State := grdUpdates.Cells[COL_STATE, RowIdx + 1];

      if (not ForceDowngrade) and SameText(State, 'локальная версия новее') then
      begin
        AppendStatus(Row.IbLabel + '/' + Row.ModuleStem + ': downgrade запрещён — пропуск');
        Inc(SkipCount);
        Continue;
      end;
      if (not ForceDowngrade) and SameText(State, 'актуально') then
      begin
        AppendStatus(Row.IbLabel + '/' + Row.ModuleStem + ': уже актуально — пропуск');
        Inc(SkipCount);
        Continue;
      end;
      if not RowInChannel(Row, Comp) then
      begin
        AppendStatus(Row.IbLabel + '/' + Row.ModuleStem + ': нет в канале — пропуск');
        Inc(SkipCount);
        Continue;
      end;

      if Row.Kind = gkService then
      begin
        SvcRes := UpdateOneServiceRow(Row, Comp, ForceDowngrade);
        if SvcRes.Ok then
          Inc(OkCount)
        else if SvcRes.SkippedDowngrade then
          Inc(SkipCount)
        else
          Inc(FailCount);
        Continue;
      end;

      if FailedPrepare.IndexOf(Row.ComponentId) >= 0 then
      begin
        Inc(FailCount);
        Continue;
      end;

      if not PreparedById.TryGetValue(Row.ComponentId, PrepText) then
      begin
        if not PrepareAssetText(Comp, PrepText, Cached, Err) then
        begin
          AppendStatus(Row.ComponentId + ': ' + Err);
          FailedPrepare.Add(Row.ComponentId);
          Inc(FailCount);
          Continue;
        end;
        AppendStatus('Asset OK [' + Row.ComponentId + ']: ' + Cached);
        PreparedById.Add(Row.ComponentId, PrepText);
      end;

      Res := UpdateOneRow(Row, Comp, PrepText, ForceDowngrade);
      if Res.Ok then
        Inc(OkCount)
      else if Res.SkippedDowngrade then
        Inc(SkipCount)
      else
        Inc(FailCount);
    end;
  finally
    PreparedById.Free;
    FailedPrepare.Free;
  end;

  RefreshGrid;
  AppendStatus(Format('Итог обновления: ok=%d fail=%d skip=%d',
    [OkCount, FailCount, SkipCount]));
end;

procedure TfrmMain.btnUpdateSelectedClick(Sender: TObject);
begin
  RunUpdates(True, False);
end;

procedure TfrmMain.btnUpdateAllClick(Sender: TObject);
begin
  RunUpdates(False, False);
end;

procedure TfrmMain.btnForceDowngradeClick(Sender: TObject);
begin
  RunUpdates(True, True);
end;

function TfrmMain.SelectedIbContext(out IbLabel, LineId, MainPath: string): Boolean;
var
  RowIdx: Integer;
begin
  Result := False;
  IbLabel := '';
  LineId := '';
  MainPath := '';
  RowIdx := grdUpdates.Row - 1;
  if (RowIdx >= 0) and (RowIdx <= High(FRows)) then
  begin
    if FRows[RowIdx].Kind = gkService then
    begin
      MessageDlg(
        'Снимок базы — только для строк ERT (Злобин / Стрелец / Сургут).'#13#10 +
        'Выберите строку модуля, не службы.',
        mtInformation, [mbOK], 0);
      Exit;
    end;
    IbLabel := FRows[RowIdx].IbLabel;
    LineId := FRows[RowIdx].LineId;
  end
  else
  begin
    MessageDlg('Выберите любую строку нужной базы в таблице (Злобин / Стрелец / Сургут).'#13#10 +
    'Выбор файла в строке не важен — снимок берёт весь набор модулей базы.',
      mtInformation, [mbOK], 0);
    Exit;
  end;

  if SameText(IbLabel, LabelZlobin) then
    MainPath := Trim(edtZlobin.Text)
  else if SameText(IbLabel, LabelStrelets) then
    MainPath := Trim(edtStrelets.Text)
  else if SameText(IbLabel, LabelSurgut) then
    MainPath := Trim(edtSurgut.Text)
  else
    MainPath := FRows[RowIdx].ErtPath;

  if Trim(MainPath) = '' then
  begin
    MessageDlg('Для «' + IbLabel + '» не задан путь к главному ERT.', mtWarning, [mbOK], 0);
    Exit;
  end;
  Result := True;
end;

procedure TfrmMain.btnSnapshotWorkingClick(Sender: TObject);
var
  IbLabel, LineId, MainPath, Err, Msg, Confirm: string;
  Info: TWorkingSnapshotInfo;
  Item: TSnapshotFileItem;
  ErtCount, MdCount: Integer;
begin
  ApplyPathsToConfig;
  if not SelectedIbContext(IbLabel, LineId, MainPath) then
    Exit;

  Confirm :=
    'Снимок для базы «' + IbLabel + '».' + sLineBreak + sLineBreak +
    'Строка в таблице выбирает только базу, не один файл.' + sLineBreak +
    'Будут сохранены все найденные ERT из ModuleCatalog этой базы + 1Cv7.MD (только архив).' +
    sLineBreak + sLineBreak +
    'Продолжить?';
  if WorkingSnapshotExists(IbLabel) then
    Confirm := Confirm + sLineBreak + sLineBreak + 'Внимание: существующий снимок будет перезаписан.';

  if MessageDlg(Confirm, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  if not CreateWorkingSnapshot(IbLabel, LineId, MainPath, Info, Err) then
  begin
    AppendStatus('Снимок: ' + Err);
    MessageDlg(Err, mtError, [mbOK], 0);
    Exit;
  end;

  ErtCount := 0;
  MdCount := 0;
  Msg := 'Снимок базы «' + IbLabel + '» сохранён (весь набор файлов):' + sLineBreak +
    Info.SnapshotDir + sLineBreak + sLineBreak;
  for Item in Info.Files do
  begin
    if Item.Kind = sfMd then
    begin
      Inc(MdCount);
      Msg := Msg + '  [MD, только архив] ' + Item.Stem + sLineBreak;
    end
    else
    begin
      Inc(ErtCount);
      if Item.Version = '' then
        Msg := Msg + '  ' + Item.Stem + ' — ver: —' + sLineBreak
      else
        Msg := Msg + '  ' + Item.Stem + ' — ver: ' + Item.Version + sLineBreak;
    end;
  end;
  Msg := Msg + sLineBreak + Format('ERT: %d, 1Cv7.MD в архиве: %d.', [ErtCount, MdCount]);

  AppendStatus('Снимок рабочей OK: ' + IbLabel + ' -> ' + Info.SnapshotDir);
  RefreshSnapshotStatusHint;
  MessageDlg(Msg, mtInformation, [mbOK], 0);
end;

procedure TfrmMain.btnRestoreWorkingClick(Sender: TObject);
var
  IbLabel, LineId, MainPath, Err, Msg: string;
  Info: TWorkingSnapshotInfo;
  Item: TSnapshotFileItem;
  N: Integer;
begin
  ApplyPathsToConfig;
  if not SelectedIbContext(IbLabel, LineId, MainPath) then
    Exit;

  if not LoadWorkingSnapshotManifest(IbLabel, Info, Err) then
  begin
    AppendStatus('Восстановление: ' + Err);
    MessageDlg(Err, mtError, [mbOK], 0);
    Exit;
  end;

  Msg := 'Откат снимка базы «' + IbLabel + '» (' + Info.CreatedAt + ').' + sLineBreak +
    'Восстанавливаются ВСЕ ERT из снимка (не только выделенная строка).' + sLineBreak +
    '1Cv7.MD НЕ будет восстановлен.' + sLineBreak + sLineBreak;
  for Item in Info.Files do
    if Item.Restorable and (Item.Kind = sfErt) then
      Msg := Msg + '  ' + Item.Stem + ' -> ' + Item.OriginalPath + sLineBreak
    else if Item.Kind = sfMd then
      Msg := Msg + '  [пропуск] ' + Item.Stem + sLineBreak;

  if MessageDlg(Msg, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  if not RestoreWorkingSnapshot(IbLabel, N, Err) then
  begin
    AppendStatus('Восстановление: ' + Err);
    MessageDlg(Err, mtError, [mbOK], 0);
    Exit;
  end;

  AppendStatus(Format('Восстановлено ERT: %d (1Cv7.MD не трогали)', [N]));
  MessageDlg(Format('Готово. Восстановлено файлов ERT: %d.'#13#10'1Cv7.MD не изменялся.', [N]),
    mtInformation, [mbOK], 0);
  RefreshGrid;
  RefreshSnapshotStatusHint;
end;

procedure TfrmMain.btnOpenSnapshotsClick(Sender: TObject);
var
  Dir: string;
  RowIdx: Integer;
  IbLabel: string;
begin
  EnsureAppDirectories;
  Dir := SnapshotsDir;

  // Если выделена строка базы и снимок есть — открыть папку этой базы
  RowIdx := grdUpdates.Row - 1;
  if (RowIdx >= 0) and (RowIdx <= High(FRows)) then
  begin
    IbLabel := FRows[RowIdx].IbLabel;
    if (IbLabel <> '') and WorkingSnapshotExists(IbLabel) then
      Dir := WorkingSnapshotDir(IbLabel);
  end;

  if not TDirectory.Exists(Dir) then
    ForceDirectories(Dir);

  if ShellExecute(Handle, 'open', PChar(Dir), nil, nil, SW_SHOWNORMAL) <= 32 then
  begin
    AppendStatus('Не удалось открыть папку: ' + Dir);
    MessageDlg('Не удалось открыть папку:'#13#10 + Dir, mtWarning, [mbOK], 0);
  end
  else
    AppendStatus('Открыта папка снимков: ' + Dir);
end;

end.
