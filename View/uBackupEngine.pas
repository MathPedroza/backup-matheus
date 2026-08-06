unit uBackupEngine;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Generics.Defaults, uBackupTypes, uBackupLogger;

type
  TBackupManifestEntry = record
    Size: Int64;
    ModifiedUtc: TDateTime;
    SHA256: string;
  end;

  TBackupItem = class
  public
    SourcePath: string;
    RelativePath: string;
    Size: Int64;
    ModifiedUtc: TDateTime;
    SHA256: string;
    NeedsCopy: Boolean;
  end;

  TBackupEngine = class
  private
    FJob: TBackupJob;
    FItems: TObjectList<TBackupItem>;
    FDirectories: TStringList;
    FKnownTargets: TStringList;
    FBaseManifest: TDictionary<string, TBackupManifestEntry>;
    FCurrentManifest: TDictionary<string, TBackupManifestEntry>;
    FCancelled: Integer;
    FSummary: TBackupSummary;
    FProgress: TBackupProgress;
    FLogger: TBackupLogger;
    FStartedTick: UInt64;
    FOnProgress: TBackupProgressEvent;
    FOnLog: TBackupLogEvent;
    procedure EmitLog(Level: TBackupLogLevel; const MessageText: string);
    procedure EmitProgress(Stage: TBackupStage; const Item: TBackupItem = nil;
      AdditionalBytes: Int64 = 0);
    procedure ScanSources;
    procedure ScanDirectory(const SourceDirectory, RelativeRoot: string);
    procedure AddFileItem(const SourceFile, RelativePath: string;
      Size: Int64; ModifiedUtc: TDateTime);
    function ShouldInclude(const Name: string; Attributes: Integer): Boolean;
    function ShouldCopyItem(Item: TBackupItem): Boolean;
    procedure PrepareItems;
    procedure CheckDiskSpace;
    function CopyOneFile(Item: TBackupItem): Boolean;
    procedure CopyItems;
    procedure CreateSelectedDirectories;
    function ComputeSHA256(const FileName: string): string;
    procedure BuildCurrentManifest;
    procedure LoadBaseManifest;
    procedure SaveManifests;
    procedure LoadManifest(const FileName: string;
      Target: TDictionary<string, TBackupManifestEntry>);
    procedure SaveManifest(const FileName: string;
      Source: TDictionary<string, TBackupManifestEntry>);
    function StateDirectory: string;
    function FullManifestFile: string;
    function LatestManifestFile: string;
    procedure CompressOutput;
    procedure AddDirectoryToZip(Zip: TObject; const DirectoryName,
      RootDirectory: string);
    function IsCancelled: Boolean;
    procedure DetermineFinalState;
  public
    constructor Create(AJob: TBackupJob);
    destructor Destroy; override;
    class function ValidateJob(Job: TBackupJob; out ErrorText: string): Boolean; static;
    procedure Cancel;
    function Execute: TBackupSummary;
    property OnProgress: TBackupProgressEvent read FOnProgress write FOnProgress;
    property OnLog: TBackupLogEvent read FOnLog write FOnLog;
  end;

implementation

uses
  Winapi.Windows, System.IOUtils, System.Hash, System.JSON, System.DateUtils,
  System.SyncObjs, System.Zip, System.StrUtils, System.Math, uBackupUtils;

constructor TBackupEngine.Create(AJob: TBackupJob);
begin
  inherited Create;
  FJob := AJob;
  FItems := TObjectList<TBackupItem>.Create(True);
  FDirectories := TStringList.Create;
  FDirectories.CaseSensitive := False;
  FDirectories.Sorted := True;
  FDirectories.Duplicates := dupIgnore;
  FKnownTargets := TStringList.Create;
  FKnownTargets.CaseSensitive := False;
  FKnownTargets.Sorted := True;
  FKnownTargets.Duplicates := dupIgnore;
  FBaseManifest := TDictionary<string, TBackupManifestEntry>.Create;
  FCurrentManifest := TDictionary<string, TBackupManifestEntry>.Create;
