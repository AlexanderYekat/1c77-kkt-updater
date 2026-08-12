unit AppConsts;

interface

const
  AppName = '1C77 KKT Updater';
  /// Должна совпадать с VerInfo FileVersion/ProductVersion в .dproj
  AppVersion = '2026.8.12.1';
  AppDataFolderName = '1C77KKTUpdater'; // %ProgramData%\CTO_KSM\1C77KKTUpdater\

  SchemaVersion = 1;

  ComponentAtolModule = '1c77-atol-module';
  ComponentShtrihModule = '1c77-shtrih-module';
  ComponentAtolService = 'atol-service';
  ComponentShtrihService = 'shtrih-service';

  ComponentTypeErtModule = 'ert-module';
  ComponentTypeWindowsService = 'windows-service';

  { Кириллица через #$ — не зависит от кодировки .pas при компиляции }
  LabelZlobin = #$0417#$043B#$043E#$0431#$0438#$043D;           // Злобин
  LabelStrelets = #$0421#$0442#$0440#$0435#$043B#$0435#$0446;   // Стрелец
  LabelSurgut = #$0421#$0443#$0440#$0433#$0443#$0442;           // Сургут
  LabelAtolService = 'ATOL Service';
  LabelShtrihService = #$0428#$0442#$0440#$0438#$0445' Service'; // Штрих Service

  { Якорные имена главных ERT (detect / UI edits) }
  DefaultAtolErtFileName = 'frATOL54_comm.ert';
  DefaultAtolErtFileNameAlt = 'frATOL54.ert';
  DefaultShtrihErtFileName = 'fr_elves-12.ert';
  DefaultShtrihTestErtFileName = 'fr_elves_test.ert';

  // Как DefaultDirName в installer_kktserver.iss: Program Files\CTO_KSM\kktserver
  DefaultServiceVendorDir = 'CTO_KSM';
  DefaultServiceAppDir = 'kktserver';
  DefaultServiceExeFileName = 'kktserverindyProject.exe';
  HintServiceExeFileName = 'kktserverindyProject.exe';
  // Дефолт base_url / порт — как DefaultHttpPort в installer_kktserver.iss
  DefaultServiceHttpPort = 2580;
  DefaultServiceBaseUrl = 'http://127.0.0.1:2580';

  DefaultManifestUrl =
    'https://raw.githubusercontent.com/AlexanderYekat/1c77-kkt-updater/main/channels/stable.json';

  ErtStreamProgrammText = 'MD Programm text';

  RegistryTitlesKey = 'Software\1C\1Cv7\7.7\Titles';

  BackupRetentionPerInstance = 5;
  ServiceBackupRetention = 5;

  { Post-update HTTP verify }
  ServiceHealthRetryIntervalMs = 1000;
  ServiceHealthRetryMaxMs = 30000;
  { Старые Delphi-сборки без GET /version: verify = FileVersion exe + /health }

  { Остановка/ожидание процесса приложения }
  ServiceProcessWaitTimeoutMs = 60000;

  EndpointVersion = '/version';
  EndpointHealth = '/health';
  /// Штатное завершение Delphi-службы (hide-to-tray; WM_CLOSE больше не убивает процесс)
  EndpointExit = '/exit';

implementation

end.
