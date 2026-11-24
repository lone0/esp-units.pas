# board_facade_generic — BMGR defaults via generic `boarddisplay`

Demonstrates the **board-agnostic** L2 panel path:

* `TBoardDisplay.Start` → `DefaultConfig` (no `psram_dma_direct`, no pclk
  override)
* no chip `{$linklib}` inside `boarddisplay` — CO5300 / CST9220 come from
  the app `--lib` line / SDK yaml

Pair with `../board-facade-mosaico/` to see the thin board-pack alternative.

## Build / run (esp32sim)

Prerequisites: FPC cross for esp32s31, IDF 6.1.x, built
`lvgl-mosaico-s31` (ptable @ `0xA000`, `MOSAICO_VCC_RAMP_MS=0`).

```sh
cd examples/board-facade-generic
ESP_FPC_ROOT=$HOME/fpc-cross-s31 \
ESP_IDF_PATH=$HOME/esp/esp-idf-v6.1 ESP_IDF_VERSION=6.1 \
ESP32_SDK_PROJECT=$HOME/lvgl-mosaico-s31 \
../../scripts/build.sh board_facade_generic.pas --soc esp32s31 \
  --lib espressif__esp_board_manager --lib gen_bmgr_codes \
  --lib esp_lcd --lib espressif__esp_lcd_co5300 \
  --lib espressif__esp_lcd_touch_cst9220 --lib espressif__esp_lcd_touch \
  --lib espressif__esp_codec_dev --lib espressif__i2c_bus \
  --lib espressif__button --lib espressif__bq27220 \
  --lib espressif__esp_video --lib espressif__esp_cam_sensor \
  --lib espressif__esp_sccb_intf --lib esp_driver_cam --lib esp_driver_ppa \
  --lib esp_hal_cam \
  --lib esp_driver_gpio --lib esp_driver_spi \
  --lib esp_driver_i2c --lib esp_driver_i2s --lib esp_driver_ledc \
  --lib esp_hal_ledc --lib esp_hal_gpio --lib esp_hal_lcd \
  --lib esp_hal_i2c --lib esp_hal_i2s --lib esp_timer --lib esp_partition \
  --lib log --lib vfs --lib esp_system

esptool --chip esp32s31 elf2image \
  --flash-mode qio --flash-freq 80m --flash-size 16MB \
  --flash-mmu-page-size 64KB \
  -o board_facade_generic.bin board_facade_generic.elf

esptool --chip esp32s31 merge-bin -o board_facade_generic.flash.bin \
  --flash-mode qio --flash-freq 80m --flash-size 16MB \
  0x2000 $HOME/lvgl-mosaico-s31/build/bootloader/bootloader.bin \
  0xa000 $HOME/lvgl-mosaico-s31/build/partition_table/partition-table.bin \
  0x10000 board_facade_generic.bin

esp32sim-s31 --board mosaico --boot rom --console uart0 \
  --rom $ESP32SIM_ROM_DIR/esp32s31_rev0_rom.elf \
  --flash-image board_facade_generic.flash.bin \
  --elf board_facade_generic.elf \
  --max-seconds 12 --tft-png panel-generic.png
```

Success: console `demo: ui up (BMGR defaults)` / `demo: done`, emu
`CO5300 2 RAMWR, 460800 pixels`, PNG shows RGB bars + crosshair.
