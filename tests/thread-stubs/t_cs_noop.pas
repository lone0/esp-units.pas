program t_cs_noop; {$mode objfpc}{$H+}
uses idfheap, syncobjs;
var C: TCriticalSection;
begin
  C := TCriticalSection.Create;   { note: a class, must be instantiated }
  C.Enter;
  C.Enter;                        { single task: re-enter is fine too }
  C.Leave;
  C.Leave;
  C.Free;
  writeln('cs ok (no-op critical section is correct for one task)');
end.
