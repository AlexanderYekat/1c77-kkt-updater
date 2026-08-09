unit AppConsts;

interface

const
  AppName = '1C77 KKT Updater';
  /// Должна совпадать с VerInfo FileVersion/ProductVersion в .dproj
  AppVersion = '2026.8.9.1';
  AppDataFolderName = '1C77KKTUpdater';

  SchemaVersion = 1;

  ComponentAtolModule = '1c77-atol-module';
  ComponentShtrihModule = '1c77-shtrih-module';
  ComponentTypeErtModule = 'ert-module';

  { Кириллица через #$ — не зависит от кодировки .pas при компиляции }
  LabelZlobin = #$0417#$043B#$043E#$0431#$0438#$043D;           // Злобин
  LabelStrelets = #$0421#$0442#$0440#$0435#$043B#$0435#$0446;   // Стрелец
  LabelSurgut = #$0421#$0443#$0440#$0433#$0443#$0442;           // Сургут

  { Якорные имена главных ERT (detect / UI edits) }
  DefaultAtolErtFileName = 'frATOL54_comm.ert';
  DefaultAtolErtFileNameAlt = 'frATOL54.ert';
  DefaultShtrihErtFileName = 'fr_elves-12.ert';
  DefaultShtrihTestErtFileName = 'fr_elves_test.ert';

  DefaultManifestUrl =
    'https://raw.githubusercontent.com/AlexanderYekat/1c77-kkt-updater/main/channels/stable.json';

  ErtStreamProgrammText = 'MD Programm text';

  RegistryTitlesKey = 'Software\1C\1Cv7\7.7\Titles';

  BackupRetentionPerInstance = 5;

implementation

end.