end;

destructor TBackupEngine.Destroy;
begin
  FLogger.Free;
  FCurrentManifest.Free;
  FBaseManifest.Free;
  FKnownTargets.Free;
  FDirectories.Free;
  FItems.Free;
  FJob.Free;
  inherited;
end;

class function TBackupEngine.ValidateJob(Job: TBackupJob;
  out ErrorText: string): Boolean;
var
  I: Integer;
  LSource, LDestination: string;
begin
  Result := False;
  ErrorText := '';
  if not Assigned(Job) then
  begin
    ErrorText := 'A configuracao do backup nao foi informada.';
    Exit;
  end;
  if Job.Sources.Count = 0 then
  begin
    ErrorText := 'Adicione pelo menos uma pasta ou arquivo de origem.';
    Exit;
  end;
  try
    LDestination := NormalizePath(Job.Destination);
  except
    on E: Exception do
    begin
      ErrorText := 'Destino invalido: ' + E.Message;
      Exit;
    end;
  end;
  if LDestination = '' then
  begin
    ErrorText := 'Informe uma pasta de destino.';
    Exit;
  end;
  if IsDangerousDestination(LDestination) then
  begin
    ErrorText := 'O destino selecionado e uma raiz ou pasta protegida do Windows.';
    Exit;
  end;
  for I := 0 to Job.Sources.Count - 1 do
  begin
    try
      LSource := NormalizePath(Job.Sources[I]);
    except
      on E: Exception do
      begin
        ErrorText := 'Origem invalida: ' + Job.Sources[I] + '. ' + E.Message;
        Exit;
      end;
    end;
    if not DirectoryExists(ToExtendedPath(LSource)) and
       not FileExists(ToExtendedPath(LSource)) then
    begin
      ErrorText := 'A origem nao existe ou esta indisponivel: ' + LSource;
      Exit;
    end;
    if PathsOverlap(LSource, LDestination) then
    begin
      ErrorText := 'Origem e destino nao podem ser iguais nem ficar um dentro do outro: ' +
        LSource;
      Exit;
    end;
  end;
  Result := True;
end;

procedure TBackupEngine.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
end;

function TBackupEngine.IsCancelled: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0;
end;

procedure TBackupEngine.EmitLog(Level: TBackupLogLevel;
  const MessageText: string);
begin
  if Assigned(FLogger) then
    FLogger.Add(Level, MessageText);
  if Assigned(FOnLog) then
    FOnLog(Self, '[' + BackupLogLevelToText(Level) + '] ' + MessageText);
end;

procedure TBackupEngine.EmitProgress(Stage: TBackupStage;
  const Item: TBackupItem; AdditionalBytes: Int64);
var
  ElapsedSeconds: Double;
begin
  FProgress.Stage := Stage;
  if Assigned(Item) then
  begin
    FProgress.CurrentFile := Item.SourcePath;
    FProgress.CurrentFolder := ExtractFileDir(Item.SourcePath);
  end;
  FProgress.TotalFiles := FSummary.TotalFiles;
  FProgress.ProcessedFiles := FSummary.ProcessedFiles;
  FProgress.CopiedFiles := FSummary.CopiedFiles;
  FProgress.SkippedFiles := FSummary.SkippedFiles;
  FProgress.ErrorFiles := FSummary.ErrorFiles;
  FProgress.TotalBytes := FSummary.TotalBytes;
  FProgress.ProcessedBytes := FSummary.ProcessedBytes + AdditionalBytes;
  if FProgress.TotalBytes > 0 then
    FProgress.Percent := EnsureRange(Round(
      (FProgress.ProcessedBytes / FProgress.TotalBytes) * 100), 0, 100)
  else if (Stage = bsFinished) then
    FProgress.Percent := 100
  else
    FProgress.Percent := 0;
  ElapsedSeconds := (GetTickCount64 - FStartedTick) / 1000;
  if ElapsedSeconds > 0 then
    FProgress.BytesPerSecond := FProgress.ProcessedBytes / ElapsedSeconds
  else
    FProgress.BytesPerSecond := 0;
  if (FProgress.BytesPerSecond > 0) and
     (FProgress.TotalBytes > FProgress.ProcessedBytes) then
    FProgress.EstimatedSecondsRemaining := Round(
      (FProgress.TotalBytes - FProgress.ProcessedBytes) /
      FProgress.BytesPerSecond)
  else
    FProgress.EstimatedSecondsRemaining := 0;
  if Assigned(FOnProgress) then
    FOnProgress(Self, FProgress);
