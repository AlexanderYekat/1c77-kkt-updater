unit HashUtil;

interface

uses
  System.SysUtils;

function Sha256HexOfFile(const FilePath: string): string;
function Sha256HexOfBytes(const Data: TBytes): string;
function SameSha256Hex(const A, B: string): Boolean;

implementation

uses
  System.Classes,
  System.Hash;

function Sha256HexOfFile(const FilePath: string): string;
var
  Hash: THashSHA2;
  Stream: TFileStream;
  Buf: TBytes;
  N: Integer;
begin
  Hash := THashSHA2.Create(SHA256);
  Stream := TFileStream.Create(FilePath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Buf, 64 * 1024);
    repeat
      N := Stream.Read(Buf[0], Length(Buf));
      if N > 0 then
        Hash.Update(Buf, N);
    until N = 0;
    Result := LowerCase(Hash.HashAsString);
  finally
    Stream.Free;
  end;
end;

function Sha256HexOfBytes(const Data: TBytes): string;
var
  Hash: THashSHA2;
begin
  Hash := THashSHA2.Create(SHA256);
  if Length(Data) > 0 then
    Hash.Update(Data);
  Result := LowerCase(Hash.HashAsString);
end;

function SameSha256Hex(const A, B: string): Boolean;
begin
  Result := SameText(Trim(A), Trim(B));
end;

end.
