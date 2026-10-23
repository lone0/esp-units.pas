{ webtbs provenance: trunk tests/webtbs/tw27173.pas }

program t_range_div_subrange;

{$mode Delphi}

uses idfheap, sysutils;

type a = 1..MaxInt;

var b: a;
    c: integer;

begin
 b := 3;
 c := -5 div b;
 writeln(c);
end.
