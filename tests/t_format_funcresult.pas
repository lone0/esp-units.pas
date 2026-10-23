{ webtbs provenance: trunk tests/webtbs/tw9704.pas }

program bug;

{$H+}

uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  SysUtils;

function GetString: String;
begin
end;

begin
  WriteLn(Format('%s', [GetString()]));
end.