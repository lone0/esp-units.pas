{ webtbs provenance: trunk tests/webtbs/tw41025.pas }

{ %OPT=-Sew }
program t_types_case_longbool;
uses idfheap, types;

var b:longbool;

begin
  b:=false;
  case b of
  true: writeln('True');
  false: writeln('False');
  end;
end.
