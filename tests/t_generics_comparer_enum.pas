{ webtbs provenance: trunk tests/webtbs/tw40331.pas }

program t_generics_comparer_enum;
{$mode delphi}
uses idfheap, Generics.Defaults;
type
  SomeEnum = (zero = 0, two = 2);
var
  z: IEqualityComparer<SomeEnum>;
begin
  z:= TEqualityComparer<SomeEnum>.Default;
  WriteLn('Done');
  //ReadLn;
end.

