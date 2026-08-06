program Backup;

uses
  Vcl.Forms,
  uBackup in '..\View\uBackup.pas' {frmBackup},
  uBackupTypes in '..\View\uBackupTypes.pas',
  uBackupUtils in '..\View\uBackupUtils.pas',
  uBackupLogger in '..\View\uBackupLogger.pas',
  uBackupConfig in '..\View\uBackupConfig.pas',
  uBackupEngine in '..\View\uBackupEngine.pas',
  uBackupThread in '..\View\uBackupThread.pas',
  Vcl.Themes,
  Vcl.Styles;

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  TStyleManager.TrySetStyle('Amethyst Kamri');
  Application.CreateForm(TfrmBackup, frmBackup);
  Application.Run;
end.
