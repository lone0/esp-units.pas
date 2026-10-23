{ webtbs provenance: trunk tests/webtbs/tw32868.pas }

program t_formatfloat_nan;

{$mode objfpc}{$H+}

uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  Math,SysUtils;

begin
  if FormatFloat('0.#',Nan)<>'NaN' then
    begin
      WriteLn(FormatFloat('0.#',Nan));
      halt(1);
    end;
end.
