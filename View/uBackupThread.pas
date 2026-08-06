unit uBackupThread;

interface

uses
  System.Classes, System.SysUtils, uBackupTypes, uBackupEngine;

type
  TBackupThread = class(TThread)
  private
    FEngine: TBackupEngine;
    FSummary: TBackupSummary;
    FPendingProgress: TBackupProgress;
    FPendingLog: string;
    FOnProgress: TBackupProgressEvent;
    FOnLog: TBackupLogEvent;
    procedure EngineProgress(Sender: TObject; const Progress: TBackupProgress);
    procedure EngineLog(Sender: TObject; const MessageText: string);
    procedure SyncProgress;
    procedure SyncLog;
  protected
    procedure Execute; override;
  public
    constructor Create(Job: TBackupJob);
    destructor Destroy; override;
    procedure Cancel;
    property Summary: TBackupSummary read FSummary;
    property OnProgress: TBackupProgressEvent read FOnProgress write FOnProgress;
    property OnLog: TBackupLogEvent read FOnLog write FOnLog;
  end;

implementation

constructor TBackupThread.Create(Job: TBackupJob);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FEngine := TBackupEngine.Create(Job);
  FEngine.OnProgress := EngineProgress;
  FEngine.OnLog := EngineLog;
end;

destructor TBackupThread.Destroy;
begin
  FEngine.Free;
  inherited;
end;

procedure TBackupThread.Cancel;
begin
  Terminate;
  FEngine.Cancel;
end;

procedure TBackupThread.EngineProgress(Sender: TObject;
  const Progress: TBackupProgress);
begin
  FPendingProgress := Progress;
  Synchronize(SyncProgress);
end;

procedure TBackupThread.EngineLog(Sender: TObject;
  const MessageText: string);
begin
  FPendingLog := MessageText;
  Synchronize(SyncLog);
end;

procedure TBackupThread.SyncProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, FPendingProgress);
end;

procedure TBackupThread.SyncLog;
begin
  if Assigned(FOnLog) then
    FOnLog(Self, FPendingLog);
end;

procedure TBackupThread.Execute;
begin
  FSummary := FEngine.Execute;
end;

end.
