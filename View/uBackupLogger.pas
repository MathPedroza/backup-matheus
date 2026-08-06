unit uBackupLogger;

interface

uses
  System.Classes, System.SysUtils;

type
  TBackupLogLevel = (llDebug, llInfo, llWarning, llError, llCritical);

  TBackupLogger = class
  private
    FLines: TStringList;
    FFileName: string;
  public
    constructor Create(const LogDirectory: string);
    destructor Destroy; override;
    procedure Add(Level: TBackupLogLevel; const MessageText: string);
    procedure Save;
    property FileName: string read FFileName;
  end;

function BackupLogLevelToText(Level: TBackupLogLevel): string;

implementation

uses
  System.IOUtils;

function BackupLogLevelToText(Level: TBackupLogLevel): string;
begin
  case Level of
    llDebug: Result := 'DEPURACAO';
    llInfo: Result := 'INFORMACAO';
    llWarning: Result := 'AVISO';
    llError: Result := 'ERRO';
    llCritical: Result := 'CRITICO';
  else
    Result := 'INFORMACAO';
  end;
end;

constructor TBackupLogger.Create(const LogDirectory: string);
begin
  inherited Create;
  FLines := TStringList.Create;
  ForceDirectories(LogDirectory);
  FFileName := TPath.Combine(LogDirectory,
    'BackupLog_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now) + '.txt');
end;

destructor TBackupLogger.Destroy;
begin
  FLines.Free;
  inherited;
end;

procedure TBackupLogger.Add(Level: TBackupLogLevel; const MessageText: string);
begin
  FLines.Add(FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' [' +
    BackupLogLevelToText(Level) + '] ' + MessageText);
end;

procedure TBackupLogger.Save;
begin
  FLines.SaveToFile(FFileName, TEncoding.UTF8);
end;

end.
