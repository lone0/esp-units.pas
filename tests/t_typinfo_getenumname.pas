{ webtbs provenance: trunk tests/webtbs/tw9551a.pas }


uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  TypInfo,sysutils;

type
  tmy2enum = (e1,e2,e3,e4);


procedure Test;
begin
  if (GetEnumName(TypeInfo(TMy2Enum), Ord(e3)) <> 'e3') then
    halt(1);
end;

begin
 Test;
end.
