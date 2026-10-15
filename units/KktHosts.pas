unit KktHosts;

interface

type
  TKktHostPair = record
    Host: string;
    Ip: string;
  end;

const
  /// Файл пар ИМЯ=IP в каталоге ИБ; читает permissive_regime_2024 (ПутьКФайлуIPХостов).
  KktHostsFileName = 'kkt_hosts.txt';

/// Пары из захардкоженной подмены хоста в старом permissive_regime_2024:
///   Если Врег(сокрлп(хост)) = "DESKTOP-XXX" тогда
///     хост = "192.168.x.x";
/// Имя — в верхнем регистре (1С сравнивает через ВРег), IP — только корректный IPv4.
function ExtractHardcodedKktHosts(const ModuleText: string): TArray<TKktHostPair>;

/// Дописывает пары в kkt_hosts.txt в формате 1С (CP1251, CRLF, ИМЯ=IP).
/// Имена, уже имеющиеся в файле, не трогает: их мог ввести пользователь позже.
/// Added — реально дописанные пары.
function MergeKktHostsFile(const FileName: string; const Pairs: TArray<TKktHostPair>;
  out Added: TArray<TKktHostPair>; out ErrorMsg: string): Boolean;

/// Перенос хардкода из старого текста модуля в <каталог ИБ>\kkt_hosts.txt.
/// Не бросает исключений. Возвращает строку для статуса ('' — переносить нечего).
function MigrateHardcodedKktHosts(const OldModuleText, ErtPath: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.RegularExpressions,
  AppLog,
  ErtCodec,
  WorkingSnapshot;

const
  // Тот же заголовок, что пишет СохранитьIPХоста в 1С
  KktHostsHeader: array[0..2] of string = (
    '// IP-адреса компьютеров со службой печати чеков, которые не находятся',
    '// по имени RDP-клиента (CLIENTNAME). Формат строки: ИМЯ_КОМПЬЮТЕРА=IP',
    '// Строку можно исправить или удалить — тогда IP-адрес спросят заново.'
  );

  // Текст заранее приводится к нижнему регистру (AnsiLowerCase), поэтому
  // кириллица в шаблоне — строчная, без опоры на (?i) для не-ASCII.
  HardcodedHostPattern =
    '=\s*"([^"\s]+)"\s*тогда\s*(?:хост|выбipсервер)\s*=\s*"([0-9]{1,3}(?:\.[0-9]{1,3}){3})"';

function IsIPv4(const S: string): Boolean;
var
  Parts: TArray<string>;
  Part: string;
  N: Integer;
begin
  Parts := S.Split(['.']);
  if Length(Parts) <> 4 then
    Exit(False);
  for Part in Parts do
    if (Part = '') or (Length(Part) > 3) or not TryStrToInt(Part, N) or (N > 255) then
      Exit(False);
  Result := True;
end;

function ExtractHardcodedKktHosts(const ModuleText: string): TArray<TKktHostPair>;
var
  M: TMatch;
  Pair: TKktHostPair;
  Seen: TStringList;
begin
  Result := nil;
  Seen := TStringList.Create;
  try
    Seen.CaseSensitive := False;
    for M in TRegEx.Matches(AnsiLowerCase(ModuleText), HardcodedHostPattern) do
    begin
      Pair.Host := AnsiUpperCase(M.Groups[1].Value);
      Pair.Ip := M.Groups[2].Value;
      if IsIPv4(Pair.Ip) and (Seen.IndexOf(Pair.Host) < 0) then
      begin
        Seen.Add(Pair.Host);
        Result := Result + [Pair];
      end;
    end;
  finally
    Seen.Free;
  end;
end;

/// Имя из строки «ИМЯ=IP»; комментарии (// и ;) и строки без '=' — False.
function TryParseHostName(const Line: string; out Host: string): Boolean;
var
  S: string;
  P: Integer;
begin
  Host := '';
  S := Trim(Line);
  if S.StartsWith('//') or S.StartsWith(';') then
    Exit(False);
  P := Pos('=', S);
  if P = 0 then
    Exit(False);
  Host := AnsiUpperCase(Trim(Copy(S, 1, P - 1)));
  Result := Host <> '';
end;

function MergeKktHostsFile(const FileName: string; const Pairs: TArray<TKktHostPair>;
  out Added: TArray<TKktHostPair>; out ErrorMsg: string): Boolean;
var
  Lines, Existing: TStringList;
  Pair: TKktHostPair;
  Host: string;
  Bytes: TBytes;
  I: Integer;
begin
  Result := False;
  Added := nil;
  ErrorMsg := '';
  Lines := TStringList.Create;
  Existing := TStringList.Create;
  try
    try
      Existing.CaseSensitive := False;
      if TFile.Exists(FileName) then
        Lines.Text := Cp1251BytesToString(TFile.ReadAllBytes(FileName))
      else
        Lines.AddStrings(KktHostsHeader);
      for I := 0 to Lines.Count - 1 do
        if TryParseHostName(Lines[I], Host) then
          Existing.Add(Host);

      for Pair in Pairs do
        if Existing.IndexOf(Pair.Host) < 0 then
        begin
          Lines.Add(Pair.Host + '=' + Pair.Ip);
          Existing.Add(Pair.Host);
          Added := Added + [Pair];
        end;
      if Length(Added) = 0 then
        Exit(True);

      Lines.LineBreak := #13#10;
      if not EncodeModuleTextToCp1251(Lines.Text, Bytes, ErrorMsg) then
        Exit;
      TFile.WriteAllBytes(FileName, Bytes);
      Result := True;
    except
      on E: Exception do
        ErrorMsg := E.Message;
    end;
  finally
    Existing.Free;
    Lines.Free;
  end;
end;

function DoMigrateHardcodedKktHosts(const OldModuleText, ErtPath: string;
  out Failed: Boolean): string;
var
  Pairs, Added: TArray<TKktHostPair>;
  Pair: TKktHostPair;
  IbRoot, FileName, Err: string;
begin
  Result := '';
  Failed := True;
  Pairs := ExtractHardcodedKktHosts(OldModuleText);
  if Length(Pairs) = 0 then
  begin
    Failed := False;
    Exit;
  end;

  IbRoot := IbRootFromExtForms(ExtFormsRootFromErt(ErtPath));
  if IbRoot = '' then
    Exit('хардкод хост=IP не перенесён: ERT не в <ИБ>\ExtForms, каталог ИБ не определён (' +
      ErtPath + ')');

  FileName := TPath.Combine(IbRoot, KktHostsFileName);
  if not MergeKktHostsFile(FileName, Pairs, Added, Err) then
    Exit('хардкод хост=IP не перенесён в ' + FileName + ': ' + Err);

  Failed := False;
  if Length(Added) = 0 then
    Exit; // перенесено раньше

  for Pair in Added do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Pair.Host + '=' + Pair.Ip;
  end;
  Result := 'хост=IP перенесены в ' + FileName + ': ' + Result;
end;

function MigrateHardcodedKktHosts(const OldModuleText, ErtPath: string): string;
var
  Failed: Boolean;
begin
  try
    Result := DoMigrateHardcodedKktHosts(OldModuleText, ErtPath, Failed);
  except
    on E: Exception do
    begin
      Result := 'хардкод хост=IP не перенесён: ' + E.Message;
      Failed := True;
    end;
  end;
  if Result = '' then
    Exit;
  // Сбой записи лога не должен ломать уже выполненное обновление ERT
  try
    if Failed then
      LogWarn(Result)
    else
      LogInfo(Result);
  except
  end;
end;

end.
