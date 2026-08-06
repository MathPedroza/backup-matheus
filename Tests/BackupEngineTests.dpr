program BackupEngineTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  uBackupTypes in '..\View\uBackupTypes.pas',
  uBackupUtils in '..\View\uBackupUtils.pas',
  uBackupLogger in '..\View\uBackupLogger.pas',
  uBackupEngine in '..\View\uBackupEngine.pas';

procedure AssertTrue(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create('FALHOU: ' + MessageText);
end;

function NewJob(const SourceDirectory, StandaloneFile,
  Destination: string; Kind: TBackupKind): TBackupJob;
begin
  Result := TBackupJob.Create;
  Result.Name := 'Teste automatico';
  Result.Sources.Add(SourceDirectory);
  if StandaloneFile <> '' then
    Result.Sources.Add(StandaloneFile);
  Result.Destination := Destination;
  Result.Options.Kind := Kind;
  Result.Options.IncludeEmptyDirectories := True;
  Result.Options.VerifyHash := True;
  Result.Options.SafetyMarginBytes := 1024;
end;

function ExecuteJob(Job: TBackupJob): TBackupSummary;
var
  Engine: TBackupEngine;
begin
  Engine := TBackupEngine.Create(Job);
  try
    Result := Engine.Execute;
  finally
    Engine.Free;
  end;
end;

procedure RunTests;
var
  TestRoot, SourceDirectory, NestedDirectory, EmptyDirectory: string;
  StandaloneFile, Destination, ErrorText, ExpectedFile: string;
  Job: TBackupJob;
  Summary: TBackupSummary;
  Engine: TBackupEngine;
begin
  TestRoot := TPath.Combine(TPath.GetTempPath,
    'BackupEngineTests_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now));
  SourceDirectory := TPath.Combine(TestRoot, 'Origem A\Dados');
  NestedDirectory := TPath.Combine(SourceDirectory, 'Nivel 1');
  EmptyDirectory := TPath.Combine(SourceDirectory, 'Pasta vazia');
  StandaloneFile := TPath.Combine(TestRoot, 'arquivo avulso.txt');
  Destination := TPath.Combine(TestRoot, 'Destino');
  ForceDirectories(NestedDirectory);
  ForceDirectories(EmptyDirectory);
  ForceDirectories(Destination);
  TFile.WriteAllText(TPath.Combine(NestedDirectory, 'arquivo.txt'), 'versao 1',
    TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(SourceDirectory, 'com acento ç.txt'), 'acentos',
    TEncoding.UTF8);
  TFile.WriteAllText(StandaloneFile, 'avulso', TEncoding.UTF8);

  try
    Job := NewJob(SourceDirectory, StandaloneFile, Destination, bkFull);
    Job.Options.CompressZip := True;
    Summary := ExecuteJob(Job);
    AssertTrue(Summary.State = brSuccess, 'backup total: ' + Summary.MessageText);
    AssertTrue(Summary.CopiedFiles = 3, 'total deveria copiar 3 arquivos');
    AssertTrue(Summary.ValidatedFiles = 3, 'total deveria validar 3 hashes');
    AssertTrue(FileExists(Summary.ZipPath), 'ZIP do total nao foi criado');
    ExpectedFile := TPath.Combine(Summary.OutputPath,
      TPath.Combine(BuildSafeSourceRoot(SourceDirectory), 'Nivel 1\arquivo.txt'));
    AssertTrue(FileExists(ExpectedFile), 'estrutura de subpastas nao foi preservada');
    AssertTrue(DirectoryExists(TPath.Combine(Summary.OutputPath,
      TPath.Combine(BuildSafeSourceRoot(SourceDirectory), 'Pasta vazia'))),
      'pasta vazia nao foi criada');
    Writeln('OK: backup total, estrutura, ZIP e SHA-256');

    TFile.WriteAllText(TPath.Combine(NestedDirectory, 'arquivo.txt'), 'versao 2',
      TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(SourceDirectory, 'novo.txt'), 'novo',
      TEncoding.UTF8);
    Job := NewJob(SourceDirectory, StandaloneFile, Destination, bkIncremental);
    Summary := ExecuteJob(Job);
    AssertTrue(Summary.State = brSuccess, 'backup incremental');
    AssertTrue(Summary.CopiedFiles = 2, 'incremental deveria copiar alterado e novo');
    AssertTrue(Summary.SkippedFiles = 2, 'incremental deveria ignorar 2 inalterados');
    Writeln('OK: backup incremental por manifesto');

    Job := NewJob(SourceDirectory, StandaloneFile, Destination, bkDifferential);
    Summary := ExecuteJob(Job);
    AssertTrue(Summary.State = brSuccess, 'backup diferencial');
    AssertTrue(Summary.CopiedFiles = 2, 'diferencial deve comparar com o ultimo total');
    Writeln('OK: backup diferencial usa o manifesto total como base');

    Job := NewJob(SourceDirectory, '', SourceDirectory, bkFull);
    try
      AssertTrue(not TBackupEngine.ValidateJob(Job, ErrorText),
        'origem igual ao destino deveria ser rejeitada');
    finally
      Job.Free;
    end;
    Job := NewJob(SourceDirectory, '', TPath.Combine(SourceDirectory, 'Destino'), bkFull);
    try
      AssertTrue(not TBackupEngine.ValidateJob(Job, ErrorText),
        'destino dentro da origem deveria ser rejeitado');
    finally
      Job.Free;
    end;
    Writeln('OK: protecao contra recursao e sobreposicao de caminhos');

    Job := NewJob(SourceDirectory, '', Destination, bkFull);
    Engine := TBackupEngine.Create(Job);
    try
      Engine.Cancel;
      Summary := Engine.Execute;
      AssertTrue(Summary.State = brCancelled, 'cancelamento cooperativo');
    finally
      Engine.Free;
    end;
    Writeln('OK: cancelamento cooperativo');
  finally
    try
      if DirectoryExists(TestRoot) then
        TDirectory.Delete(TestRoot, True);
    except
      on E: Exception do
        Writeln('AVISO: nao foi possivel limpar a pasta de teste: ', E.Message);
    end;
  end;
end;

begin
  try
    RunTests;
    Writeln('TODOS OS TESTES PASSARAM.');
    ExitCode := 0;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
