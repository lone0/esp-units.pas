# IDF SDK profiles (same Pascal units)

**Agent rule (also `AGENTS.md` §3.9):** hardware configuration belongs in
the IDF build’s BMGR board YAML (`board_devices.yaml` / peripherals /
amend) → `gen_bmgr_codes`, **not** embedded in Pascal L2 units. Pascal
stays hardware-agnostic above FreeRTOS / ESP-IDF; apps may supply only
what BMGR cannot model.

Three ESP-IDF project trees (already on this machine) back the same
`units/` sources. Switch only `ESP32_SDK_PROJECT` (and the mosaico lib
list vs the generic hello list).

| Profile | Path | Board / quirks | Smoke with |
|---------|------|----------------|------------|
| **esp32sim mosaico** | `$HOME/lvgl-mosaico-s31` | `esp_mosaico`; `MOSAICO_VCC_RAMP_MS=0` (GPIO VCC); ptable `0xA000`; SPI 80 MHz + `psram_dma_direct` in yaml | `examples/landscape/` or `examples/display-native/` |
| **real mosaico** | `$HOME/mosaico-s31` | same yaml SPI policy; `MOSAICO_VCC_RAMP_MS=100` (LEDC ramp); ptable `0x8000` | same examples on hardware |
| **generic S31** | `$HOME/idf-build-s31` | hello_world, no BMGR panel | `examples/idfheap-smoke.pas` (or any non-panel program) |

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

- `TBoardDisplay.Start` / `TBoardLvgl.Start` = yaml-as-is.
- Optional app-owned `TBoardDisplay.OverrideConfig` before `Start` (facade
  does not invent SPI fields).
- `board_mosaico` = CO5300 brightness helper only (optional).
- Do **not** put SPI policy back into Pascal L2.

## What to smoke where

| Profile | Smoke here | Needs |
|---------|------------|--------|
| esp32sim mosaico | esp32sim `--board mosaico` | This VM; see `examples/landscape/README.md` |
| real mosaico | flash ESP-Mosaico | Real hardware |
| generic S31 | QEMU/esp-emu or flash | Optional; no panel |
