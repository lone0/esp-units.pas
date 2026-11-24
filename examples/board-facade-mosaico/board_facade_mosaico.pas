{ board_facade_mosaico — yaml-as-is panel + optional CO5300 brightness.

  SPI policy (80 MHz, psram_dma_direct) lives in esp_mosaico
  board_devices.yaml / gen_bmgr_codes. This demo only shows the leftover
  vendor helper in board_mosaico (brightness). Pair with
  board-facade-generic (same Start path, no brightness call).

  Build / run: see README.md (lvgl-mosaico-s31, 64KB MMU, merge-bin @ 0xA000). }

program board_facade_mosaico;

{$mode objfpc}{$H+}

uses
  idfheap,
  c_bmgr,
  c_esp_lcd,
  boarddisplay,
  board_mosaico;

const
  W = 480;
  H = 480;
  TAG = 'facade_mosaico';
  BRIGHTNESS = 60;

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

  if MosaicoSetBrightness(panel, BRIGHTNESS) <> ESP_OK then
    writeln(TAG, ': W set_brightness failed (driver default)');

  GetMem(fb, SizeOf(word) * W * H);
  if fb = nil then
    halt;

  paint_bars(fb);
  ret := esp_lcd_panel_draw_bitmap(panel, 0, 0, W, H, fb);
  if ret <> ESP_OK then
    halt;
  ret := esp_lcd_panel_draw_bitmap(panel, 0, 0, W, H, fb);

  esp_rom_printf('demo: ui up (yaml + brightness)'#10);
  writeln(TAG, ': I panel ready via TBoardDisplay.Start + MosaicoSetBrightness');

  for i := 1 to 20 do
    vTaskDelay(10);

  esp_rom_printf('demo: done'#10);
  halt;
end.
