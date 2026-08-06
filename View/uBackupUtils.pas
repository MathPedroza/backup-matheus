unit uBackupUtils;

interface

uses
  System.SysUtils, System.Classes;

function NormalizePath(const Value: string): string;
function IsSamePath(const Left, Right: string): Boolean;
function IsPathInside(const ChildPath, ParentPath: string): Boolean;
function PathsOverlap(const Left, Right: string): Boolean;
function ToExtendedPath(const Value: string): string;
function BuildSafeSourceRoot(const SourcePath: string): string;
function IsTemporaryName(const FileName: string): Boolean;
function IsDangerousDestination(const Value: string): Boolean;
function EnsureUniqueDirectory(const ParentPath, BaseName: string): string;
function FormatBytes(const Value: Int64): string;

implementation

uses
  System.IOUtils, System.StrUtils, System.DateUtils;

function NormalizePath(const Value: string): string;
var
  LValue: string;
begin
  LValue := Trim(Value);
  if LValue = '' then
    Exit('');

  LValue := TPath.GetFullPath(LValue);
  if (Length(LValue) > 3) and LValue.EndsWith(PathDelim) then
    LValue := ExcludeTrailingPathDelimiter(LValue);
  Result := LValue;
end;

function IsSamePath(const Left, Right: string): Boolean;
begin
  Result := SameText(NormalizePath(Left), NormalizePath(Right));
end;

function IsPathInside(const ChildPath, ParentPath: string): Boolean;
var
  LChild, LParent: string;
begin
  LChild := IncludeTrailingPathDelimiter(NormalizePath(ChildPath));
  LParent := IncludeTrailingPathDelimiter(NormalizePath(ParentPath));
  Result := StartsText(LParent, LChild) and not SameText(LChild, LParent);
end;

function PathsOverlap(const Left, Right: string): Boolean;
begin
  Result := IsSamePath(Left, Right) or IsPathInside(Left, Right) or
    IsPathInside(Right, Left);
end;

function ToExtendedPath(const Value: string): string;
var
  LPath: string;
begin
  LPath := NormalizePath(Value);
  if StartsText('\\?\', LPath) then
    Exit(LPath);
  if StartsText('\\', LPath) then
    Result := '\\?\UNC\' + Copy(LPath, 3, MaxInt)
  else
    Result := '\\?\' + LPath;
end;

function SanitizeRootName(const Value: string): string;
var
  C: Char;
begin
  Result := '';
  for C in Value do
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.']) then
      Result := Result + C
    else
      Result := Result + '_';
end;

function BuildSafeSourceRoot(const SourcePath: string): string;
var
  LPath, LTail, LServer, LShare: string;
  P: Integer;
begin
  LPath := NormalizePath(SourcePath);
  if StartsText('\\', LPath) then
  begin
    LTail := Copy(LPath, 3, MaxInt);
    P := Pos('\', LTail);
    if P = 0 then
      Exit('Rede_' + SanitizeRootName(LTail));
    LServer := Copy(LTail, 1, P - 1);
    Delete(LTail, 1, P);
    P := Pos('\', LTail);
    if P = 0 then
    begin
      LShare := LTail;
      LTail := '';
    end
    else
    begin
      LShare := Copy(LTail, 1, P - 1);
      Delete(LTail, 1, P);
    end;
    Result := 'Rede_' + SanitizeRootName(LServer) + '_' +
      SanitizeRootName(LShare);
    if LTail <> '' then
      Result := TPath.Combine(Result, LTail);
  end
  else
  begin
    Result := 'Unidade_' + UpCase(LPath[1]);
    LTail := Copy(LPath, 4, MaxInt);
    if LTail <> '' then
      Result := TPath.Combine(Result, LTail);
  end;
end;

function IsTemporaryName(const FileName: string): Boolean;
var
  LName, LExt: string;
begin
  LName := LowerCase(FileName);
  LExt := LowerCase(ExtractFileExt(LName));
  Result := StartsText('~', LName) or
    MatchText(LExt, ['.tmp', '.temp', '.bak', '.part', '.crdownload']) or
    MatchText(LName, ['thumbs.db', 'desktop.ini', 'pagefile.sys',
      'hiberfil.sys', 'swapfile.sys']);
end;

function IsDangerousDestination(const Value: string): Boolean;
var
  LPath, LWindows, LUsers: string;
begin
  LPath := NormalizePath(Value);
  LWindows := NormalizePath(GetEnvironmentVariable('WINDIR'));
  LUsers := NormalizePath(GetEnvironmentVariable('SystemDrive') + '\Users');
  Result := (LPath = '') or (Length(LPath) <= 3) or
    IsSamePath(LPath, LWindows) or IsPathInside(LPath, LWindows) or
    IsSamePath(LPath, LUsers);
end;

function EnsureUniqueDirectory(const ParentPath, BaseName: string): string;
var
  I: Integer;
begin
  Result := TPath.Combine(ParentPath, BaseName);
  I := 1;
  while DirectoryExists(Result) or FileExists(Result + '.zip') do
  begin
    Result := TPath.Combine(ParentPath, BaseName + '_' + Format('%.2d', [I]));
    Inc(I);
  end;
end;

function FormatBytes(const Value: Int64): string;
const
  KB = Int64(1024);
  MB = KB * 1024;
  GB = MB * 1024;
  TB = GB * 1024;
begin
  if Value >= TB then
    Result := FormatFloat('0.00 TB', Value / TB)
  else if Value >= GB then
    Result := FormatFloat('0.00 GB', Value / GB)
  else if Value >= MB then
    Result := FormatFloat('0.00 MB', Value / MB)
  else if Value >= KB then
    Result := FormatFloat('0.00 KB', Value / KB)
  else
    Result := IntToStr(Value) + ' bytes';
end;

end.
