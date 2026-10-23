{ webtbs provenance: trunk tests/webtbs/tw33898.pas }

{ %NORUN }

program t_stringhelper_join;

{$mode delphi}

uses idfheap, sysutils;

begin
  writeln(string.join('&', ['ab', 'cd']));
end.