end;

function TBackupEngine.ShouldInclude(const Name: string;
  Attributes: Integer): Boolean;
begin
  Result := False;
  if ((Attributes and faHidden) <> 0) and not FJob.Options.IncludeHidden then
    Exit;
  if ((Attributes and faSysFile) <> 0) and not FJob.Options.IncludeSystem then
    Exit;
  if ((Attributes and faSymLink) <> 0) then
  begin
    EmitLog(llWarning, 'Link simbolico ou ponto de reanalise ignorado: ' + Name);
    Exit;
  end;
  if FJob.Options.IgnoreTemporary and IsTemporaryName(Name) then
    Exit;
  if MatchText(Name, ['$RECYCLE.BIN', 'System Volume Information']) then
    Exit;
  Result := True;
end;

procedure TBackupEngine.AddFileItem(const SourceFile, RelativePath: string;
  Size: Int64; ModifiedUtc: TDateTime);
var
  Item: TBackupItem;
begin
  if FKnownTargets.IndexOf(RelativePath) >= 0 then
  begin
    EmitLog(llWarning, 'Item duplicado ignorado: ' + SourceFile);
    Exit;
  end;
  FKnownTargets.Add(RelativePath);
  Item := TBackupItem.Create;
  Item.SourcePath := SourceFile;
  Item.RelativePath := RelativePath;
  Item.Size := Size;
  Item.ModifiedUtc := ModifiedUtc;
  FItems.Add(Item);
end;

procedure TBackupEngine.ScanDirectory(const SourceDirectory,
  RelativeRoot: string);
var
  SR: TSearchRec;
  LSource, LRelative: string;
  Found: Boolean;
begin
  if IsCancelled then
    Exit;
  if FJob.Options.IncludeEmptyDirectories then
    FDirectories.Add(RelativeRoot);
  Found := FindFirst(IncludeTrailingPathDelimiter(ToExtendedPath(SourceDirectory)) + '*',
    faAnyFile, SR) = 0;
  if not Found then
  begin
    EmitLog(llError, 'Nao foi possivel enumerar a pasta: ' + SourceDirectory +
      '. Erro do Windows: ' + SysErrorMessage(GetLastError));
    Inc(FSummary.ErrorFiles);
    Exit;
  end;
  try
    repeat
      if IsCancelled then
        Exit;
      if (SR.Name = '.') or (SR.Name = '..') or
         not ShouldInclude(SR.Name, SR.Attr) then
        Continue;
      LSource := TPath.Combine(SourceDirectory, SR.Name);
      LRelative := TPath.Combine(RelativeRoot, SR.Name);
      if (SR.Attr and faDirectory) <> 0 then
        ScanDirectory(LSource, LRelative)
      else
      begin
        try
          AddFileItem(LSource, LRelative, SR.Size,
            TFile.GetLastWriteTimeUtc(ToExtendedPath(LSource)));
        except
          on E: Exception do
          begin
            Inc(FSummary.ErrorFiles);
            EmitLog(llError, 'Falha ao analisar ' + LSource + ': ' + E.Message);
          end;
        end;
      end;
    until FindNext(SR) <> 0;
  finally
    System.SysUtils.FindClose(SR);
  end;
end;

procedure TBackupEngine.ScanSources;
var
  I: Integer;
  LSource, LRelative: string;
  Info: TSearchRec;
