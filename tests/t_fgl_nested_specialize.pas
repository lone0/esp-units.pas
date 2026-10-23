{ webtbs provenance: trunk tests/webtbs/tw17957.pas }

{$mode objfpc}
uses idfheap, fgl;

type
  TFoo1 = class(TObject);

  TFoo2 = class
    type
      TFooList = specialize TFPGList<TFoo1>;
  end;

begin
end.
