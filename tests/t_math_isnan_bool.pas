{ webtbs provenance: trunk tests/webtbs/tw37398.pas }

program t_math_isnan_bool;

{$mode objfpc}{$H+}

uses idfheap, math;
var d: double;
  temp: Boolean;
begin
  d := NaN;
  temp := IsNan(d) or (d = 0);
  writeln(temp);
end.
