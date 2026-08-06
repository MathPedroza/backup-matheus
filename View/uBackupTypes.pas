unit uBackupTypes;

interface

uses
  System.Classes, System.SysUtils;

type
  TBackupKind = (bkFull, bkIncremental, bkDifferential);
  TBackupResultState = (brSuccess, brWarning, brPartial, brCancelled, brFailed);
  TBackupStage = (bsValidating, bsScanning, bsCopying, bsVerifying,
    bsCompressing, bsSavingManifest, bsFinished);

  TBackupOptions = record
    Kind: TBackupKind;
    CompressZip: Boolean;
    IncludeHidden: Boolean;
    IncludeSystem: Boolean;
    IgnoreTemporary: Boolean;
    IncludeEmptyDirectories: Boolean;
    VerifyHash: Boolean;
    OverwriteExisting: Boolean;
    RetryCount: Integer;
    RetryDelayMs: Cardinal;
    SafetyMarginBytes: Int64;
    class function Defaults: TBackupOptions; static;
  end;

  TBackupProgress = record
    Stage: TBackupStage;
    CurrentFile: string;
    CurrentFolder: string;
    TotalFiles: Integer;
    ProcessedFiles: Integer;
    CopiedFiles: Integer;
    SkippedFiles: Integer;
    ErrorFiles: Integer;
    DeletedFiles: Integer;
    TotalBytes: Int64;
    ProcessedBytes: Int64;
    Percent: Integer;
    BytesPerSecond: Double;
    EstimatedSecondsRemaining: Int64;
  end;

  TBackupSummary = record
    State: TBackupResultState;
    StartedAt: TDateTime;
    FinishedAt: TDateTime;
    TotalFiles: Integer;
    ProcessedFiles: Integer;
    CopiedFiles: Integer;
    SkippedFiles: Integer;
    ErrorFiles: Integer;
    ValidatedFiles: Integer;
    DivergentFiles: Integer;
    TotalBytes: Int64;
    ProcessedBytes: Int64;
    OutputPath: string;
    ZipPath: string;
    LogPath: string;
    MessageText: string;
  end;

  TBackupJob = class
  private
    FSources: TStringList;
  public
    Name: string;
    Destination: string;
    Options: TBackupOptions;
    constructor Create;
    destructor Destroy; override;
    property Sources: TStringList read FSources;
    function Clone: TBackupJob;
  end;

  TBackupProgressEvent = procedure(Sender: TObject;
    const Progress: TBackupProgress) of object;
  TBackupLogEvent = procedure(Sender: TObject; const MessageText: string) of object;

function BackupKindToText(const Value: TBackupKind): string;
function BackupResultToText(const Value: TBackupResultState): string;
function BackupStageToText(const Value: TBackupStage): string;

implementation

class function TBackupOptions.Defaults: TBackupOptions;
begin
  Result.Kind := bkFull;
  Result.CompressZip := False;
  Result.IncludeHidden := False;
  Result.IncludeSystem := False;
  Result.IgnoreTemporary := True;
  Result.IncludeEmptyDirectories := False;
  Result.VerifyHash := False;
  Result.OverwriteExisting := True;
  Result.RetryCount := 2;
  Result.RetryDelayMs := 500;
  Result.SafetyMarginBytes := 100 * 1024 * 1024;
end;

constructor TBackupJob.Create;
begin
  inherited Create;
  FSources := TStringList.Create;
  FSources.CaseSensitive := False;
  FSources.Duplicates := dupIgnore;
  Options := TBackupOptions.Defaults;
end;

destructor TBackupJob.Destroy;
begin
  FSources.Free;
  inherited;
end;

function TBackupJob.Clone: TBackupJob;
begin
  Result := TBackupJob.Create;
  Result.Name := Name;
  Result.Destination := Destination;
  Result.Options := Options;
  Result.Sources.Assign(FSources);
end;

function BackupKindToText(const Value: TBackupKind): string;
begin
  case Value of
    bkFull: Result := 'TOTAL';
    bkIncremental: Result := 'INCREMENTAL';
    bkDifferential: Result := 'DIFERENCIAL';
  else
    Result := 'DESCONHECIDO';
  end;
end;

function BackupResultToText(const Value: TBackupResultState): string;
begin
  case Value of
    brSuccess: Result := 'Concluido com sucesso';
    brWarning: Result := 'Concluido com avisos';
    brPartial: Result := 'Concluido parcialmente';
    brCancelled: Result := 'Cancelado';
    brFailed: Result := 'Falhou';
  else
    Result := 'Desconhecido';
  end;
end;

function BackupStageToText(const Value: TBackupStage): string;
begin
  case Value of
    bsValidating: Result := 'Validando';
    bsScanning: Result := 'Analisando';
    bsCopying: Result := 'Copiando';
    bsVerifying: Result := 'Verificando';
    bsCompressing: Result := 'Compactando';
    bsSavingManifest: Result := 'Salvando historico';
    bsFinished: Result := 'Finalizado';
  else
    Result := '';
  end;
end;

end.
