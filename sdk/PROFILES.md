# IDF SDK profiles for one Pascal suite

Zhen’s rule: **hardware in YAML; Pascal stays hardware-independent.**

Three ESP-IDF project trees (already on this machine) back the same
`units/` sources. Switch only `ESP32_SDK_PROJECT` (and the mosaico lib
list vs the generic hello list).

| Profile | Path | Board / quirks | Pascal entry |
|---------|------|----------------|--------------|
| **esp32sim mosaico** | `$HOME/lvgl-mosaico-s31` | `esp_mosaico`; `MOSAICO_VCC_RAMP_MS=0` (GPIO VCC); ptable `0xA000`; SPI 80 MHz + `psram_dma_direct` in yaml | `examples/board-suite/board_suite.pas` |
| **real mosaico** | `$HOME/mosaico-s31` | same yaml SPI policy; `MOSAICO_VCC_RAMP_MS=100` (LEDC ramp); ptable `0x8000` | same `board_suite.pas` |
| **generic S31** | `$HOME/idf-build-s31` | hello_world, no BMGR panel | `examples/board-suite/board_suite_generic.pas` |

## Yaml SPI policy (both mosaico trees)

In `managed_components/espressif__esp_boards/esp_mosaico/board_devices.yaml`
under `display_lcd` → `io_spi_config`:

```yaml
pclk_hz: 80000000
flags:
  quad_mode: true
  psram_dma_direct: true
```

After editing yaml, regenerate then rebuild:

```sh
. $HOME/esp/esp-idf-v6.1/export.sh
cd $ESP32_SDK_PROJECT
python3 managed_components/espressif__esp_board_manager/gen_bmgr_config_codes.py \
  -b esp_mosaico --project-dir "$PWD"
idf.py build
```

Confirm `components/gen_bmgr_codes/gen_board_device_config.c` shows
`.pclk_hz = 80000000` and `.psram_dma_direct = true`.

## Pascal

- `TBoardDisplay.Start` / `TBoardLvgl.Start` = yaml-as-is (`DefaultConfig`).
- `board_mosaico` = CO5300 brightness helper only (optional).
- Do **not** put SPI policy back into Pascal L2.

## What to smoke where

| Profile | Smoke here | Needs |
|---------|------------|--------|
| esp32sim mosaico | esp32sim `--board mosaico` | This VM (see board-suite README) |
| real mosaico | flash ESP-Mosaico | Real hardware |
| generic S31 | QEMU/esp-emu or flash | Optional; no panel |
