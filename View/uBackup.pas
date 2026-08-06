unit uBackup;
interface
uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.DateUtils, System.UITypes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.FileCtrl, Vcl.ExtCtrls, Vcl.Menus, Vcl.ComCtrls,
  Vcl.WinXPickers, Vcl.Buttons, cxGraphics, cxLookAndFeels,
  cxLookAndFeelPainters, cxButtons, cxControls, cxContainer, cxEdit,
  cxCheckBox, dxStatusBar, JvExStdCtrls, JvListBox, JvDriveCtrls,
  JvCombobox, IdIOHandler, IdIOHandlerSocket, IdIOHandlerStack, IdSSL,
  IdSSLOpenSSL, IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient,
  IdHTTP, uBackupTypes, uBackupThread, Vcl.Imaging.pngimage;
type
  TfrmBackup = class(TForm)
    Panel1: TPanel;
    lblTamanhoTotal: TLabel;
    btnIniciar: TcxButton;
    btnSair: TcxButton;
    btnCancelar: TcxButton;
    Panel2: TPanel;
    Image1: TImage;
    PageControl1: TPageControl;
    TabParametros: TTabSheet;
    TabCaminho: TTabSheet;
    Label5: TLabel;
    MemoOrigens: TMemo;
    Label1: TLabel;
    Edit1: TEdit;
    ProgressBar1: TProgressBar;
    btnPastas: TSpeedButton;
    btnLimpar: TSpeedButton;
    btnRemover: TSpeedButton;
    lblProgresso: TLabel;
    GroupBox1: TGroupBox;
    Label2: TLabel;
    btnCarregarArquivos: TSpeedButton;
    OpenDialog1: TOpenDialog;
    chkSegunda: TCheckBox;
    chkTerca: TCheckBox;
    chkQuarta: TCheckBox;
    chkQuinta: TCheckBox;
    chkSexta: TCheckBox;
    chkSabado: TCheckBox;
    chkDomingo: TCheckBox;
    Label3: TLabel;
    ComboBox1: TComboBox;
    dtHoraAgendada: TTimePicker;
    TimerAgendamento: TTimer;
    Panel3: TPanel;
    MemoLog: TMemo;
    Label6: TLabel;
    dxStatusBar1: TdxStatusBar;
    StatusBar1: TStatusBar;
    Timer1: TTimer;
    TrayIcon1: TTrayIcon;
    PopupMenu1: TPopupMenu;
    Restaurar1: TMenuItem;
    Sair1: TMenuItem;
    dlb: TJvDirectoryListBox;
    DriveComboBox1: TJvDriveCombo;
    IdHTTP1: TIdHTTP;
    IdSSLIOHandlerSocketOpenSSL1: TIdSSLIOHandlerSocketOpenSSL;
    EdtDrive: TEdit;
    Label4: TLabel;
    btnDrive: TSpeedButton;
    chkDiferencial: TCheckBox;
    chkIncluirSistema: TCheckBox;
    chkValidarHash: TCheckBox;
    cxCheckDrive: TCheckBox;
    chkCompactarZip: TCheckBox;
    chkIncremental: TCheckBox;
    chkIgnorarVazias: TCheckBox;
    cxTamanhoBackup: TCheckBox;
    chkIncluirOcultos: TCheckBox;
    procedure btnPastasClick(Sender: TObject);
    procedure btnRemoverClick(Sender: TObject);
    procedure btnLimparClick(Sender: TObject);
    procedure dlbChange(Sender: TObject);
    procedure btnIniciarClick(Sender: TObject);
    procedure btnSairClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure btnCarregarArquivosClick(Sender: TObject);
    procedure TimerAgendamentoTimer(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure TrayIcon1DblClick(Sender: TObject);
    procedure Sair1Click(Sender: TObject);
    procedure Restaurar1Click(Sender: TObject);
    procedure btnCancelarClick(Sender: TObject);
    procedure cxCheckDriveClick(Sender: TObject);
    procedure chkCompactarZipClick(Sender: TObject);
    procedure chkDiferencialClick(Sender: TObject);
    procedure chkIncrementalClick(Sender: TObject);
    procedure chkIgnorarVaziasClick(Sender: TObject);
    procedure chkIncluirOcultosClick(Sender: TObject);
  private
    FBackupThread: TBackupThread;
    FBackupEmExecucao: Boolean;
    FLastScheduledRun: TDateTime;
    FConfigFileName: string;
    function BuildJob: TBackupJob;
    function TryAddSource(const Value: string): Boolean;
    function CurrentWeekDaysMask: Integer;
    procedure ApplyWeekDaysMask(Value: Integer);
    procedure LoadConfiguration;
    procedure SaveConfiguration;
    procedure PrepareInterfaceForBackup;
    procedure FinishInterfaceAfterBackup(const Summary: TBackupSummary);
    procedure BackupProgress(Sender: TObject; const Progress: TBackupProgress);
    procedure BackupLog(Sender: TObject; const MessageText: string);
    procedure BackupTerminated(Sender: TObject);
    function FormatDuration(TotalSeconds: Int64): string;
  public
  end;
var
  frmBackup: TfrmBackup;

implementation
uses
  Winapi.MMSystem, Winapi.ShellAPI, System.IOUtils, System.StrUtils,
  uBackupEngine, uBackupConfig, uBackupUtils;

{$R *.dfm}

function GetWindowsUserName: string;
var
  Buffer: array[0..255] of Char;
  Size: DWORD;
begin
  Size := Length(Buffer);
  if GetUserName(Buffer, Size) then
    Result := Buffer
  else
    Result := 'Desconhecido';
end;

procedure TfrmBackup.FormCreate(Sender: TObject);
begin
  FBackupThread := nil;
  FBackupEmExecucao := False;
  FConfigFileName := TBackupConfigStore.DefaultFileName;
  ProgressBar1.Min := 0;
  ProgressBar1.Max := 100;
  btnCancelar.Enabled := False;
  TimerAgendamento.Interval := 60000;
  TimerAgendamento.Enabled := True;
  FormatSettings := TFormatSettings.Create('pt-BR');
  StatusBar1.Panels[0].Text := FormatDateTime('dddd, dd/mm/yyyy - hh:nn:ss', Now);
  StatusBar1.Panels[3].Text := 'Usuario: ' + GetWindowsUserName;
  LoadConfiguration;
  PageControl1.ActivePage := TabCaminho;

  if ComboBox1.ItemIndex = 0 then
    TThread.Queue(nil,
      procedure
      begin
        if (MemoOrigens.Lines.Count > 0) and (Trim(Edit1.Text) <> '') then
          btnIniciarClick(Self);
      end);
end;

procedure TfrmBackup.FormDestroy(Sender: TObject);
begin
  SaveConfiguration;
end;

procedure TfrmBackup.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := not FBackupEmExecucao;
  if not CanClose then
  begin
    if MessageDlg('Existe um backup em andamento. Deseja solicitar o cancelamento?',
      mtWarning, [mbYes, mbNo], 0) = mrYes then
      btnCancelarClick(Self);
    MessageDlg('Aguarde o encerramento seguro da operacao antes de fechar.',
      mtInformation, [mbOK], 0);
  end;
end;

function TfrmBackup.TryAddSource(const Value: string): Boolean;
var
  Normalized: string;
  I: Integer;
begin
  Result := False;
  try
    Normalized := NormalizePath(Value);
  except
    on E: Exception do
    begin
      MessageDlg('Caminho invalido: ' + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  for I := 0 to MemoOrigens.Lines.Count - 1 do
    if SameText(NormalizePath(MemoOrigens.Lines[I]), Normalized) then
      Exit;
  MemoOrigens.Lines.Add(Normalized);
  Result := True;
end;

procedure TfrmBackup.btnPastasClick(Sender: TObject);
var
  SelectedDirectory: string;
begin
  if SelectDirectory('Selecione uma pasta de origem', '', SelectedDirectory,
    [sdNewUI, sdShowEdit, sdNewFolder]) then
    if not TryAddSource(SelectedDirectory) then
      MessageDlg('Essa pasta ja foi adicionada.', mtInformation, [mbOK], 0);
end;

procedure TfrmBackup.btnCarregarArquivosClick(Sender: TObject);
var
  I: Integer;
begin
  OpenDialog1.Title := 'Selecione um ou mais arquivos';
  OpenDialog1.Options := [ofAllowMultiSelect, ofFileMustExist, ofEnableSizing];
  if OpenDialog1.Execute then
    for I := 0 to OpenDialog1.Files.Count - 1 do
      if not TryAddSource(OpenDialog1.Files[I]) then
        MemoLog.Lines.Add('[AVISO] Item duplicado ignorado: ' + OpenDialog1.Files[I]);
end;

procedure TfrmBackup.btnRemoverClick(Sender: TObject);
var
  LineIndex: Integer;
begin
  LineIndex := MemoOrigens.CaretPos.Y;
  if (LineIndex >= 0) and (LineIndex < MemoOrigens.Lines.Count) then
    MemoOrigens.Lines.Delete(LineIndex);
end;

procedure TfrmBackup.btnLimparClick(Sender: TObject);
begin
  if not FBackupEmExecucao then
    MemoOrigens.Clear;
end;

procedure TfrmBackup.dlbChange(Sender: TObject);
begin
  Edit1.Text := dlb.Directory;
end;

function TfrmBackup.BuildJob: TBackupJob;
var
  I: Integer;
begin
  Result := TBackupJob.Create;
  Result.Name := 'Perfil padrao';
  Result.Destination := Trim(Edit1.Text);

  for I := 0 to MemoOrigens.Lines.Count - 1 do
    if Trim(MemoOrigens.Lines[I]) <> '' then
      Result.Sources.Add(Trim(MemoOrigens.Lines[I]));

  if chkDiferencial.Checked then
    Result.Options.Kind := bkDifferential

  else if chkIncremental.Checked then
    Result.Options.Kind := bkIncremental
  else
    Result.Options.Kind := bkFull;
  Result.Options.CompressZip := chkCompactarZip.Checked;
  Result.Options.IncludeEmptyDirectories := not chkIgnorarVazias.Checked;
  Result.Options.IncludeHidden := chkIncluirOcultos.Checked;
  Result.Options.IncludeSystem := chkIncluirSistema.Checked;
  Result.Options.VerifyHash := chkValidarHash.Checked;
end;

procedure TfrmBackup.PrepareInterfaceForBackup;
begin
  FBackupEmExecucao := True;
  btnIniciar.Enabled := False;
  btnCancelar.Enabled := True;
  TabParametros.Enabled := False;
  TabCaminho.Enabled := False;
  MemoLog.Clear;
  ProgressBar1.Position := 0;
  lblProgresso.Caption := '0%';
  dxStatusBar1.Panels[0].Text := 'Validando...';
  dxStatusBar1.Panels[1].Text := '';
end;

procedure TfrmBackup.btnIniciarClick(Sender: TObject);
var
  Job: TBackupJob;
  ErrorText: string;
begin
  if FBackupEmExecucao then
  begin
    MessageDlg('Ja existe um backup em andamento.', mtWarning, [mbOK], 0);
    Exit;
  end;

  Job := BuildJob;
  if not TBackupEngine.ValidateJob(Job, ErrorText) then
  begin
    Job.Free;
    MessageDlg(ErrorText, mtWarning, [mbOK], 0);
    Exit;
  end;

  SaveConfiguration;
  PrepareInterfaceForBackup;
  FBackupThread := TBackupThread.Create(Job);
  FBackupThread.OnProgress := BackupProgress;
  FBackupThread.OnLog := BackupLog;
  FBackupThread.OnTerminate := BackupTerminated;
  FBackupThread.Start;
end;

procedure TfrmBackup.btnCancelarClick(Sender: TObject);
begin
  if Assigned(FBackupThread) and FBackupEmExecucao then
  begin
    FBackupThread.Cancel;
    btnCancelar.Enabled := False;
    MemoLog.Lines.Add('[AVISO] Cancelamento solicitado; aguardando o ponto seguro.');
  end;
end;

function TfrmBackup.FormatDuration(TotalSeconds: Int64): string;
begin
  if TotalSeconds < 0 then
    TotalSeconds := 0;
  Result := Format('%.2d:%.2d:%.2d', [TotalSeconds div 3600,
    (TotalSeconds mod 3600) div 60, TotalSeconds mod 60]);
end;

procedure TfrmBackup.BackupProgress(Sender: TObject;
  const Progress: TBackupProgress);
begin
  ProgressBar1.Position := Progress.Percent;
  lblProgresso.Caption := IntToStr(Progress.Percent) + '%';

  if Progress.CurrentFile <> '' then
    dxStatusBar1.Panels[0].Text := 'Arquivo: ' + Progress.CurrentFile
  else
    dxStatusBar1.Panels[0].Text := BackupStageToText(Progress.Stage);
  dxStatusBar1.Panels[1].Text := 'Restante: ' +
    FormatDuration(Progress.EstimatedSecondsRemaining);
  StatusBar1.Panels[2].Text := Format('%d/%d | %s de %s | %s/s',
    [Progress.ProcessedFiles, Progress.TotalFiles,
     FormatBytes(Progress.ProcessedBytes), FormatBytes(Progress.TotalBytes),
     FormatBytes(Round(Progress.BytesPerSecond))]);
end;

procedure TfrmBackup.BackupLog(Sender: TObject; const MessageText: string);
begin
  MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' ' + MessageText);
  MemoLog.SelStart := Length(MemoLog.Text);
  MemoLog.Perform(EM_SCROLLCARET, 0, 0);
end;

procedure TfrmBackup.BackupTerminated(Sender: TObject);
var
  Summary: TBackupSummary;
begin
  Summary := FBackupThread.Summary;
  FBackupThread := nil;
  FBackupEmExecucao := False;
  FinishInterfaceAfterBackup(Summary);
  SaveConfiguration;
end;

procedure TfrmBackup.FinishInterfaceAfterBackup(const Summary: TBackupSummary);
var
  IconType: TMsgDlgType;
begin
  TabParametros.Enabled := True;
  TabCaminho.Enabled := True;
  btnCancelar.Enabled := False;
  btnIniciar.Enabled := True;

  if Summary.State = brSuccess then
  begin
    lblProgresso.Caption := 'Concluido';
    ProgressBar1.Position := 100;
    IconType := mtInformation;
    PlaySound('SystemAsterisk', 0, SND_ALIAS or SND_ASYNC);
  end
  else if Summary.State = brCancelled then
  begin
    lblProgresso.Caption := 'Cancelado';
    IconType := mtWarning;
  end
  else
  begin
    lblProgresso.Caption := BackupResultToText(Summary.State);
    IconType := mtError;
    PlaySound('SystemHand', 0, SND_ALIAS or SND_ASYNC);
  end;
  dxStatusBar1.Panels[0].Text := BackupResultToText(Summary.State);
  dxStatusBar1.Panels[1].Text := Format('Copiados: %d | Ignorados: %d | Erros: %d',
    [Summary.CopiedFiles, Summary.SkippedFiles, Summary.ErrorFiles]);
  MessageDlg(Summary.MessageText + sLineBreak +
    'Destino: ' + Summary.OutputPath + sLineBreak +
    'Log: ' + Summary.LogPath, IconType, [mbOK], 0);
end;

procedure TfrmBackup.chkDiferencialClick(Sender: TObject);
begin
  if chkDiferencial.Checked then
    chkIncremental.Checked := False;
end;

procedure TfrmBackup.chkIncrementalClick(Sender: TObject);
begin
  if chkIncremental.Checked then
     chkDiferencial.Checked := False;
end;

procedure TfrmBackup.chkIgnorarVaziasClick(Sender: TObject);
begin
  SaveConfiguration;
  if chkIgnorarVazias.Checked then
    dxStatusBar1.Panels[0].Text := 'Pastas vazias serao ignoradas.'
  else
    dxStatusBar1.Panels[0].Text := 'Pastas vazias serao incluidas.';
end;

procedure TfrmBackup.chkIncluirOcultosClick(Sender: TObject);
begin
  SaveConfiguration;
  if chkIncluirOcultos.Checked then
    dxStatusBar1.Panels[0].Text := 'Arquivos ocultos serao incluidos.'
  else
    dxStatusBar1.Panels[0].Text := 'Arquivos ocultos serao ignorados.';
end;

procedure TfrmBackup.chkCompactarZipClick(Sender: TObject);
begin
  { A compactacao agora e aplicada ao resultado da execucao e pode ser usada
    nos tres tipos de backup. }
end;

procedure TfrmBackup.cxCheckDriveClick(Sender: TObject);
begin
  if cxCheckDrive.Checked then
  begin
    cxCheckDrive.Checked := False;
    MessageDlg('O envio para nuvem permanece desativado ate que OAuth e o upload '
      + 'sejam implementados com armazenamento seguro de credenciais.',
      mtInformation, [mbOK], 0);
  end;
end;

function TfrmBackup.CurrentWeekDaysMask: Integer;
begin
  Result := 0;
  if chkDomingo.Checked then Result := Result or (1 shl 1);
  if chkSegunda.Checked then Result := Result or (1 shl 2);
  if chkTerca.Checked then Result := Result or (1 shl 3);
  if chkQuarta.Checked then Result := Result or (1 shl 4);
  if chkQuinta.Checked then Result := Result or (1 shl 5);
  if chkSexta.Checked then Result := Result or (1 shl 6);
  if chkSabado.Checked then Result := Result or (1 shl 7);
end;

procedure TfrmBackup.ApplyWeekDaysMask(Value: Integer);
begin
  chkDomingo.Checked := (Value and (1 shl 1)) <> 0;
  chkSegunda.Checked := (Value and (1 shl 2)) <> 0;
  chkTerca.Checked := (Value and (1 shl 3)) <> 0;
  chkQuarta.Checked := (Value and (1 shl 4)) <> 0;
  chkQuinta.Checked := (Value and (1 shl 5)) <> 0;
  chkSexta.Checked := (Value and (1 shl 6)) <> 0;
  chkSabado.Checked := (Value and (1 shl 7)) <> 0;
end;

procedure TfrmBackup.LoadConfiguration;
var
  Config: TBackupStoredConfig;
begin
  Config := TBackupStoredConfig.Create;
  try
    TBackupConfigStore.Load(FConfigFileName, Config);
    MemoOrigens.Lines.Assign(Config.Sources);
    Edit1.Text := Config.Destination;
    chkIncremental.Checked := Config.Incremental;
    chkDiferencial.Checked := Config.Differential;
    chkCompactarZip.Checked := Config.CompressZip;
    chkIgnorarVazias.Checked := Config.IgnoreEmptyDirectories;
    chkIncluirOcultos.Checked := Config.IncludeHidden;
    chkIncluirSistema.Checked := Config.IncludeSystem;
    chkValidarHash.Checked := Config.VerifyHash;
    cxTamanhoBackup.Checked := Config.CalculateSize;
    ComboBox1.ItemIndex := Config.ScheduleMode;
    dtHoraAgendada.Time := Config.ScheduleTime;
    ApplyWeekDaysMask(Config.WeekDaysMask);
    FLastScheduledRun := Config.LastScheduledRun;
  finally
    Config.Free;
  end;
end;

procedure TfrmBackup.SaveConfiguration;
var
  Config: TBackupStoredConfig;
begin
  if FConfigFileName = '' then
    Exit;
  Config := TBackupStoredConfig.Create;
  try
    Config.Sources.Assign(MemoOrigens.Lines);
    Config.Destination := Edit1.Text;
    Config.Incremental := chkIncremental.Checked;
    Config.Differential := chkDiferencial.Checked;
    Config.CompressZip := chkCompactarZip.Checked;
    Config.IgnoreEmptyDirectories := chkIgnorarVazias.Checked;
    Config.IncludeHidden := chkIncluirOcultos.Checked;
    Config.IncludeSystem := chkIncluirSistema.Checked;
    Config.VerifyHash := chkValidarHash.Checked;
    Config.CalculateSize := cxTamanhoBackup.Checked;
    Config.ScheduleMode := ComboBox1.ItemIndex;
    Config.ScheduleTime := dtHoraAgendada.Time;
    Config.WeekDaysMask := CurrentWeekDaysMask;
    Config.LastScheduledRun := FLastScheduledRun;
    TBackupConfigStore.Save(FConfigFileName, Config);
  finally
    Config.Free;
  end;
end;

procedure TfrmBackup.TimerAgendamentoTimer(Sender: TObject);
var
  TodayBit: Integer;
begin
  if FBackupEmExecucao or (ComboBox1.ItemIndex <> 2) then
    Exit;
  TodayBit := 1 shl DayOfWeek(Date);
  if (CurrentWeekDaysMask and TodayBit) = 0 then
    Exit;
  if FormatDateTime('hh:nn', Time) <> FormatDateTime('hh:nn', dtHoraAgendada.Time) then
    Exit;
  if FormatDateTime('yyyymmddhhnn', FLastScheduledRun) =
     FormatDateTime('yyyymmddhhnn', Now) then
    Exit;
  FLastScheduledRun := Now;
  SaveConfiguration;
  MemoLog.Lines.Add('[INFORMACAO] Iniciando backup agendado.');
  btnIniciarClick(Self);
end;

procedure TfrmBackup.Timer1Timer(Sender: TObject);
var
  ModeText: string;
begin
  StatusBar1.Panels[0].Text := FormatDateTime('dddd, dd/mm/yyyy - hh:nn:ss', Now);
  if chkDiferencial.Checked then
    ModeText := 'Diferencial'
  else if chkIncremental.Checked then
    ModeText := 'Incremental'
  else
    ModeText := 'Total';
  if chkCompactarZip.Checked then
    ModeText := ModeText + ' + ZIP';
  StatusBar1.Panels[1].Text := 'Modo: ' + ModeText;
end;

procedure TfrmBackup.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
      if FBackupEmExecucao then
        btnCancelarClick(Self)
      else
        Close;
    VK_F10: btnIniciarClick(Self);
    VK_F12: Close;
  end;
end;

procedure TfrmBackup.FormKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    Perform(CM_DialogKey, VK_TAB, 0);
  end;
end;

procedure TfrmBackup.FormResize(Sender: TObject);
begin
  if WindowState = wsMinimized then
  begin
    TrayIcon1.Visible := True;
    TrayIcon1.ShowBalloonHint;
    Hide;
  end;
end;

procedure TfrmBackup.TrayIcon1DblClick(Sender: TObject);
begin
  Show;
  WindowState := wsNormal;
  TrayIcon1.Visible := False;
end;

procedure TfrmBackup.Restaurar1Click(Sender: TObject);
begin
  TrayIcon1DblClick(Sender);
end;
procedure TfrmBackup.Sair1Click(Sender: TObject);
begin
  Close;
end;

procedure TfrmBackup.btnSairClick(Sender: TObject);
begin
  Close;
end;
end.
