board_manager — Pascal port of lvgl-s31/main/main.c (esp_board_manager + esp_lvgl_adapter LVGL display example)

This example is the full Pascal/C interopproducer showcase the `esp-units.pas` repo was set up for:

* a hand-converted Pascal binding (`units/c_bmgr.pas`) for the **esp_board_manager** device registry
* a hand-converted Pascal binding (`units/c_lvgl_adapter.pas`) for the **espressif__esp_lvgl_adapter**
* a program (`board_manager.pas`) whose statements mirror `main.c`'s `app_main` one-for-one
* the untouched **C** test UI (`lvgl_test_ui.c/.h`, byte-identical snapshot of
  `/mnt/storage/fpc-esp/lvgl-s31/main/lvgl_test_ui.c`, sha256 a0993c3e56a20fbeafe9c7e25bc86dfb)
  which does the real LVGL work and is linked in via `build.sh --c`

… all running on the **ESP-Mosaico** board (esp32s31) against the already-built C IDF
project at `/mnt/storage/fpc-esp/lvgl-s31`, including its software USB CDC
(usb_hs_console) `--wrap=app_main` console chain.

Build (build-only verification; flash the Mosaico yourself):

```sh
cd examples/bmgr-lvgl
ESP_FPC_ROOT=/mnt/storage/fpc-cross \
ESP32_SDK_PROJECT=/mnt/storage/fpc-esp/lvgl-s31 \
../../scripts/build.sh board_manager.pas --soc esp32s31 \
    --c lvgl_test_ui.c \
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

Why the `--lib` set is what it is — this is the **C-build linkage mirror**:

* `espressif__esp_board_manager` and `gen_bmgr_codes` must be whole-archived
  (`--lib` wraps each in `--whole-archive`), exactly like the C `link.txt`,
  because the registry factory tables live in data symbols no object pulls by
  reference on demand.
* The device registry pulls in every device type the yaml could name —
  codec, camera, button, knob, USB, FS, LVGL decode/FS/freetype/libpng/zlib,
  sensors, PPA, LEDC… — which the C build reaches through the archives
  available to its linker; the Pascal link has to *name* each one (`--lib`),
  plain archives for all of those. Two are non-standard snap-path/directory
  names (`libesp_new_jpeg.a` under managed_components, `libfreetype.a` under
  the freetype build output dir, `liblvgl_docoder_lib.a` — sic, a typo in the
  decoder component's own CMake target), so those pass as full `.a` paths.
* `lvgl__lvgl`/`espressif__esp_lvgl_adapter` are regular archives (like the C
  link: no whole-archive on them).
* `usb_hs_console` + `app_main` `--wrap`: build.sh detects the SDK project's
  `build/esp-idf/usb_hs_console/libusb_hs_console.a` and then automatically
  also whole-archives `espressif__esp_tinyusb`, `espressif__tinyusb`,
  `esp_hal_usb` and emits `-k--wrap=app_main` — that is the software USB CDC
  console chain used on ESP-Mosaico. This is the Mutter-board's Type-C
  console/disconnectable reality; flash-tested on 2026-11-02 in the
  hello-s31-mosaico Pascal build.
* CONFIG_SPIRAM=y detected in the SDK config: build.sh additionally
  whole- archives `esp_psram` (same, below, for the espcoredump archive).

Verified - **build-only** (`flash/ser walk` happens only when the board
is rejuvenated by hand; full build here, verification steps as performed):

1. `scripts/build.sh … exit 0`: `succesfully created ESP32-S31 image`,
   `board_manager.elf/.bin` written.
2. In board_manager.o: every `external` decl from the two units resolves —
   `esp_board_manager_init_device_by_name`, `…get_device_handle`,
   `…get_device_config`, `…deinit_device_by_name`, `esp_lv_adapter_init/start/
   deinit/register_display/register_touch/unregister_display/
   unregister_touch`, and `lvgl_test_start` from the `--c` link.
3. In board_manager.elf:
   * `__wrap_app_main` is the real `usb_console.c` symbol: disassembly shows
     it calling `bsp_usb_console_init()` then tail-jumping to
     `ESP32S31_$$_APP_MAIN` — the FPC RTL `app_main` — whose PASCALMAIN
     resolves to this program's body.
   * the FreeRTOS main-task prologue jal's into `__wrap_app_main` — the
     wrap really is what runs the console init on boot.
   * sc101iot_detect and ov3640_detect are resident `T` symbols (camera
     device factories pulled wholesale through the bmgr registry, same as
     C's `-u` flags do).
   * no png/zlib object ever got pulled (`zcalloc`,
     `__wrap_png_create_png_struct` absent), so no png wrap flags are
     needed — the C link's extra `--wrap=png_create_png_struct … -u
     zcalloc` flags become validation-time no-ops here.

Notes on writing it this way:

* `idfheap` stays the FIRST unit (see `AGENTS.md`), before any other unit
  initialization string work happens.
* `main/lvgl_test_ui.c` is linked first-class from `--c`; the Pascal side
  never touches structurally-heavy LVGL — the adapter's `lv_display_t` /
  `lv_indev_t` are left opaque in the Pascal (`plv_display_t` etc.) which
  the adapter ABI only ever treats as handles.
* The two binding units (now `units/c_bmgr.pas` / `units/c_lvgl_adapter.pas`,
  shared with `../display-native/`) are h2pas-ready source documents for
  precise record layout
  (record offsets were resolved by-hand against the C headers, including
  the esp_lcd_panel_io_spi_config_t = 44 B shape, the union config 108 B
  shape at the `dev_display_lcd_config_t` sub_cfg union and the adapter's
  24 B display profile, 36 B touch config and 52 B adapter config) — with
  the ESP-Mosaico sdkconfig compile-gated truth baked in: SPI sub-type
  only (DSI/RGB/RGB3W/I80/PARLIO compile out at the C source level there),
  CONFIG_SPIRAM=y so main.c's SPI+PSRAM register path is the active one,
  and the adapter's CONFIG_LVGL_ADAPTER_ENABLE_* off (fs/decoder/freetype/
  button/knob/fps surface faithfully trimmed away).
* `strcmp`, `lvgl_test_start`, FreeRTOS glue are `cdecl; external;` — the
  way this repo always wraps C.
