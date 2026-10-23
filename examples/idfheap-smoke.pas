program idfheap_smoke;

{$mode objfpc}{$H+}

{ Smoke test for the idfheap unit (production manager routing, in contrast
  to probe-idfmm's mid-run hot-swap proof). idfheap is FIRST in uses, so
  the IDF-backed manager is installed before sysutils/classes initialize
  (init order: heapmgr -> idfheap -> sysutils -> ... -> classes).

  Proves:
   1. every allocation - even from these unit inits - lives in the IDF pool
      (address check: expect 0x3FCBxxxx = IDF internal-DRAM pool, NOT the
      0x3FC9Cxxx static -Ch block);
   2. GetFPCHeapStatus reports real IDF-pool numbers;
   3. a full classes/strings/dynarray workload runs on the managed pool;
   4. clean exit: classes' teardown (TThreadList, TEncodings, ...) frees
      everything through the IDF manager - RunError-free, exit 0. }

uses
  idfheap,       { MUST be first: installs the manager before all inits }
  classes, sysutils;

var
  p: pointer;
  st: TFPCHeapStatus;
  lst: TStringList;
  i: smallint;
  s: SizeInt;
  big: array of longint;
begin
  p := GetMem(4096);
  writeln('GetMem(4096) @', hexstr(ptruint(p), 8));

  st := GetFPCHeapStatus;
  writeln('IDF pool: used=', st.CurrHeapUsed, ' free=', st.CurrHeapFree,
          ' size=', st.CurrHeapSize);

  lst := TStringList.Create;
  for i := 1 to 100 do
    lst.Add('value' + IntToStr(1000 + i));
  lst.Sort;
  s := Length(lst[99]);
  writeln('TStringList 100 items sorted; last item length ', s);

  for i := 0 to 99 do
    begin
      SetLength(big, (i + 1) * 500);
      big[i] := i * i;
    end;
  writeln('dynarray 100 x 500 slots ok, big[99]=', big[99]);
  SetLength(big, 0);

  lst.Free;
  FreeMem(p);
  writeln('idfheap smoke OK');
end.
