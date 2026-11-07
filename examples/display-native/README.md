display_native — Pascal-native display chain demo (boarddisplay facade + c_lvgl subset)

The "use → one Start → build UI" shape:

* the **boarddisplay** facade (units/, L2): `uses boarddisplay` lazily
  initializes the three display-chain devices (display_lcd, lcd_touch,
  lcd_brightness) in the unit initialization; `TBoardDisplay.Start` brings
  the esp_lvgl_adapter up, registers display + touch and starts the worker;
  afterwards `lv_screen_active()` is live and Pascal builds UI over the
  **c_lvgl** subset (units/, L1) under `TBoardDisplay.UILock/UIUnlock`.
* no C sources are linked (`--c` is absent) — unlike bmgr-lvgl, where the
  untouched C `lvgl_test_ui.c` does the LVGL work. Every element here is
  created from Pascal.
* the red button is the **packed-lv_color_t ABI probe**: lv_color_t is a
  3×uint8 C struct passed by value (psABI-bitified into one register, see
  units/c_lvgl.pas). If the button is not pure red (255, 0, 0), the packing
  is wrong and the style setters need a tiny C shim instead.
* the event callback runs in the adapter worker task and locks around its
  own LVGL calls — the lvgl_test_ui.c `ui_acquire`/`ui_release` pattern.

Build (build-only verification; flash the Mosaico by hand):

```sh
cd examples/display-native
ESP_FPC_ROOT=/mnt/storage/fpc-cross \
ESP32_SDK_PROJECT=/mnt/storage/fpc-esp/lvgl-s31 \
../../scripts/build.sh display_native.pas --soc esp32s31 \
    --lib espressif__esp_board_manager --lib gen_bmgr_codes \
    --lib lvgl__lvgl --lib espressif__esp_lvgl_adapter \
    --lib espressif__esp_lcd_co5300 --lib waveshare__esp_lcd_touch_cst9217 \
    --lib esp_pm --lib esp_lcd --lib esp_driver_ppa --lib espressif__esp_lcd_touch \
    --lib espressif__esp_codec_dev --lib espressif__i2c_bus --lib espressif__button \
    --lib espressif__knob --lib espressif__bq27220 --lib espressif__esp_cam_sensor \
    --lib espressif__esp_video --lib espressif__esp_sccb_intf --lib espressif__usb \
    --lib espressif__usb_host_uac --lib espressif__usb_host_uvc --lib fatfs \
    --lib wear_levelling --lib spiffs --lib espressif__esp_mmap_assets \
    --lib /mnt/storage/fpc-esp/lvgl-s31/managed_components/espressif__esp_new_jpeg/lib/esp32s31/libesp_new_jpeg.a \
    --lib /mnt/storage/fpc-esp/lvgl-s31/build/esp-idf/espressif__esp_lv_decoder/liblvgl_docoder_lib.a \
    --lib espressif__esp_lv_fs \
    --lib /mnt/storage/fpc-esp/lvgl-s31/build/esp-idf/espressif__freetype/output/libfreetype.a \
    --lib espressif__libpng --lib espressif__zlib --lib espressif__qoi \
    --lib esp_driver_i2c --lib esp_driver_i2s --lib esp_driver_gpio --lib esp_driver_spi \
    --lib esp_hal_gpio --lib esp_hal_lcd --lib esp_timer --lib esp_partition \
    --lib esp_hal_i2c --lib esp_hal_i2s --lib esp_hal_cam --lib esp_hal_ppa \
    --lib esp_hal_ledc --lib esp_driver_cam --lib esp_driver_ledc \
    --lib log --lib vfs --lib esp_system
```

Why the `--lib` set is identical to bmgr-lvgl's: `espressif__esp_board_manager`
and `gen_bmgr_codes` are whole-archived (the registry factory tables live in
data symbols no object pulls by reference), and the generated device-handle
tables reference the init functions of every device the board yaml names —
so the registry pulls the whole driver family regardless of which devices
this program actually touches. The one difference vs bmgr-lvgl: no `--c`
(this program links no C sources) and the two snapshot .a paths stay as-is.

Configurable start (the facade's value-semantics config record; defaults =
the verified bmgr-lvgl behavior):

```pascal
var
  cfg: TBoardDisplayConfig;
begin
  cfg := TBoardDisplay.DefaultConfig;
  cfg.TaskPriority := 5;
  cfg.Rotation     := ESP_LV_ADAPTER_ROTATE_180;
  ret := TBoardDisplay.StartEx(cfg);
```

Out of the L2 config by design (need them → drop to the L1
c_lvgl_adapter API): auto-sleep/touch callback hooks, TE-sync and mono
display profiles, the full-board `esp_board_manager_init()`.

Verified — **on hardware** (2026-11-07, ESP-Mosaico):

1. `scripts/build.sh … exit 0`, `display_native.elf/.bin` written.
2. `nm` on the ELF: `lv_screen_active`, `lv_font_montserrat_*`, the
   adapter/bmgr API and the facade's three device inits all resolve;
   `__wrap_app_main` → `PASCALMAIN` → `ESP32S31_$$_APP_MAIN` chain intact.
3. Console: `TBoardDisplay.Start` success path + 1 Hz heartbeats.
4. Screen: Pascal-built label + button render (user-confirmed).
5. Touch: CST9217 → adapter indev → LVGL event → Pascal cdecl callback →
   `button clicked` logged (4×).
6. **Packed-`lv_color_t` ABI probe: user-confirmed pure red (255,0,0)** —
   the psABI bitified by-value passing of the 3×uint8 struct is correct;
   no C shim needed.
7. Font iterations: 14 (default) → 20 → 28 (user asked bigger each time;
   28/36 enabled in the lvgl-s31 sdkconfig via one Kconfig line +
   `idf.py build`, no other SDK change).

Flash notes learned on hardware: the reliable write is `esptool
--no-stub --after hard-reset write-flash 0x0 <tight image>` from either
the ROM-download CDC (303a:0020) or the running app's console
(303a:1001, via its auto-download protocol; the stub path is flaky on
this board). Address ports by `/dev/serial/by-id/` identity
(`...Espressif_Device_123456-if00` = app console,
`...ESP32-S31_1c:29:04:d0:88:24-if00` = ROM download) — the ttyACM*
numbers drift across re-enumerations.
