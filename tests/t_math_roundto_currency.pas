{ webtbs provenance: trunk tests/webtbs/tw19077.pas }

uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  math;
var
  c : currency;
begin
{$ifdef FPC_HAS_TYPE_EXTENDED}
  c:=1.5625;
  c:=RoundTo(c,-1);
  if c<>1.6 then
    halt(1);
  writeln('ok');
{$endif FPC_HAS_TYPE_EXTENDED}
end.


