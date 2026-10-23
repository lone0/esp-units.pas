{ webtbs provenance: trunk tests/webtbs/tw39735.pas }

program t_datetime_to_timestamp;
uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  sysutils;
var
  LStart: TDateTime;
begin
  LStart := DateTimeToTimeStamp(Now).Time;
end.
