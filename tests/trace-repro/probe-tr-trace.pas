program probe_tr;
{ probe-enc twin + heapmgr trace: echoes every SysGetMem/SysFreeMem from
  program start until the teardown crash, to identify which free writes
  the zero into the TEncoding.Default object's VMT slot. }
uses classes, sysutils, heapmgr;

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
  HeapTraceEnable;
  DumpObj('TEncoding.Default', TEncoding.Default);
  writeln('is standard : ', TEncoding.IsStandardEncoding(TEncoding.Default));
  writeln('TRACE LIVE - now exiting');
end.
