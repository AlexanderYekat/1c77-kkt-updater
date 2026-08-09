unit RegistryBases;

interface

type
  TIbInfo = record
    Path: string;
    Title: string;
    MatchedLabel: string; // Злобин / Стрелец / Сургут
  end;

  TIbInfoArray = TArray<TIbInfo>;

function ReadAllTitles(out Items: TIbInfoArray; out ErrorMsg: string): Boolean;
function FilterByLabel(const Items: TIbInfoArray; const LabelName: string): TIbInfoArray;
function FindAtolBases(out Items: TIbInfoArray; out ErrorMsg: string): Boolean;
function FindSurgutBases(out Items: TIbInfoArray; out ErrorMsg: string): Boolean;
function SuggestErtCandidates(const IbPath, PreferredFileName: string): TArray<string>;
function PickBestErtCandidate(const Candidates: TArray<string>): string;
function PickBestShtrihErtCandidate(const Candidates: TArray<string>): string;
function IsLikelyAtolErtFileName(const FileName: string): Boolean;
function IsLikelyShtrihErtFileName(const FileName: string): Boolean;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Win.Registry,
  AppConsts;

function TitleMatchesLabel(const Title, LabelName: string): Boolean;
begin
  Result := Pos(AnsiUpperCase(LabelName), AnsiUpperCase(Title)) > 0;
end;

function DetectLabel(const Title: string): string;
begin
  if TitleMatchesLabel(Title, LabelZlobin) then
    Exit(LabelZlobin);
  if TitleMatchesLabel(Title, LabelStrelets) then
    Exit(LabelStrelets);
  if TitleMatchesLabel(Title, LabelSurgut) then
    Exit(LabelSurgut);
  Result := '';
end;

function ReadAllTitles(out Items: TIbInfoArray; out ErrorMsg: string): Boolean;
var
  Reg: TRegistry;
  Names: TStringList;
  Name, Title: string;
  List: TIbInfoArray;
  N, I: Integer;
  Info: TIbInfo;
begin
  Result := False;
  SetLength(Items, 0);
  ErrorMsg := '';
  Reg := TRegistry.Create(KEY_READ);
  Names := TStringList.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKeyReadOnly(RegistryTitlesKey) then
    begin
      ErrorMsg :=
        'Не удалось открыть HKCU\' + RegistryTitlesKey +
        '. Запустите updater от того же пользователя Windows, что и 1С 7.7.';
      Exit;
    end;

    Reg.GetValueNames(Names);
    SetLength(List, Names.Count);
    N := 0;
    for I := 0 to Names.Count - 1 do
    begin
      Name := Names[I];
      if Reg.GetDataType(Name) <> rdString then
        Continue;
      Title := Reg.ReadString(Name);
      Info.Path := Name;
      Info.Title := Title;
      Info.MatchedLabel := DetectLabel(Title);
      List[N] := Info;
      Inc(N);
    end;
    SetLength(List, N);
    Items := List;
    Result := True;
    if N = 0 then
      ErrorMsg := 'Ключ Titles открыт, но список баз пуст.';
  finally
    Names.Free;
    Reg.Free;
  end;
end;

function FilterByLabel(const Items: TIbInfoArray; const LabelName: string): TIbInfoArray;
var
  Info: TIbInfo;
  N: Integer;
begin
  SetLength(Result, Length(Items));
  N := 0;
  for Info in Items do
    if SameText(Info.MatchedLabel, LabelName) or TitleMatchesLabel(Info.Title, LabelName) then
    begin
      Result[N] := Info;
      if Result[N].MatchedLabel = '' then
        Result[N].MatchedLabel := LabelName;
      Inc(N);
    end;
  SetLength(Result, N);
end;

function FindAtolBases(out Items: TIbInfoArray; out ErrorMsg: string): Boolean;
var
  All, Acc: TIbInfoArray;
  Part: TIbInfoArray;
  Info: TIbInfo;
begin
  Result := ReadAllTitles(All, ErrorMsg);
  if not Result then
    Exit;
  SetLength(Acc, 0);
  Part := FilterByLabel(All, LabelZlobin);
  for Info in Part do
  begin
    SetLength(Acc, Length(Acc) + 1);
    Acc[High(Acc)] := Info;
  end;
  Part := FilterByLabel(All, LabelStrelets);
  for Info in Part do
  begin
    SetLength(Acc, Length(Acc) + 1);
    Acc[High(Acc)] := Info;
  end;
  Items := Acc;
  if Length(Items) = 0 then
    ErrorMsg := 'Базы с маркерами «Злобин» / «Стрелец» в Titles не найдены.';
