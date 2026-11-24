{ board_suite — one Pascal panel smoke for every Mosaico IDF build.

  Same source against:
    - esp32sim mosaico  (ESP32_SDK_PROJECT=$HOME/lvgl-mosaico-s31, VCC_RAMP_MS=0)
    - real mosaico      (ESP32_SDK_PROJECT=$HOME/mosaico-s31, VCC_RAMP_MS=100)

  Hardware policy is entirely in BMGR yaml / gen_bmgr_codes. This program
  only calls TBoardDisplay.Start (DefaultConfig = yaml-as-is). Display
  units are not forked per board.

  Generic S31 (no BMGR panel): build board_suite_generic.pas against
  $HOME/idf-build-s31 — same idfheap-first shape, no boarddisplay.

  Build / pack / run recipes: README.md and ../../sdk/PROFILES.md. }

program board_suite;

{$mode objfpc}{$H+}

uses
  idfheap,
  c_bmgr,
  c_esp_lcd,
  boarddisplay;

const
  W = 480;
  H = 480;
  TAG = 'board_suite';

procedure vTaskDelay(ticks: cuint32); cdecl; external;
procedure esp_rom_printf(fmt: PChar); cdecl; external;

function be_rgb565(r, g, b: integer): word;
var
  c: word;
begin
  c := word(((r shr 3) shl 11) or ((g shr 2) shl 5) or (b shr 3));
  Result := word((c shl 8) or (c shr 8));
end;

procedure paint_bars(buf: PWord);
var
  x, y: integer;
  c: word;
begin
  for y := 0 to H - 1 do
    for x := 0 to W - 1 do
    begin
      case x div 80 of
        0: c := be_rgb565(220, 40, 40);
        1: c := be_rgb565(40, 200, 40);
        2: c := be_rgb565(40, 80, 220);
        3: c := be_rgb565(220, 200, 40);
        4: c := be_rgb565(220, 40, 200);
      else
        c := be_rgb565(40, 200, 220);
      end;
      if (x = W div 2) or (y = H div 2) then
        c := be_rgb565(255, 255, 255);
      if ((x < 24) and (y < 24)) or ((x >= W - 24) and (y >= H - 24)) then
        c := be_rgb565(255, 255, 0);
      buf[y * W + x] := c;
    end;
end;

var
  ret: esp_err_t;
  panel: esp_lcd_panel_handle_t;
  fb: PWord;
  i: integer;
begin
  ret := TBoardDisplay.Start;
  if ret <> ESP_OK then
    halt;
  panel := TBoardDisplay.Panel;
  if panel = nil then
    halt;

  GetMem(fb, SizeOf(word) * W * H);
  if fb = nil then
    halt;

  paint_bars(fb);
  ret := esp_lcd_panel_draw_bitmap(panel, 0, 0, W, H, fb);
  if ret <> ESP_OK then
    halt;
  ret := esp_lcd_panel_draw_bitmap(panel, 0, 0, W, H, fb);

  esp_rom_printf('demo: board_suite ui up'#10);
  writeln(TAG, ': I yaml-as-is panel ready');

  for i := 1 to 20 do
    vTaskDelay(10);

  esp_rom_printf('demo: done'#10);
  halt;
end.
