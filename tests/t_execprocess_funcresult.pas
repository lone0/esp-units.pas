{ webtbs provenance: trunk tests/webtbs/tw19851b.pas }

uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  sysutils;

begin
{$ifdef WINDOWS}
  executeprocess(GetEnvironmentVariable('COMSPEC'),'/c echo abcdefghijklmnopqrstuvwxyz1 | tw19851a');
{$endif WINDOWS}
end.
