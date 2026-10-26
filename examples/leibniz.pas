program leibniz;
{ Origin: https://github.com/niklas-heer/speed-comparison/blob/master/src/leibniz.pas }
{ Computes Pi using the Leibniz series }

uses
  idfheap, TypInfo;

{ Microseconds since boot, monotonic — IDF's own timer. Declared here so the
  example needs no extra unit; esp_timer is already in the RTL's link list. }
function esp_timer_get_time: int64; cdecl; external name 'esp_timer_get_time';

var
  rounds, i: longint;
  pi, x: single; {double;}
  t0, t1: int64;

begin
  rounds := 1000000;
  pi := 1.0;
  x := 1.0;
  t0 := esp_timer_get_time;
  for i := 2 to rounds + 1 do
  begin
    x := x * -1;
    pi := pi + x / (2 * i - 1);
  end;
  t1 := esp_timer_get_time;

  pi := pi * 4;
  WriteLn('Leibniz Pi of type ' + PTypeInfo(TypeInfo(pi))^.Name);
  writeln(pi);
  writeln('rounds: ', rounds);
  writeln('loop: ', t1 - t0, ' us = ', (t1 - t0) / 1000:0:3, ' ms');
end.