begin
  EmitProgress(bsScanning);
  for I := 0 to FJob.Sources.Count - 1 do
  begin
    if IsCancelled then
      Exit;
    LSource := NormalizePath(FJob.Sources[I]);
    LRelative := BuildSafeSourceRoot(LSource);
    if DirectoryExists(ToExtendedPath(LSource)) then
      ScanDirectory(LSource, LRelative)
    else if FindFirst(ToExtendedPath(LSource), faAnyFile, Info) = 0 then
    try
      if ShouldInclude(Info.Name, Info.Attr) then
        AddFileItem(LSource, LRelative, Info.Size,
          TFile.GetLastWriteTimeUtc(ToExtendedPath(LSource)));
    finally
      System.SysUtils.FindClose(Info);
    end;
  end;
end;

function TBackupEngine.StateDirectory: string;
begin
  Result := TPath.Combine(FJob.Destination, '.backup-state');
end;

function TBackupEngine.FullManifestFile: string;
begin
  Result := TPath.Combine(StateDirectory, 'manifest_full.json');
end;

function TBackupEngine.LatestManifestFile: string;
begin
  Result := TPath.Combine(StateDirectory, 'manifest_latest.json');
end;

procedure TBackupEngine.LoadManifest(const FileName: string;
  Target: TDictionary<string, TBackupManifestEntry>);
var
  JSONValue: TJSONValue;
  Root, Obj: TJSONObject;
  Files: TJSONArray;
  I: Integer;
  Entry: TBackupManifestEntry;
  PathValue: string;
begin
  Target.Clear;
  if not FileExists(ToExtendedPath(FileName)) then
    Exit;
  JSONValue := TJSONObject.ParseJSONValue(
    TFile.ReadAllText(ToExtendedPath(FileName), TEncoding.UTF8));
  try
    if not (JSONValue is TJSONObject) then
      raise Exception.Create('Manifesto JSON invalido: ' + FileName);
    Root := TJSONObject(JSONValue);
    Files := Root.GetValue<TJSONArray>('files');
    if not Assigned(Files) then
      Exit;
    for I := 0 to Files.Count - 1 do
    begin
      Obj := Files.Items[I] as TJSONObject;
      PathValue := Obj.GetValue<string>('path');
      Entry.Size := StrToInt64Def(Obj.GetValue<TJSONValue>('size').Value, 0);
      Entry.ModifiedUtc := ISO8601ToDate(Obj.GetValue<string>('modifiedUtc'), True);
      if Assigned(Obj.GetValue('sha256')) then
        Entry.SHA256 := Obj.GetValue<string>('sha256')
      else
        Entry.SHA256 := '';
      Target.AddOrSetValue(LowerCase(PathValue), Entry);
    end;
  finally
    JSONValue.Free;
  end;
end;

procedure TBackupEngine.SaveManifest(const FileName: string;
  Source: TDictionary<string, TBackupManifestEntry>);
var
  Root, Obj: TJSONObject;
  Files: TJSONArray;
  Pair: TPair<string, TBackupManifestEntry>;
  TempFile: string;
begin
  ForceDirectories(ToExtendedPath(ExtractFileDir(FileName)));
  Root := TJSONObject.Create;
  try
    Root.AddPair('formatVersion', TJSONNumber.Create(1));
    Root.AddPair('generatedAtUtc', DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True));
    Files := TJSONArray.Create;
    Root.AddPair('files', Files);
    for Pair in Source do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('path', Pair.Key);
      Obj.AddPair('size', TJSONNumber.Create(Pair.Value.Size));
      Obj.AddPair('modifiedUtc', DateToISO8601(Pair.Value.ModifiedUtc, True));
      Obj.AddPair('sha256', Pair.Value.SHA256);
      Files.AddElement(Obj);
    end;
    TempFile := FileName + '.tmp';
    TFile.WriteAllText(ToExtendedPath(TempFile), Root.Format(2), TEncoding.UTF8);
    if FileExists(ToExtendedPath(FileName)) then
      TFile.Delete(ToExtendedPath(FileName));
    TFile.Move(ToExtendedPath(TempFile), ToExtendedPath(FileName));
  finally
    Root.Free;
  end;
end;

