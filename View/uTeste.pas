unit uTeste;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs;

type
  TForm1 = class(TForm)
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

// Função para compactar em .zip
function TfrmBackup.CompactarParaZip(const Origem, DestinoZip: string): Boolean;
var
  Zip: TZipFile;
  SR: TSearchRec;
  PastaOrigem, PastaDestino, ArquivoZip, FilePath: string;
  i: Integer;
begin
  for i := 0 to MemoOrigens.Lines.Count - 1 do
  begin
    PastaOrigem  := MemoOrigens.Lines[i];
    PastaDestino := Trim(Edit1.Text);

    // Verifica se a pasta de origem existe
  if not DirectoryExists(PastaDestino) then
  begin
    Application.MessageBox(PChar('A pasta especificada não existe: ' +
    PastaOrigem), 'Atenção!', MB_ICONERROR + MB_OK);
    Exit;
  end;

  // Remove barra final, se existir
  if PastaOrigem.EndsWith('\') then
    PastaOrigem := Copy(PastaOrigem, 1, Length(PastaOrigem) - 1);

  // Define a subpasta 'compactado' dentro da pasta de origem
  PastaDestino := PastaDestino + '\compactado';
  ForceDirectories(PastaDestino); // Cria se não existir

  // Caminho completo do arquivo ZIP
  ArquivoZip := PastaDestino + '\bkp.zip';

  // Remove ZIP anterior se já existir
  if FileExists(ArquivoZip) then
    DeleteFile(ArquivoZip);

  // Cria e adiciona arquivos ao ZIP
  Zip := TZipFile.Create;
  try
    Zip.Open(ArquivoZip, zmWrite);

    if FindFirst(PastaOrigem + '\*.*', faAnyFile, SR) = 0 then
      begin
        repeat
          if (SR.Name <> '.') and (SR.Name <> '..') and (SR.Name <> 'compactado')
          then // Evita incluir a pasta de destino
          begin
            FilePath := PastaOrigem + '\' + SR.Name;
            if not DirectoryExists(FilePath) then
              Zip.Add(FilePath, SR.Name);
          end;
        until FindNext(SR) <> 0;
        FindClose(SR);
      end;

      Zip.Close;
      Application.MessageBox(PChar('Backup compactado com sucesso em: ' +
        ArquivoZip), 'Informação!', MB_ICONINFORMATION + MB_OK);
    finally
      Zip.Free;
    end;
  end;
end;

 // Faz a verificação se o Backup vai ser compactado (.zip)
      if chkCompactarZip.Checked then
        CompactarParaZip(Origem, Destino + '\compactado\bkp_' + IntToStr(I+1) + '.zip');

end.
