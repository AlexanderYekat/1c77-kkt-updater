program KktHostsTest;

{$APPTYPE CONSOLE}

// Перенос захардкоженных пар «имя RDP-клиента → IP» из старого
// permissive_regime_2024 в <ИБ>\kkt_hosts.txt.
// Параметры (необязательно): пути к TXT модулей (UTF-8) — печатает найденные пары.
// Пишет пару строк в обычный лог апдейтера (AppLog).

uses
  System.SysUtils,
  System.IOUtils,
  AppConsts in '..\units\AppConsts.pas',
  AppPaths in '..\units\AppPaths.pas',
  AppLog in '..\units\AppLog.pas',
  VersionParse in '..\units\VersionParse.pas',
  ModuleCatalog in '..\units\ModuleCatalog.pas',
  HashUtil in '..\units\HashUtil.pas',
  ErtCodec in '..\units\ErtCodec.pas',
  ErtStorage in '..\units\ErtStorage.pas',
  WorkingSnapshot in '..\units\WorkingSnapshot.pas',
  KktHosts in '..\units\KktHosts.pas';

const
  CRLF = #13#10;

  OldModule =
    'процедура ОбеспечитьХостПрокси()' + CRLF +
    #9'хост = СокрЛП(глХостСервисаПечатиЧека);' + CRLF +
    #9'хост = ПолучитьИмяХостаКлиента();' + CRLF +
    #9'Если Врег(сокрлп(хост)) = "DESKTOP-E3TR59N" тогда' + CRLF +
    #9#9'хост = "192.168.92.34";' + CRLF +
    #9'конецЕсли;' + CRLF +
    #9'ЕСЛИ ВРег(хост) = "kassa-2" ТОГДА ХОСТ = "10.0.0.7"; КОНЕЦЕСЛИ;' + CRLF +
    #9'Если Врег(хост) = "BAD-IP" тогда хост = "10.0.0.300"; конецЕсли;' + CRLF +
    #9'Если Врег(хост) = "DESKTOP-E3TR59N" тогда хост = "1.1.1.1"; конецЕсли;' + CRLF +
    'конецПроцедуры' + CRLF;

  // Фрагменты нового модуля: IP в комментарии и в Предупреждение — не пары
  NewModule =
    '// IPv4 вида 192.168.1.25 > 1, иначе 0' + CRLF +
    #9'Предупреждение("""" + ip + """ — не IP-адрес." + РазделительСтрок + "Пример: 192.168.1.25");' + CRLF +
    #9'если хост = "" тогда' + CRLF +
    #9#9'хост = СокрЛП(выбIpСервер);' + CRLF;

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const Msg: string);
begin
  if Cond then
    Writeln('ok   ', Msg)
  else
  begin
    Writeln('FAIL ', Msg);
    Inc(Failures);
  end;
end;

function PairsToStr(const Pairs: TArray<TKktHostPair>): string;
var
  Pair: TKktHostPair;
begin
  Result := '';
  for Pair in Pairs do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Pair.Host + '=' + Pair.Ip;
  end;
end;

function ReadCp1251(const FileName: string): string;
begin
  Result := Cp1251BytesToString(TFile.ReadAllBytes(FileName));
end;

procedure WriteCp1251(const FileName, Text: string);
var
  Bytes: TBytes;
  Err: string;
begin
  if not EncodeModuleTextToCp1251(Text, Bytes, Err) then
    raise Exception.Create(Err);
  TFile.WriteAllBytes(FileName, Bytes);
end;

procedure TestExtract;
var
  Pairs: TArray<TKktHostPair>;
begin
  Pairs := ExtractHardcodedKktHosts(OldModule);
  Check(PairsToStr(Pairs) = 'DESKTOP-E3TR59N=192.168.92.34, KASSA-2=10.0.0.7',
    'extract: старый модуль -> ' + PairsToStr(Pairs));
  Pairs := ExtractHardcodedKktHosts(NewModule);
  Check(Length(Pairs) = 0, 'extract: новый модуль без пар -> ' + PairsToStr(Pairs));
end;

procedure TestMigrate;
var
  Ib, Hosts, Msg, Text: string;
begin
  Ib := TPath.Combine(TPath.GetTempPath, 'KktHostsTest_' + TPath.GetGUIDFileName);
  ForceDirectories(TPath.Combine(Ib, 'ExtForms\Equip'));
  Hosts := TPath.Combine(Ib, KktHostsFileName);
  try
    // нет файла -> создаётся с заголовком и обеими парами
    Msg := MigrateHardcodedKktHosts(OldModule, TPath.Combine(Ib, 'ExtForms\permissive_regime_2024.ert'));
    Check(TFile.Exists(Hosts), 'migrate: файл создан (' + Msg + ')');
    Text := ReadCp1251(Hosts);
    Check(Text.StartsWith('// IP-адреса компьютеров') and
      Text.EndsWith('DESKTOP-E3TR59N=192.168.92.34' + CRLF + 'KASSA-2=10.0.0.7' + CRLF),
      'migrate: заголовок + пары, CP1251/CRLF');

    // повтор -> ничего не дописывает
    Msg := MigrateHardcodedKktHosts(OldModule, TPath.Combine(Ib, 'ExtForms\Equip\permissive_regime_2024.ert'));
    Check((Msg = '') and (ReadCp1251(Hosts) = Text), 'migrate: повтор без дублей (ExtForms\Equip)');

    // пользователь уже ввёл другой IP -> не перезаписываем; файл без перевода строки в конце
    WriteCp1251(Hosts, '// комментарий' + CRLF + 'desktop-e3tr59n = 192.168.92.50');
    MigrateHardcodedKktHosts(OldModule, TPath.Combine(Ib, 'ExtForms\permissive_regime_2024.ert'));
    Check(ReadCp1251(Hosts) = '// комментарий' + CRLF + 'desktop-e3tr59n = 192.168.92.50' + CRLF +
      'KASSA-2=10.0.0.7' + CRLF, 'migrate: введённый пользователем IP не тронут');

    // ERT не в ExtForms -> каталог ИБ не определить, файл не пишем
    TFile.Delete(Hosts);
    Msg := MigrateHardcodedKktHosts(OldModule, TPath.Combine(Ib, 'permissive_regime_2024.ert'));
    Check((not TFile.Exists(Hosts)) and Msg.Contains('не перенесён'), 'migrate: ERT вне ExtForms -> ' + Msg);

    // новый модуль -> файл не создаётся
    Msg := MigrateHardcodedKktHosts(NewModule, TPath.Combine(Ib, 'ExtForms\permissive_regime_2024.ert'));
    Check((Msg = '') and not TFile.Exists(Hosts), 'migrate: без хардкода файл не создаётся');
  finally
    TDirectory.Delete(Ib, True);
  end;
end;

var
  I: Integer;
  Pairs: TArray<TKktHostPair>;
begin
  try
    for I := 1 to ParamCount do
    begin
      Pairs := ExtractHardcodedKktHosts(
        Utf8BytesToStringWithoutBom(TFile.ReadAllBytes(ParamStr(I))));
      Writeln(ParamStr(I), ': [', PairsToStr(Pairs), ']');
    end;
    if ParamCount > 0 then
      Exit;
    TestExtract;
    TestMigrate;
  except
    on E: Exception do
    begin
      Writeln('FAIL exception: ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;
  if Failures = 0 then
    Writeln('ALL OK')
  else
    Writeln('FAILURES: ', Failures);
  ExitCode := Ord(Failures > 0);
end.