procedure TBackupEngine.LoadBaseManifest;
begin
  case FJob.Options.Kind of
    bkFull: FBaseManifest.Clear;
    bkIncremental: LoadManifest(LatestManifestFile, FBaseManifest);
    bkDifferential: LoadManifest(FullManifestFile, FBaseManifest);
  end;
  if (FJob.Options.Kind <> bkFull) and (FBaseManifest.Count = 0) then
    EmitLog(llWarning, 'Nao existe manifesto base; os arquivos serao tratados como novos.');
end;

function TBackupEngine.ComputeSHA256(const FileName: string): string;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(ToExtendedPath(FileName),
    fmOpenRead or fmShareDenyNone);
  try
    Result := THashSHA2.GetHashString(Stream);
  finally
    Stream.Free;
  end;
end;

function TBackupEngine.ShouldCopyItem(Item: TBackupItem): Boolean;
var
  Base: TBackupManifestEntry;
begin
  if FJob.Options.Kind = bkFull then
    Exit(True);
  if not FBaseManifest.TryGetValue(LowerCase(Item.RelativePath), Base) then
    Exit(True);
  Result := (Base.Size <> Item.Size) or
    (Abs(SecondsBetween(Base.ModifiedUtc, Item.ModifiedUtc)) > 2);
  if not Result and FJob.Options.VerifyHash and (Base.SHA256 <> '') then
  begin
    Item.SHA256 := ComputeSHA256(Item.SourcePath);
    Result := not SameText(Item.SHA256, Base.SHA256);
  end;
end;

procedure TBackupEngine.PrepareItems;
var
  Item: TBackupItem;
begin
  LoadBaseManifest;
  FSummary.TotalFiles := FItems.Count;
  FSummary.TotalBytes := 0;
  for Item in FItems do
  begin
    if IsCancelled then
      Exit;
    Item.NeedsCopy := ShouldCopyItem(Item);
    Inc(FSummary.TotalBytes, Item.Size);
  end;
  EmitLog(llInfo, Format('Analise concluida: %d arquivo(s), %s.',
    [FSummary.TotalFiles, FormatBytes(FSummary.TotalBytes)]));
end;

procedure TBackupEngine.CheckDiskSpace;
var
  FreeAvailable, TotalSpace, TotalFree, BytesToCopy, Required, Margin: Int64;
  Item: TBackupItem;
begin
  BytesToCopy := 0;
  for Item in FItems do
    if Item.NeedsCopy then
      Inc(BytesToCopy, Item.Size);
  Margin := Max(FJob.Options.SafetyMarginBytes, BytesToCopy div 20);
  Required := BytesToCopy + Margin;
  if FJob.Options.CompressZip then
    Inc(Required, BytesToCopy);
  if not GetDiskFreeSpaceEx(PChar(FJob.Destination), FreeAvailable,
    TotalSpace, @TotalFree) then
    raise EOSError.CreateFmt('Nao foi possivel consultar o espaco no destino: %s',
      [SysErrorMessage(GetLastError)]);
  if FreeAvailable < Required then
    raise Exception.CreateFmt('Espaco insuficiente. Necessario estimado: %s; disponivel: %s.',
      [FormatBytes(Required), FormatBytes(FreeAvailable)]);
  EmitLog(llInfo, 'Espaco livre validado: ' + FormatBytes(FreeAvailable) + '.');
end;

procedure TBackupEngine.CreateSelectedDirectories;
var
  RelativeDirectory: string;
begin
  for RelativeDirectory in FDirectories do
  begin
    if IsCancelled then
      Exit;
    ForceDirectories(ToExtendedPath(TPath.Combine(FSummary.OutputPath,
      RelativeDirectory)));
  end;
end;

function TBackupEngine.CopyOneFile(Item: TBackupItem): Boolean;
const
  BufferSize = 1024 * 1024;
var
  SourceStream, DestStream: TFileStream;
  Buffer: TBytes;
  ReadCount: Integer;
  CopiedForFile: Int64;
  DestinationFile: string;
  Attempt: Integer;
  SourceHash, DestinationHash: string;
