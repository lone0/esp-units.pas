# board_facade_mosaico — Mosaico policy via `board_mosaico`

Demonstrates the **thin board pack** pattern:

* generic `boarddisplay` stays chip-agnostic
* `board_mosaico.MosaicoDisplayConfig` supplies `psram_dma_direct` + 80 MHz
* optional `MosaicoSetBrightness` owns the CO5300 vendor register

Pair with `../board-facade-generic/` (BMGR defaults, no pack).

For LVGL apps set `cfg.Panel := MosaicoDisplayConfig` on a
`TBoardLvglConfig` — see `../display-native/`.

## Build / run (esp32sim)

Same prerequisites as `../board-facade-generic/` (`lvgl-mosaico-s31`,
64KB MMU elf2image, merge-bin @ `0xA000`).

```sh
cd examples/board-facade-mosaico
ESP_FPC_ROOT=$HOME/fpc-cross-s31 \
ESP_IDF_PATH=$HOME/esp/esp-idf-v6.1 ESP_IDF_VERSION=6.1 \
ESP32_SDK_PROJECT=$HOME/lvgl-mosaico-s31 \
../../scripts/build.sh board_facade_mosaico.pas --soc esp32s31 \
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
  -o board_facade_mosaico.bin board_facade_mosaico.elf

esptool --chip esp32s31 merge-bin -o board_facade_mosaico.flash.bin \
  --flash-mode qio --flash-freq 80m --flash-size 16MB \
  0x2000 $HOME/lvgl-mosaico-s31/build/bootloader/bootloader.bin \
  0xa000 $HOME/lvgl-mosaico-s31/build/partition_table/partition-table.bin \
  0x10000 board_facade_mosaico.bin

esp32sim-s31 --board mosaico --boot rom --console uart0 \
  --rom $ESP32SIM_ROM_DIR/esp32s31_rev0_rom.elf \
  --flash-image board_facade_mosaico.flash.bin \
  --elf board_facade_mosaico.elf \
  --max-seconds 12 --tft-png panel-mosaico.png
```

Success: console `demo: ui up (mosaico pack)` / `demo: done`, emu
`CO5300 2 RAMWR, 460800 pixels`, PNG shows RGB bars + crosshair.
