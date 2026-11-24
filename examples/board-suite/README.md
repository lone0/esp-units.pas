# board_suite — one Pascal smoke, three IDF profiles

See [`../../sdk/PROFILES.md`](../../sdk/PROFILES.md).

## Mosaico (sim or real HW)

```sh
cd examples/board-suite
# sim profile:
export ESP32_SDK_PROJECT=$HOME/lvgl-mosaico-s31
# or real HW profile:
# export ESP32_SDK_PROJECT=$HOME/mosaico-s31

ESP_FPC_ROOT=$HOME/fpc-cross-s31 \
ESP_IDF_PATH=$HOME/esp/esp-idf-v6.1 ESP_IDF_VERSION=6.1 \
../../scripts/build.sh board_suite.pas --soc esp32s31 \
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
```

esp32sim (ptable `0xA000` on lvgl tree):

```sh
esptool --chip esp32s31 elf2image \
  --flash-mode qio --flash-freq 80m --flash-size 16MB \
  --flash-mmu-page-size 64KB -o board_suite.bin board_suite.elf
esptool --chip esp32s31 merge-bin -o board_suite.flash.bin \
  --flash-mode qio --flash-freq 80m --flash-size 16MB \
  0x2000 $HOME/lvgl-mosaico-s31/build/bootloader/bootloader.bin \
  0xa000 $HOME/lvgl-mosaico-s31/build/partition_table/partition-table.bin \
  0x10000 board_suite.bin
esp32sim-s31 --board mosaico --boot rom --console uart0 \
  --rom $ESP32SIM_ROM_DIR/esp32s31_rev0_rom.elf \
  --flash-image board_suite.flash.bin --elf board_suite.elf \
  --max-seconds 12 --tft-png panel.png
```

## Generic S31

```sh
export ESP32_SDK_PROJECT=$HOME/idf-build-s31
ESP_FPC_ROOT=$HOME/fpc-cross-s31 \
ESP_IDF_PATH=$HOME/esp/esp-idf-v6.1 ESP_IDF_VERSION=6.1 \
../../scripts/build.sh board_suite_generic.pas --soc esp32s31
```