begin
  Result := False;
  DestinationFile := TPath.Combine(FSummary.OutputPath, Item.RelativePath);
  for Attempt := 0 to FJob.Options.RetryCount do
  begin
    if IsCancelled then
      Exit;
    try
      ForceDirectories(ToExtendedPath(ExtractFileDir(DestinationFile)));
      if FileExists(ToExtendedPath(DestinationFile)) then
      begin
        if not FJob.Options.OverwriteExisting then
          raise Exception.Create('O arquivo ja existe e a sobrescrita esta desativada.');
        TFile.SetAttributes(ToExtendedPath(DestinationFile), []);
        TFile.Delete(ToExtendedPath(DestinationFile));
      end;
      SourceStream := TFileStream.Create(ToExtendedPath(Item.SourcePath),
        fmOpenRead or fmShareDenyNone);
      try
        DestStream := TFileStream.Create(ToExtendedPath(DestinationFile), fmCreate);
        try
          SetLength(Buffer, BufferSize);
          CopiedForFile := 0;
          repeat
            if IsCancelled then
              raise EAbort.Create('Copia cancelada pelo usuario.');
            ReadCount := SourceStream.Read(Buffer[0], Length(Buffer));
            if ReadCount > 0 then
            begin
              DestStream.WriteBuffer(Buffer[0], ReadCount);
              Inc(CopiedForFile, ReadCount);
              EmitProgress(bsCopying, Item, CopiedForFile);
            end;
          until ReadCount = 0;
        finally
          DestStream.Free;
        end;
      finally
        SourceStream.Free;
      end;
      TFile.SetLastWriteTimeUtc(ToExtendedPath(DestinationFile), Item.ModifiedUtc);
      if FJob.Options.VerifyHash then
      begin
        EmitProgress(bsVerifying, Item);
        if Item.SHA256 <> '' then
          SourceHash := Item.SHA256
        else
          SourceHash := ComputeSHA256(Item.SourcePath);
        DestinationHash := ComputeSHA256(DestinationFile);
        if not SameText(SourceHash, DestinationHash) then
          raise Exception.Create('A verificacao SHA-256 encontrou divergencia.');
        Item.SHA256 := SourceHash;
        Inc(FSummary.ValidatedFiles);
      end;
      TFile.SetAttributes(ToExtendedPath(DestinationFile),
        TFile.GetAttributes(ToExtendedPath(Item.SourcePath)));
      EmitLog(llInfo, 'Arquivo copiado: ' + Item.SourcePath + ' -> ' + DestinationFile);
      Result := True;
      Exit;
    except
      on E: Exception do
      begin
        if FileExists(ToExtendedPath(DestinationFile)) then
          try
            TFile.SetAttributes(ToExtendedPath(DestinationFile), []);
            TFile.Delete(ToExtendedPath(DestinationFile));
          except
            on CleanupError: Exception do
              EmitLog(llWarning, 'Nao foi possivel remover o arquivo parcial ' +
                DestinationFile + ': ' + CleanupError.Message);
          end;
        if IsCancelled then
          Exit;
        if Attempt < FJob.Options.RetryCount then
        begin
          EmitLog(llWarning, Format('Tentativa %d falhou para %s: %s. Tentando novamente.',
            [Attempt + 1, Item.SourcePath, E.Message]));
          TThread.Sleep(FJob.Options.RetryDelayMs);
        end
        else
          EmitLog(llError, 'Falha ao copiar ' + Item.SourcePath + ': ' + E.Message);
      end;
    end;
  end;
end;

procedure TBackupEngine.CopyItems;
var
  Item: TBackupItem;
