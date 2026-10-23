{ webtbs provenance: trunk tests/webtbs/tw1792.pas }

uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  math;
Begin
 WriteLn(power(2,31));
end.
