{ webtbs provenance: trunk tests/webtbs/tw38642.pas }

{ %NORUN }

program t_generics_enum_list_decl;
{$mode delphi}{$H+}
uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  classes,
  generics.collections;
type
  TMonthType = (January, February, May=10, June, July);
  TMonthList = TList<TMonthType>;
var
  myList : TMonthList;
begin
end.