begin
  CreateSelectedDirectories;
  for Item in FItems do
  begin
    if IsCancelled then
      Exit;
    if not Item.NeedsCopy then
    begin
      Inc(FSummary.SkippedFiles);
      Inc(FSummary.ProcessedFiles);
      Inc(FSummary.ProcessedBytes, Item.Size);
      EmitLog(llDebug, 'Arquivo sem alteracao ignorado: ' + Item.SourcePath);
      EmitProgress(bsCopying, Item);
      Continue;
    end;
    if CopyOneFile(Item) then
    begin
      Inc(FSummary.CopiedFiles);
      Inc(FSummary.ProcessedFiles);
      Inc(FSummary.ProcessedBytes, Item.Size);
    end
    else if not IsCancelled then
    begin
      Inc(FSummary.ErrorFiles);
      Inc(FSummary.ProcessedFiles);
      Inc(FSummary.ProcessedBytes, Item.Size);
    end;
    EmitProgress(bsCopying, Item);
  end;
end;

procedure TBackupEngine.BuildCurrentManifest;
var
  Item: TBackupItem;
  Entry: TBackupManifestEntry;
begin
  FCurrentManifest.Clear;
  for Item in FItems do
  begin
    Entry.Size := Item.Size;
    Entry.ModifiedUtc := Item.ModifiedUtc;
    Entry.SHA256 := Item.SHA256;
    if FJob.Options.VerifyHash and (Entry.SHA256 = '') then
      try
        Entry.SHA256 := ComputeSHA256(Item.SourcePath);
      except
        on E: Exception do
          EmitLog(llWarning, 'Nao foi possivel registrar o hash de ' +
            Item.SourcePath + ': ' + E.Message);
      end;
    FCurrentManifest.AddOrSetValue(LowerCase(Item.RelativePath), Entry);
  end;
end;

procedure TBackupEngine.SaveManifests;
begin
  EmitProgress(bsSavingManifest);
  BuildCurrentManifest;
  if FJob.Options.Kind = bkFull then
    SaveManifest(FullManifestFile, FCurrentManifest);
  SaveManifest(LatestManifestFile, FCurrentManifest);
  try
    TFile.SetAttributes(ToExtendedPath(StateDirectory), [TFileAttribute.faHidden]);
  except
    on E: Exception do
      EmitLog(llWarning, 'Nao foi possivel ocultar a pasta de estado: ' + E.Message);
  end;
  EmitLog(llInfo, 'Manifesto de estado atualizado.');
end;

procedure TBackupEngine.AddDirectoryToZip(Zip: TObject;
  const DirectoryName, RootDirectory: string);
var
  SR: TSearchRec;
  CurrentPath, RelativePath: string;
begin
  if FindFirst(IncludeTrailingPathDelimiter(ToExtendedPath(DirectoryName)) + '*',
    faAnyFile, SR) <> 0 then
    Exit;
  try
    repeat
      if IsCancelled then
        Exit;
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      CurrentPath := TPath.Combine(DirectoryName, SR.Name);
      if (SR.Attr and faDirectory) <> 0 then
        AddDirectoryToZip(Zip, CurrentPath, RootDirectory)
      else
      begin
        RelativePath := CurrentPath.Substring(
          Length(IncludeTrailingPathDelimiter(RootDirectory)));
        TZipFile(Zip).Add(ToExtendedPath(CurrentPath), RelativePath);
        EmitLog(llDebug, 'Adicionado ao ZIP: ' + RelativePath);
      end;
    until FindNext(SR) <> 0;
  finally
    System.SysUtils.FindClose(SR);
  end;
end;

procedure TBackupEngine.CompressOutput;
var
  Zip: TZipFile;
begin
  if IsCancelled then
    Exit;
  EmitProgress(bsCompressing);
  FSummary.ZipPath := FSummary.OutputPath + '.zip';
  if FileExists(ToExtendedPath(FSummary.ZipPath)) then
    TFile.Delete(ToExtendedPath(FSummary.ZipPath));
  Zip := TZipFile.Create;
  try
    Zip.Open(ToExtendedPath(FSummary.ZipPath), zmWrite);
    AddDirectoryToZip(Zip, FSummary.OutputPath, FSummary.OutputPath);
    Zip.Close;
  finally
    Zip.Free;
  end;
  if not FileExists(ToExtendedPath(FSummary.ZipPath)) or
     (TFile.GetSize(ToExtendedPath(FSummary.ZipPath)) = 0) then
    raise Exception.Create('O arquivo ZIP nao foi criado corretamente.');
  EmitLog(llInfo, 'Backup compactado em: ' + FSummary.ZipPath);
