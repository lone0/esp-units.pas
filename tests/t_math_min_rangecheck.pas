{ webtbs provenance: trunk tests/webtbs/tw3900.pas }

{$Q+}
uses idfheap, math;
var s1,s2:byte;
begin
s1:=2;
s2:=77;
writeln(0-min(s1,s2));
end.
