{ webtbs provenance: trunk tests/webtbs/tw8611.pas }

program t_classes_ifdeclared;

{$mode objfpc}

uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  Classes;

  {$if declared(TObject)}
  {$endif}

begin
end.
