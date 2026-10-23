{ webtbs provenance: trunk tests/webtbs/tw16315a.pas }

program t_math_infinity_assign;
uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  Math;
var
  D: Double;
begin
  D := Infinity;
end.

