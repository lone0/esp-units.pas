{ webtbs provenance: trunk tests/webtbs/tw37969.pas }

{$mode objfpc}
program t_trim_variant;

uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  sysutils;
var
  aValue: variant;
  s: String;
begin
  s := Trim( aValue );
end.
