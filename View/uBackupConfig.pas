unit uBackupConfig;

interface

uses
  System.Classes, System.SysUtils;

type
  TBackupStoredConfig = class
  public
    Sources: TStringList;
    Destination: string;
    Incremental: Boolean;
    Differential: Boolean;
    CompressZip: Boolean;
    IgnoreEmptyDirectories: Boolean;
    IncludeHidden: Boolean;
    IncludeSystem: Boolean;
    VerifyHash: Boolean;
    CalculateSize: Boolean;
    ScheduleMode: Integer;
    ScheduleTime: TDateTime;
    WeekDaysMask: Integer;
    LastScheduledRun: TDateTime;
    constructor Create;
    destructor Destroy; override;
  end;

  TBackupConfigStore = class
  public
    class function DefaultFileName: string; static;
    class procedure Load(const FileName: string; Config: TBackupStoredConfig); static;
    class procedure Save(const FileName: string; Config: TBackupStoredConfig); static;
  end;

implementation

uses
  System.IniFiles, System.IOUtils;

constructor TBackupStoredConfig.Create;
begin
  inherited Create;
  Sources := TStringList.Create;
  ScheduleMode := 2;
  ScheduleTime := EncodeTime(18, 0, 0, 0);
end;

destructor TBackupStoredConfig.Destroy;
begin
  Sources.Free;
  inherited;
end;

class function TBackupConfigStore.DefaultFileName: string;
var
  DirectoryName: string;
begin
  DirectoryName := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),
    'BackupMatheus');
  ForceDirectories(DirectoryName);
  Result := TPath.Combine(DirectoryName, 'backup.ini');
end;

class procedure TBackupConfigStore.Load(const FileName: string;
  Config: TBackupStoredConfig);
var
  Ini: TMemIniFile;
  I, Count: Integer;
begin
  if not FileExists(FileName) then
    Exit;
  Ini := TMemIniFile.Create(FileName, TEncoding.UTF8);
  try
    Config.Destination := Ini.ReadString('Profile', 'Destination', '');
    Config.Incremental := Ini.ReadBool('Profile', 'Incremental', False);
    Config.Differential := Ini.ReadBool('Profile', 'Differential', False);
    Config.CompressZip := Ini.ReadBool('Profile', 'CompressZip', False);
    Config.IgnoreEmptyDirectories := Ini.ReadBool('Profile',
      'IgnoreEmptyDirectories', True);
    Config.IncludeHidden := Ini.ReadBool('Profile', 'IncludeHidden', False);
    Config.IncludeSystem := Ini.ReadBool('Profile', 'IncludeSystem', False);
    Config.VerifyHash := Ini.ReadBool('Profile', 'VerifyHash', False);
    Config.CalculateSize := Ini.ReadBool('Profile', 'CalculateSize', True);
    Config.ScheduleMode := Ini.ReadInteger('Schedule', 'Mode', 2);
    Config.ScheduleTime := Ini.ReadDateTime('Schedule', 'Time',
      EncodeTime(18, 0, 0, 0));
    Config.WeekDaysMask := Ini.ReadInteger('Schedule', 'WeekDaysMask', 0);
    Config.LastScheduledRun := Ini.ReadDateTime('Schedule', 'LastRun', 0);
    Config.Sources.Clear;
    Count := Ini.ReadInteger('Sources', 'Count', 0);
    for I := 0 to Count - 1 do
      Config.Sources.Add(Ini.ReadString('Sources', 'Item' + IntToStr(I), ''));
  finally
    Ini.Free;
  end;
end;

class procedure TBackupConfigStore.Save(const FileName: string;
  Config: TBackupStoredConfig);
var
  Ini: TMemIniFile;
  I: Integer;
begin
  ForceDirectories(ExtractFileDir(FileName));
  Ini := TMemIniFile.Create(FileName, TEncoding.UTF8);
  try
    Ini.WriteString('Profile', 'Destination', Config.Destination);
    Ini.WriteBool('Profile', 'Incremental', Config.Incremental);
    Ini.WriteBool('Profile', 'Differential', Config.Differential);
    Ini.WriteBool('Profile', 'CompressZip', Config.CompressZip);
    Ini.WriteBool('Profile', 'IgnoreEmptyDirectories',
      Config.IgnoreEmptyDirectories);
    Ini.WriteBool('Profile', 'IncludeHidden', Config.IncludeHidden);
    Ini.WriteBool('Profile', 'IncludeSystem', Config.IncludeSystem);
    Ini.WriteBool('Profile', 'VerifyHash', Config.VerifyHash);
    Ini.WriteBool('Profile', 'CalculateSize', Config.CalculateSize);
    Ini.WriteInteger('Schedule', 'Mode', Config.ScheduleMode);
    Ini.WriteDateTime('Schedule', 'Time', Config.ScheduleTime);
    Ini.WriteInteger('Schedule', 'WeekDaysMask', Config.WeekDaysMask);
    Ini.WriteDateTime('Schedule', 'LastRun', Config.LastScheduledRun);
    Ini.EraseSection('Sources');
    Ini.WriteInteger('Sources', 'Count', Config.Sources.Count);
    for I := 0 to Config.Sources.Count - 1 do
      Ini.WriteString('Sources', 'Item' + IntToStr(I), Config.Sources[I]);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

end.
