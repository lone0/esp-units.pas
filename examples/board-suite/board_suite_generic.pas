{ board_suite_generic — same suite entry for Generic S31 (no BMGR panel).

  Links against ESP32_SDK_PROJECT=$HOME/idf-build-s31 (hello_world tree).
  Does not use boarddisplay / boardlvgl — those units stay mosaico/BMGR
  only; this file proves one repo can target a third IDF build without
  forking the display facades.

  Build: see README.md. }

program board_suite_generic;

{$mode objfpc}{$H+}

uses
  idfheap,
  ctypes;

procedure vTaskDelay(ticks: cuint32); cdecl; external;
procedure esp_rom_printf(fmt: PChar); cdecl; external;

var
  i: integer;
begin
  esp_rom_printf('demo: board_suite_generic up'#10);
  writeln('board_suite_generic: I idfheap ok on generic S31');
  for i := 1 to 10 do
    vTaskDelay(10);
  esp_rom_printf('demo: done'#10);
  halt;
end.
