{ mosaico_sim — minimal Pascal panel demo for ESP-Mosaico under esp32sim.
  Uses BMGR's first-time display_lcd bring-up (no boarddisplay re-init:
  the deinit→override→re-init path hangs under esp32sim after VCC).
  Paints RGB bars + crosshair, prints demo: on UART0, then halts.

  Build (from this directory):
    ESP_FPC_ROOT=$HOME/fpc-cross-s31 ESP_IDF_PATH=$HOME/esp/esp-idf-v6.1 \
    ESP_IDF_VERSION=6.1 ESP32_SDK_PROJECT=$HOME/mosaico-s31 \
    ../../scripts/build.sh mosaico_sim.pas --soc esp32s31 \
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

  Re-pack with 64KB MMU pages (required for boot):
    esptool --chip esp32s31 elf2image --flash-mode qio --flash-freq 80m \
      --flash-size 16MB --flash-mmu-page-size 64KB \
      -o mosaico_sim.bin mosaico_sim.elf

  Run under esp32sim (needs mosaico board_runtime with MOSAICO_VCC_RAMP_MS=0):
    esp32sim-s31 --board mosaico --boot rom --console uart0 \
      --bootloader $HOME/mosaico-s31/build/bootloader/bootloader.bin \
      --ptable $HOME/mosaico-s31/build/partition_table/partition-table.bin \
      --app mosaico_sim.bin --elf mosaico_sim.elf \
      --max-seconds 12 --tft-png panel.png
}

program mosaico_sim;

{$mode objfpc}{$H+}

uses
  idfheap,
  c_bmgr,
  c_esp_lcd;

const
  W = 480;
  H = 480;

function gpio_set_level(gpio_num: cint; level: cuint32): esp_err_t; cdecl; external;
procedure vTaskDelay(ticks: cuint32); cdecl; external;
procedure esp_rom_printf(fmt: PChar); cdecl; external;

type
  TPeriphGpioHandle = record
    gpio_num: cint;
  end;
  PPeriphGpioHandle = ^TPeriphGpioHandle;

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
  motorh, lcdh: pointer;
  lcd_handles: Pdev_display_lcd_handles_t;
  fb: PWord;
  i: integer;
begin
  ret := esp_board_manager_init;
  if ret <> ESP_OK then
    halt;

  motorh := nil;
  if (esp_board_manager_get_device_handle('vibration_motor', @motorh) = ESP_OK)
     and (motorh <> nil) then
    gpio_set_level(PPeriphGpioHandle(motorh)^.gpio_num, 0);

  lcdh := nil;
  ret := esp_board_manager_get_device_handle(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD, @lcdh);
  if (ret <> ESP_OK) or (lcdh = nil) then
    halt;
  lcd_handles := Pdev_display_lcd_handles_t(lcdh);
  panel := lcd_handles^.panel_handle;
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

  esp_rom_printf('demo: ui up'#10);

  for i := 1 to 20 do
    vTaskDelay(10);

  esp_rom_printf('demo: done'#10);
  halt;
end.
