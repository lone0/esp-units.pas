{ webtbs provenance: trunk tests/webtbs/tw22290.pas }

uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  SysUtils;

begin
  if formatfloat('0e',-1)<>'-1e' then
    halt(1);
end.
