{$mode objfpc}{$H+}
program t_encoding_roundtrip;
{ TEncoding functional smoke: the three core operations across the three
  workhorse encodings.
    1. GetBytes    - string -> encoded bytes (ASCII / UTF-8 incl. CJK / UTF-16LE)
    2. GetString   - bytes -> string, round-trip identity
    3. GetPreamble - BOM bytes
  Byte output is hex for determinism. idfheap first: heap routing. }
uses idfheap, classes, sysutils;

var
  B: TBytes;
  U: UnicodeString;

  function Hexs(const AB: TBytes): string;
  var
    i: Integer;
  begin
    Result := '';
    for i := 0 to High(AB) do
      Result := Result + hexstr(AB[i], 2) + ' ';
  end;

  procedure Check(const what: string; ok: boolean);
  begin
    if ok then
      writeln(what, ': ok')
    else
    begin
      writeln(what, ': FAIL');
      Halt(1);
    end;
  end;

begin
  { 1. ASCII: GetBytes + GetString round-trip }
  B := TEncoding.ASCII.GetBytes('AB');
  Check('ASCII GetBytes', (Length(B) = 2) and (B[0] = $41) and (B[1] = $42));
  Check('ASCII GetString', TEncoding.ASCII.GetString(B) = 'AB');

  { 2. UTF-8: multi-byte CJK (U+55B5 -> E5 96 B5) + round-trip }
  U := TEncoding.UTF8.GetString(TBytes.Create($E5, $96, $B5));
  Check('UTF8 CJK decode', (Length(U) = 1) and (Ord(U[1]) = $55B5));
  B := TEncoding.UTF8.GetBytes(U);
  Check('UTF8 CJK encode', (Length(B) = 3) and (B[0] = $E5) and (B[1] = $96) and (B[2] = $B5));

  { 3. Unicode UTF-16LE: bytes + BOM preamble }
  U := 'AB';
  B := TEncoding.Unicode.GetBytes(U);
  Check('Unicode GetBytes', (Length(B) = 4) and (B[0] = $41) and (B[1] = 0) and
        (B[2] = $42) and (B[3] = 0));
  B := TEncoding.Unicode.GetPreamble;
  Check('Unicode preamble', (Length(B) = 2) and (B[0] = $FF) and (B[1] = $FE));

  writeln('t_encoding roundtrip OK');
end.
