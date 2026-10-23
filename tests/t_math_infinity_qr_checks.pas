{ webtbs provenance: trunk tests/webtbs/tw07584.pas }

program t_math_infinity_qr_checks;

{$mode delphi}

uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  math;

{$Q+}
{$R+}

begin
  Writeln(Math.Infinity);
end.