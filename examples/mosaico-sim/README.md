# mosaico_sim — Pascal panel smoke for ESP-Mosaico / esp32sim

Brings up the board via BMGR, grabs the CO5300 panel handle from the first
`display_lcd` init (no `boarddisplay` re-init — that deinit→override→re-init
path hangs under esp32sim), paints RGB bars + a white crosshair + yellow
corners, prints `demo:` on UART0, then halts.

Target: [`esp32sim`](https://github.com/mikroverk/esp32sim) v0.4+ with
`--board mosaico`.

## Prerequisites

1. FPC cross for esp32s31 (`ESP_FPC_ROOT`), IDF 6.1.x, and a built mosaico
   SDK tree (`ESP32_SDK_PROJECT`, e.g. `$HOME/mosaico-s31`).
2. In that tree, `esp_mosaico/board_runtime.c` must drive VCC with a plain
   GPIO when `MOSAICO_VCC_RAMP_MS=0` (LEDC fade wait never completes in the
   simulator). Rebuild the SDK after changing it so `gen_bmgr_codes` picks
   up the object.

## Build

```sh
cd examples/mosaico-sim
ESP_FPC_ROOT=$HOME/fpc-cross-s31 \
ESP_IDF_PATH=$HOME/esp/esp-idf-v6.1 ESP_IDF_VERSION=6.1 \
ESP32_SDK_PROJECT=$HOME/mosaico-s31 \
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
```

Re-pack the app image with a 64KB MMU page size (FPC’s default `elf2image`
can leave the second IROM segment mis-aligned so the bootloader rejects it):

```sh
esptool --chip esp32s31 elf2image \
  --flash-mode qio --flash-freq 80m --flash-size 16MB \
  --flash-mmu-page-size 64KB \
  -o mosaico_sim.bin mosaico_sim.elf
```

## Run (esp32sim)

```sh
esp32sim-s31 --board mosaico --boot rom --console uart0 \
  --rom $ESP32SIM_ROM_DIR/esp32s31_rev0_rom.elf \
  --bootloader $HOME/mosaico-s31/build/bootloader/bootloader.bin \
  --ptable $HOME/mosaico-s31/build/partition_table/partition-table.bin \
  --app mosaico_sim.bin --elf mosaico_sim.elf \
  --max-seconds 12 --tft-png panel.png
```

Success looks like `demo: ui up` / `demo: done` on the console and emu
stats with `CO5300` `RAMWR` / non-zero pixels, `power on`. The PNG should
show six color bars, a white crosshair, and yellow corner markers.