end;

function FindSurgutBases(out Items: TIbInfoArray; out ErrorMsg: string): Boolean;
var
  All: TIbInfoArray;
begin
  Result := ReadAllTitles(All, ErrorMsg);
  if not Result then
    Exit;
  Items := FilterByLabel(All, LabelSurgut);
  if Length(Items) = 0 then
    ErrorMsg := 'Базы с маркером «Сургут» в Titles не найдены.';
end;

function SuggestErtCandidates(const IbPath, PreferredFileName: string): TArray<string>;
var
  Roots: TArray<string>;
  Preferred: TArray<string>;
  Root, Pref, FileName: string;
  Files: TArray<string>;
  N: Integer;
  Seen: TStringList;

  procedure AddUnique(const Path: string);
  begin
    if (Path = '') or not TFile.Exists(Path) then
      Exit;
    if Seen.IndexOf(UpperCase(Path)) >= 0 then
      Exit;
    Seen.Add(UpperCase(Path));
    if N >= Length(Result) then
      SetLength(Result, Length(Result) * 2 + 8);
    Result[N] := Path;
    Inc(N);
  end;

begin
  SetLength(Result, 0);
  if Trim(IbPath) = '' then
    Exit;

  Roots := [
    TPath.Combine(IbPath, 'ExtForms'),
    TPath.Combine(IbPath, TPath.Combine('ExtForms', 'Equip'))
  ];

  Preferred := [
    PreferredFileName,
    DefaultAtolErtFileName,
    DefaultAtolErtFileNameAlt
  ];

  Seen := TStringList.Create;
  try
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    N := 0;
    SetLength(Result, 32);

    // Сначала точные имена в ExtForms и Equip
    for Pref in Preferred do
    begin
      if Trim(Pref) = '' then
        Continue;
      for Root in Roots do
        AddUnique(TPath.Combine(Root, Pref));
    end;

    // Затем любые *ATOL*.ert
    for Root in Roots do
    begin
      if not TDirectory.Exists(Root) then
        Continue;
      Files := TDirectory.GetFiles(Root, '*ATOL*.ert');
      for FileName in Files do
        AddUnique(FileName);
    end;

    // Прочие .ert — в конец списка (для Обзор), автовыбор их не возьмёт
    for Root in Roots do
    begin
      if not TDirectory.Exists(Root) then
        Continue;
      Files := TDirectory.GetFiles(Root, '*.ert');
      for FileName in Files do
        AddUnique(FileName);
    end;

    SetLength(Result, N);
  finally
    Seen.Free;
  end;
end;

function IsLikelyAtolErtFileName(const FileName: string): Boolean;
var
  Name: string;
begin
  Name := TPath.GetFileName(FileName);
  Result :=
    SameText(Name, DefaultAtolErtFileName) or
    SameText(Name, DefaultAtolErtFileNameAlt) or
    (Pos('ATOL', AnsiUpperCase(Name)) > 0);
end;

function IsLikelyShtrihErtFileName(const FileName: string): Boolean;
var
  Name: string;
begin
  Name := TPath.GetFileName(FileName);
  Result :=
    SameText(Name, DefaultShtrihErtFileName) or
    SameText(Name, 'fr_elves.ert') or
    (Pos('FR_ELVES-12', AnsiUpperCase(Name)) > 0);
end;

function PickBestErtCandidate(const Candidates: TArray<string>): string;
var
  C: string;
begin
  Result := '';
  if Length(Candidates) = 0 then
    Exit;

  for C in Candidates do
    if SameText(TPath.GetFileName(C), DefaultAtolErtFileName) then
      Exit(C);
  for C in Candidates do
    if SameText(TPath.GetFileName(C), DefaultAtolErtFileNameAlt) then
      Exit(C);
  for C in Candidates do
    if IsLikelyAtolErtFileName(C) then
      Exit(C);

  Result := '';
end;

function PickBestShtrihErtCandidate(const Candidates: TArray<string>): string;
var
  C: string;
begin
  Result := '';
  if Length(Candidates) = 0 then
    Exit;

  for C in Candidates do
    if SameText(TPath.GetFileName(C), DefaultShtrihErtFileName) then
      Exit(C);
  for C in Candidates do
    if IsLikelyShtrihErtFileName(C) then
      Exit(C);

  Result := '';
end;

end.
