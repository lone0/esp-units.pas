{ webtbs provenance: trunk tests/webtbs/tw2891.pas }

uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
 Math;

 var
 d: Double;
 e: Extended;

 begin
 d := 0;
 e := 0;

 d := Min(d, e);
 end.
