{ board_facade_generic — show the board-agnostic L2 panel path.

  Uses TBoardDisplay.Start (DefaultConfig = BMGR-as-generated, no SPI
  overrides, no chip {$linklib} in the unit). Chip drivers still come
  from the app --lib / SDK yaml, same as display_lvgl / mosaico_sim.

  Contrast: examples/board-facade-mosaico/ opts into Mosaico panel
  policy via board_mosaico.MosaicoDisplayConfig.

  Build (from this directory; same link closure as mosaico_sim):

    ESP_FPC_ROOT=$HOME/fpc-cross-s31 \
    ESP_IDF_PATH=$HOME/esp/esp-idf-v6.1 ESP_IDF_VERSION=6.1 \
    ESP32_SDK_PROJECT=$HOME/mosaico-s31 \
    ../../scripts/build.sh board_facade_generic.pas --soc esp32s31 \
      --lib espressif__esp_board_manager --lib gen_bmgr_codes \
      --lib esp_lcd --lib espressif__esp_lcd_co5300 \
      --lib espressif__esp_lcd_touch_cst9220 --lib espressif__esp_lcd_touch \
      --lib espressif__esp_codec_dev --lib espressif__i2c_bus \
      --lib espressif__button --lib espressif__bq27220 \
      --lib espressif__esp_video --lib espressif__esp_cam_sensor \
      --lib espressif__esp_sccb_intf --lib esp_driver_cam --lib esp_driver_ppa \
      --lib esp_hal_cam \
      --lib $HOME/mosaico-s31/managed_components/espressif__bmi270_sensor/6.1/esp32s31/libbmi270_sensor.a \
      --lib esp_driver_gpio --lib esp_driver_spi \
      --lib esp_driver_i2c --lib esp_driver_i2s --lib esp_driver_ledc \
      --lib esp_hal_ledc --lib esp_hal_gpio --lib esp_hal_lcd \
      --lib esp_hal_i2c --lib esp_hal_i2s --lib esp_timer --lib esp_partition \
      --lib log --lib vfs --lib esp_system

  Re-pack + run under esp32sim: see README.md (64KB MMU, VCC ramp bypass). }

program board_facade_generic;

{$mode objfpc}{$H+}

uses
  idfheap,
  c_bmgr,
  c_esp_lcd,
  boarddisplay;

const
  W = 480;
  H = 480;
  TAG = 'facade_generic';

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
  { First bring-up via boarddisplay with DefaultConfig (BMGR-as-generated,
    no SPI overrides). App --lib supplies CO5300 / transport archives. }
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

  esp_rom_printf('demo: ui up (BMGR defaults)'#10);
  writeln(TAG, ': I panel ready via TBoardDisplay.Start / DefaultConfig');

  for i := 1 to 20 do
    vTaskDelay(10);

  esp_rom_printf('demo: done'#10);
  halt;
end.
