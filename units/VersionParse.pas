unit VersionParse;

interface

type
  TVersionKey = record
    Y, M, D, N: Integer;
    function IsValid: Boolean;
    function CompareTo(const Other: TVersionKey): Integer;
    function AsString: string;
    class function Empty: TVersionKey; static;
  end;

  TModuleIdentity = record
    ComponentId: string;
    VersionRaw: string;
    VersionKey: TVersionKey;
    HasComponent: Boolean;
    HasVersion: Boolean;
  end;

function ParseVersionKey(const Raw: string; out Key: TVersionKey): Boolean;
function ExtractModuleIdentity(const Text: string): TModuleIdentity;
/// Legacy: //<stem> или //<stem>.ert … ver: YYYY.MM.DD-NN
function HasLegacyStemVerMarker(const Text, Stem: string;
  out VersionRaw: string): Boolean;
/// Любой из переданных stem
function HasAnyLegacyStemVerMarker(const Text: string;
  const Stems: array of string; out VersionRaw: string): Boolean;
/// Совместимость: frATOL54 / frATOL54_comm
function HasLegacyAtolVerMarker(const Text: string; out VersionRaw: string): Boolean;
function CompareVersionStrings(const A, B: string): Integer;

implementation

uses
  System.SysUtils,
  System.RegularExpressions;

function TVersionKey.IsValid: Boolean;
begin
  Result := (Y > 0) and (M >= 1) and (M <= 12) and (D >= 1) and (D <= 31) and (N >= 0);
end;

function TVersionKey.CompareTo(const Other: TVersionKey): Integer;
begin
  if Y <> Other.Y then Exit(Y - Other.Y);
  if M <> Other.M then Exit(M - Other.M);
  if D <> Other.D then Exit(D - Other.D);
  Result := N - Other.N;
end;

function TVersionKey.AsString: string;
begin
  if not IsValid then
    Exit('');
  Result := Format('%.4d.%.2d.%.2d-%.2d', [Y, M, D, N]);
end;

class function TVersionKey.Empty: TVersionKey;
begin
  Result.Y := 0;
  Result.M := 0;
  Result.D := 0;
  Result.N := 0;
end;

function ParseVersionKey(const Raw: string; out Key: TVersionKey): Boolean;
var
  M: TMatch;
begin
  Key := TVersionKey.Empty;
  M := TRegEx.Match(Trim(Raw), '^(\d{4})\.(\d{2})\.(\d{2})-(\d+)$');
  Result := M.Success;
  if not Result then
    Exit;
  Key.Y := StrToInt(M.Groups[1].Value);
  Key.M := StrToInt(M.Groups[2].Value);
  Key.D := StrToInt(M.Groups[3].Value);
  Key.N := StrToInt(M.Groups[4].Value);
  Result := Key.IsValid;
end;

function ExtractHeaderValue(const Text, FieldName: string): string;
var
  M: TMatch;
begin
  M := TRegEx.Match(
    Text,
    '(?im)^\s*//\s*' + FieldName + '\s*:\s*(.+?)\s*$'
  );
  if M.Success then
    Result := Trim(M.Groups[1].Value)
  else
    Result := '';
end;

function EscapeRegexLiteral(const S: string): string;
var
  I: Integer;
  Ch: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    if CharInSet(Ch, ['\', '^', '$', '.', '|', '?', '*', '+', '(', ')', '[', ']', '{', '}']) then
      Result := Result + '\' + Ch
    else
      Result := Result + Ch;
  end;
end;

function HasLegacyStemVerMarker(const Text, Stem: string;
  out VersionRaw: string): Boolean;
var
  M: TMatch;
  Key: TVersionKey;
  Pattern: string;
begin
  VersionRaw := '';
  if Trim(Stem) = '' then
    Exit(False);
  // //\s*<stem>(?:\.ert)?\b[^\r\n]*\bver:\s*(YYYY.MM.DD-NN)
  Pattern := '(?im)//\s*' + EscapeRegexLiteral(Stem) +
    '(?:\.ert)?\b[^\r\n]*\bver:\s*(\d{4}\.\d{2}\.\d{2}-\d+)';
  M := TRegEx.Match(Text, Pattern);
  Result := M.Success and ParseVersionKey(M.Groups[1].Value, Key);
  if Result then
    VersionRaw := M.Groups[1].Value;
end;

function HasAnyLegacyStemVerMarker(const Text: string;
  const Stems: array of string; out VersionRaw: string): Boolean;
var
  Stem: string;
begin
  VersionRaw := '';
  for Stem in Stems do
    if HasLegacyStemVerMarker(Text, Stem, VersionRaw) then
      Exit(True);
  Result := False;
end;

function HasLegacyAtolVerMarker(const Text: string; out VersionRaw: string): Boolean;
begin
  Result := HasAnyLegacyStemVerMarker(
    Text,
    ['frATOL54', 'frATOL54_comm'],
    VersionRaw
  );
end;

function ExtractModuleIdentity(const Text: string): TModuleIdentity;
var
  Head: string;
  Lines: TArray<string>;
  I: Integer;
  M: TMatch;
  Key: TVersionKey;
  Raw: string;
begin
  Result.ComponentId := '';
  Result.VersionRaw := '';
  Result.VersionKey := TVersionKey.Empty;
  Result.HasComponent := False;
  Result.HasVersion := False;

  Result.ComponentId := ExtractHeaderValue(Text, 'component');
  Result.HasComponent := Result.ComponentId <> '';

  Raw := ExtractHeaderValue(Text, 'version');
  if (Raw <> '') and ParseVersionKey(Raw, Key) then
  begin
    Result.VersionRaw := Raw;
    Result.VersionKey := Key;
    Result.HasVersion := True;
    Exit;
  end;

  Lines := Text.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  Head := '';
  for I := 0 to High(Lines) do
  begin
    if I >= 40 then
      Break;
    if Head <> '' then
      Head := Head + #10;
    Head := Head + Lines[I];
  end;

  M := TRegEx.Match(Head, '(?i)\bver:\s*(\d{4}\.\d{2}\.\d{2}-\d+)\b');
  if M.Success and ParseVersionKey(M.Groups[1].Value, Key) then
  begin
    Result.VersionRaw := M.Groups[1].Value;
    Result.VersionKey := Key;
    Result.HasVersion := True;
    Exit;
  end;

  M := TRegEx.Match(Text, '(?i)глЭтотМодульВерсияМодуля\s*=\s*"([^"]+)"');
  if M.Success then
  begin
    Raw := Trim(M.Groups[1].Value);
    Result.VersionRaw := Raw;
    if ParseVersionKey(Raw, Key) then
    begin
      Result.VersionKey := Key;
      Result.HasVersion := True;
    end;
  end;
end;

function CompareVersionStrings(const A, B: string): Integer;
var
  KA, KB: TVersionKey;
  OKA, OKB: Boolean;
begin
  OKA := ParseVersionKey(A, KA);
  OKB := ParseVersionKey(B, KB);
  if OKA and OKB then
    Exit(KA.CompareTo(KB));
  if OKA and not OKB then
    Exit(1);
  if OKB and not OKA then
    Exit(-1);
  Result := CompareText(A, B);
end;

end.
