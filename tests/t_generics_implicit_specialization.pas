{ webtbs provenance: trunk tests/webtbs/tw39680.pas }

{ %NORUN }

program t_generics_implicit_specialization;

{$mode objfpc}{$H+}
{$ModeSwitch implicitfunctionspecialization}

uses
  idfheap, // IDF-pool manager (opt-out from the static heap)
  
  Generics.Collections;

generic procedure Foo<T>(lst: specialize TEnumerable<T>);
begin
end;

var
  lst: specialize TList<Integer>; // Inherits from TEnumerable
begin
  Foo(lst); // Error
  specialize Foo<Integer>(lst); // works
end.

