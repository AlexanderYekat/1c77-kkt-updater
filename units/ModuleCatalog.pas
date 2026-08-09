unit ModuleCatalog;

interface

uses
  AppConsts;

type
  TModuleLine = (mlAtol, mlShtrih);

  TModuleCatalogEntry = record
    ComponentId: string;
    FileStem: string;
    Line: TModuleLine;
    DefaultFileName: string;
    LegacyStems: TArray<string>;
  end;

const
  ModuleCatalogCount = 10;

  /// Маркер линейки для snapshot / UI (совместим с CP1 LineId)
  LineIdAtol = ComponentAtolModule;
  LineIdShtrih = ComponentShtrihModule;

function ModuleCatalogEntries: TArray<TModuleCatalogEntry>;
function TryFindModuleById(const ComponentId: string;
  out Entry: TModuleCatalogEntry): Boolean;
function ModulesForLine(Line: TModuleLine): TArray<TModuleCatalogEntry>;
function LabelsForLine(Line: TModuleLine): TArray<string>;
function LineIdOf(Line: TModuleLine): string;
function LineFromLineId(const LineId: string): TModuleLine;
function IsAtolLine(const LineId: string): Boolean;
function FindErtPathByStem(const ExtFormsRoot, Stem: string): string;
function ResolveModulePath(
  const ExtFormsRoot, ConfigPath: string;
  const Entry: TModuleCatalogEntry
): string;

implementation

uses
  System.SysUtils,
  System.IOUtils;

function MakeEntry(
  const ComponentId, FileStem: string;
  Line: TModuleLine;
  const LegacyStems: TArray<string>
): TModuleCatalogEntry;
begin
  Result.ComponentId := ComponentId;
  Result.FileStem := FileStem;
  Result.Line := Line;
  Result.DefaultFileName := FileStem + '.ert';
  Result.LegacyStems := LegacyStems;
end;

function SingleStem(const Stem: string): TArray<string>;
begin
  SetLength(Result, 1);
  Result[0] := Stem;
end;

function ModuleCatalogEntries: TArray<TModuleCatalogEntry>;
begin
  // Ровно 10 внешних ERT. Код конфигурации (module-form-of-check, глобальный) — вне каталога.
  SetLength(Result, ModuleCatalogCount);
  Result[0] := MakeEntry(
    ComponentAtolModule, 'frATOL54_comm', mlAtol,
    TArray<string>.Create('frATOL54', 'frATOL54_comm')
  );
  Result[1] := MakeEntry(
    '1c77-atol-permissive_regime_2024', 'permissive_regime_2024', mlAtol,
    SingleStem('permissive_regime_2024')
  );
  Result[2] := MakeEntry(
    '1c77-atol-razresh_regim_check', 'razresh_regim_check', mlAtol,
    SingleStem('razresh_regim_check')
  );
  Result[3] := MakeEntry(
    '1c77-atol-razresh_regim_dialog_error', 'razresh_regim_dialog_error', mlAtol,
    SingleStem('razresh_regim_dialog_error')
  );
  Result[4] := MakeEntry(
    '1c77-atol-test_check', 'test_check', mlAtol,
    SingleStem('test_check')
  );
  Result[5] := MakeEntry(
    ComponentShtrihModule, 'fr_elves-12', mlShtrih,
    SingleStem('fr_elves-12')
  );
  Result[6] := MakeEntry(
    '1c77-shtrih-fr_elves_test', 'fr_elves_test', mlShtrih,
    SingleStem('fr_elves_test')
  );
  Result[7] := MakeEntry(
    '1c77-shtrih-permissive_regime_2024', 'permissive_regime_2024', mlShtrih,
    SingleStem('permissive_regime_2024')
  );
  Result[8] := MakeEntry(
    '1c77-shtrih-razresh_regim_check', 'razresh_regim_check', mlShtrih,
    SingleStem('razresh_regim_check')
  );
  Result[9] := MakeEntry(
    '1c77-shtrih-razresh_regim_dialog_error', 'razresh_regim_dialog_error', mlShtrih,
    SingleStem('razresh_regim_dialog_error')
  );
end;

function TryFindModuleById(const ComponentId: string;
  out Entry: TModuleCatalogEntry): Boolean;
var
  Item: TModuleCatalogEntry;
begin
  for Item in ModuleCatalogEntries do
    if SameText(Item.ComponentId, ComponentId) then
    begin
      Entry := Item;
      Exit(True);
    end;
  Entry := Default(TModuleCatalogEntry);
  Result := False;
end;

function ModulesForLine(Line: TModuleLine): TArray<TModuleCatalogEntry>;
var
  Item: TModuleCatalogEntry;
  N: Integer;
begin
  SetLength(Result, ModuleCatalogCount);
  N := 0;
  for Item in ModuleCatalogEntries do
    if Item.Line = Line then
    begin
      Result[N] := Item;
      Inc(N);
    end;
  SetLength(Result, N);
end;

function LabelsForLine(Line: TModuleLine): TArray<string>;
begin
  if Line = mlAtol then
    Result := TArray<string>.Create(LabelZlobin, LabelStrelets)
  else
    Result := TArray<string>.Create(LabelSurgut);
end;

function LineIdOf(Line: TModuleLine): string;
begin
  if Line = mlAtol then
    Result := LineIdAtol
  else
    Result := LineIdShtrih;
end;

function LineFromLineId(const LineId: string): TModuleLine;
begin
  if SameText(LineId, LineIdShtrih) or SameText(LineId, ComponentShtrihModule) then
    Result := mlShtrih
  else
    Result := mlAtol;
end;

function IsAtolLine(const LineId: string): Boolean;
begin
  Result := LineFromLineId(LineId) = mlAtol;
end;

function FindErtPathByStem(const ExtFormsRoot, Stem: string): string;
var
  A, B: string;
begin
  Result := '';
  if (ExtFormsRoot = '') or (Stem = '') then
    Exit;
  A := TPath.Combine(ExtFormsRoot, Stem + '.ert');
  B := TPath.Combine(TPath.Combine(ExtFormsRoot, 'Equip'), Stem + '.ert');
  if TFile.Exists(A) then
    Exit(A);
  if TFile.Exists(B) then
    Exit(B);
end;

function ResolveModulePath(
  const ExtFormsRoot, ConfigPath: string;
  const Entry: TModuleCatalogEntry
): string;
var
  Stem: string;
begin
  if (Trim(ConfigPath) <> '') and TFile.Exists(ConfigPath) then
    Exit(Trim(ConfigPath));
  if Trim(ConfigPath) <> '' then
    // путь задан, но файла нет — всё равно вернём (UI покажет «файл не найден»)
    Exit(Trim(ConfigPath));

  Result := FindErtPathByStem(ExtFormsRoot, Entry.FileStem);
  if Result <> '' then
    Exit;

  // для 1c77-atol-module — исторический stem frATOL54
  for Stem in Entry.LegacyStems do
    if not SameText(Stem, Entry.FileStem) then
    begin
      Result := FindErtPathByStem(ExtFormsRoot, Stem);
      if Result <> '' then
        Exit;
    end;
end;

end.
