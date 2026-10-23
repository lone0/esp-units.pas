program probe_enc;
{ tw1251b twin: same global var + dead function; body adds state prints +
  a raw memory dump of TEncoding.Default BEFORE the exit teardown runs,
  to pin down what the exit-crash victim object actually is. }
uses idfheap, classes, sysutils;

type
  TWordArr = array[0..3] of LongWord;
  PTWordArr = ^TWordArr;

var
  list : TStringList;

function strcat(dest, source : pchar) : pchar;
begin
end;

procedure DumpObj(prefix: string; p: TObject);
var
  i: longint;
  w: PTWordArr;
begin
  w := pointer(p);
  writeln(prefix+' @', hexstr(ptruint(p), 8), ' :');
  for i := 0 to 3 do
    writeln('  +', i*4, ' = ', hexstr(w^[i], 8));
end;

begin
  DumpObj('TEncoding.Default', TEncoding.Default);
  writeln('is standard : ', TEncoding.IsStandardEncoding(TEncoding.Default));
  writeln('SYSUTILS+CLASSES init ok, now exiting');
end.