end;

procedure TBackupEngine.DetermineFinalState;
begin
  if IsCancelled then
  begin
    FSummary.State := brCancelled;
    FSummary.MessageText := 'Backup cancelado pelo usuario.';
  end
  else if (FSummary.ErrorFiles > 0) and (FSummary.CopiedFiles > 0) then
  begin
    FSummary.State := brPartial;
    FSummary.MessageText := 'Backup concluido parcialmente; consulte o log.';
  end
  else if FSummary.ErrorFiles > 0 then
  begin
    FSummary.State := brFailed;
    FSummary.MessageText := 'O backup falhou; consulte o log.';
  end
  else
  begin
    FSummary.State := brSuccess;
    FSummary.MessageText := 'Backup concluido com sucesso.';
  end;
end;

function TBackupEngine.Execute: TBackupSummary;
var
  ErrorText, RunName: string;
begin
  FSummary := Default(TBackupSummary);
  FProgress := Default(TBackupProgress);
  FSummary.State := brFailed;
  FSummary.StartedAt := Now;
  FStartedTick := GetTickCount64;
  try
    EmitProgress(bsValidating);
    if not ValidateJob(FJob, ErrorText) then
      raise Exception.Create(ErrorText);
    FJob.Destination := NormalizePath(FJob.Destination);
    ForceDirectories(ToExtendedPath(FJob.Destination));
    FLogger := TBackupLogger.Create(TPath.Combine(FJob.Destination, 'Logs'));
    EmitLog(llInfo, 'Inicio do backup. Usuario: ' + GetEnvironmentVariable('USERNAME') +
      '; computador: ' + GetEnvironmentVariable('COMPUTERNAME') + '.');
    EmitLog(llInfo, 'Tipo: ' + BackupKindToText(FJob.Options.Kind) +
      '; destino: ' + FJob.Destination + '.');
    ScanSources;
    if IsCancelled then
      raise EAbort.Create('Operacao cancelada.');
    PrepareItems;
    CheckDiskSpace;
    RunName := 'Backup_' + BackupKindToText(FJob.Options.Kind) + '_' +
      FormatDateTime('yyyy-mm-dd_hh-nn-ss', Now);
    FSummary.OutputPath := EnsureUniqueDirectory(FJob.Destination, RunName);
    ForceDirectories(ToExtendedPath(FSummary.OutputPath));
    CopyItems;
    if not IsCancelled and (FSummary.ErrorFiles = 0) then
    begin
      if FJob.Options.CompressZip then
        CompressOutput;
      if not IsCancelled then
        SaveManifests;
    end;
  except
    on E: EAbort do
      EmitLog(llWarning, E.Message);
    on E: Exception do
    begin
      Inc(FSummary.ErrorFiles);
      EmitLog(llCritical, E.ClassName + ': ' + E.Message);
      FSummary.MessageText := E.Message;
    end;
  end;
  DetermineFinalState;
  FSummary.FinishedAt := Now;
  if Assigned(FLogger) then
  begin
    EmitLog(llInfo, 'Resultado: ' + BackupResultToText(FSummary.State) +
      Format('. Copiados: %d; ignorados: %d; erros: %d.',
      [FSummary.CopiedFiles, FSummary.SkippedFiles, FSummary.ErrorFiles]));
    try
      FLogger.Save;
      FSummary.LogPath := FLogger.FileName;
    except
      on E: Exception do
      begin
        Inc(FSummary.ErrorFiles);
        if FSummary.State = brSuccess then
          FSummary.State := brWarning;
        if Assigned(FOnLog) then
          FOnLog(Self, '[ERRO] Nao foi possivel salvar o log: ' + E.Message);
      end;
    end;
  end;
  EmitProgress(bsFinished);
  Result := FSummary;
end;

end.
