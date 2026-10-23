{ webtbs provenance: trunk tests/webtbs/tw13552.pas }

uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  sysutils;

var
  s: ansistring;
begin
  ThousandSeparator:=#0;
  DecimalSeparator:='.';
  s:=formatfloat('#,0.00',1000.0);
  writeln(s);
  if (s<>'1000.00') then
    halt(1);
end.
