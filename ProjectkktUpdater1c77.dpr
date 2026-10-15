program ProjectkktUpdater1c77;

uses
  Vcl.Forms,
  Winapi.ActiveX,
  AppConsts in 'units\AppConsts.pas',
  ModuleCatalog in 'units\ModuleCatalog.pas',
  AppPaths in 'units\AppPaths.pas',
  AppLog in 'units\AppLog.pas',
  VersionParse in 'units\VersionParse.pas',
  Config in 'units\Config.pas',
  RegistryBases in 'units\RegistryBases.pas',
  HashUtil in 'units\HashUtil.pas',
  HttpDownload in 'units\HttpDownload.pas',
  Manifest in 'units\Manifest.pas',
  ErtCodec in 'units\ErtCodec.pas',
  ErtStorage in 'units\ErtStorage.pas',
  Backup in 'units\Backup.pas',
  UpdateErt in 'units\UpdateErt.pas',
  ExeVersion in 'units\ExeVersion.pas',
  ProcessControl in 'units\ProcessControl.pas',
  ServiceHttp in 'units\ServiceHttp.pas',
  ZipUtil in 'units\ZipUtil.pas',
  ServiceRollbackJournal in 'units\ServiceRollbackJournal.pas',
  UpdateService in 'units\UpdateService.pas',
  AppElevation in 'units\AppElevation.pas',
  WorkingSnapshot in 'units\WorkingSnapshot.pas',
  KktHosts in 'units\KktHosts.pas',
  kktUpdater1c77 in 'kktUpdater1c77.pas' {frmMain};

{$R *.res}

begin
  CoInitialize(nil);
  try
    Application.Initialize;
    Application.MainFormOnTaskbar := True;
    Application.Title := AppName;
    Application.CreateForm(TfrmMain, frmMain);
    Application.Run;
  finally
    CoUninitialize;
  end;
end.
