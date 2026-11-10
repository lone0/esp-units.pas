landscape — SWAG 0119.PAS "Landscape" (Marcin Borkowski, 1994-08-24) on the ESP-Mosaico, fidelity port at native panel resolution

The 1994 DOS/VGA voxel-terrain flyover, kept **line-aligned** with the
original with its constants retuned to the panel (parameters only — the
algorithm structure is untouched), driven through esp_lcd — no LVGL, no
adapter, no C glue. Uses two units added for this app (see the repo's
units/README.md for the L1/L2 grammar): `c_bmi270` (L1 binding of
espressif/bmi270_sensor) and `imuattitude` (L2: the two tilt angles off
the accelerometer, with the boot-pose baseline and the orientation
formulas).

## Fidelity architecture

The 1994 code is verbatim in structure (under `{ ==== 94 code }`):
`pal` (384 B), `ncol`, `plasma` (single 128 seed at `$0000`,
`plasma(0,0,256,256)`), the whole `draw()` shape — near-to-far depth
slices, byte-`rng` per-column occlusion, fixed-point cos/sin ×256,
pinhole projection, sea-level clamp, span fill — and the main sequence
(`randomize` → terrain → mode+palette → `repeat dir mod 360; draw;
<input> until false`).

Everything the ESP world forces on us lives in one display-adapter
section and is called where the original had its DOS counterparts:

| 94 original | this port |
|---|---|
| `uses crt` | `uses idfheap, c_bmgr, c_esp_lcd, Math` |
| `readkey;` (before terrain gen) | `esp_init;` — BMGR bring-up, motor off, own DMA-direct panel-io + CO5300 panel, TE line, double frame buffer |
| `asm int10 $13 end;` | `vga_setmode;` — clear panel buffers |
| `port[$3C8]/[$3C9]` palette load | `vga_setmode;` — pal → 128-entry BE RGB565 LUT |
| `draw(): …; move(scr^,A000:0,64000)` | `draw(): …; vga_flush` |
| `case readkey of #75/#77/#72/#80` | `dir+ctrl_dturn; y+ctrl_dy; x+ctrl_dx` — the "keys" are three integers the background ctrl task publishes (BMI270 tilt steering: lean = the #75/#77 turns, flat/vertical = the #72/#80 fwd/back; wander simulation when the sensor is absent). All float math and the I2C read live in that task; the frame loop is integer-only |

Complete deviation list from verbatim (also in the file header):

1. `uses crt` → the ESP units; console = the board's USB CDC.
2. `mp` sits in a padded 120 KiB block (`MAP_LOW/MAP_BLOCK`): plasma
   writes up to `256*256+256` and draw samples `256*iyp+ixp` with
   `iyp/ixp` in [-110, 365] — on DOS harmless adjacent-RAM accesses,
   here kept inside our own allocation so the code needs no edits. The
   pad is zeroed = the fresh-heap zeros DOS handed back.
3. `scr` retyped: was one 64000-byte palette-index buffer; now a
   pointer into the 480×480 BE-RGB565 **double panel buffer**
   (`frame[0]/[1]` in PSRAM, flipped by `vga_flush`), painted through
   the LUT at paint time — the DAC's index-to-RGB job happens where the
   index byte was stored. `rng` grew to `word[0..481]` (480 columns +
   the 480 sentinel exceeds a byte).
4. The readkey steering branch consumes `ctrl_dturn/dx/dy` — three
   integers the background **ctrl task** recomputes every 333 ms from
   the BMI270's gravity vector (lean = the 94 #75/#77 turns,
   proportional, capped at 10°/frame; flat = #72 forward, vertical =
   #80 backward, dead zone = hover) or, sensor absent, from a wander
   simulation. All float math and the I2C read live in that task; the
   frame loop is integer-only and oblivious. Movement lags a turn by
   up to one sample period (slight sideslip while banking).
5. fps/TE diagnostics live in `vga_flush` (adapter side).

## Native-resolution parameter mapping (draw's inline constants)

Each constant is the 94 value times the resolution ratio; FOCAL_Y
additionally carries the mode-13h pixel aspect so the square panel
reproduces what a 4:3 CRT actually showed (world anisotropy 10:1):

| 94 | native 480×480 | derivation |
|---|---|---|
| 320 / 64000 | 480 / 480×480×2 | panel width, 16 bpp surface |
| 160 / 100 | 240 / 240 | center / horizon |
| 360 | 540 | 360 × 1.5 |
| 30 | **54** | 30 × 1.5 × 1.2 (resolution × mode-13h pixel aspect) |
| 318 | 478 | 480 − 2 clip |
| 300 (span fill) | 450 | × 1.5 |
| rng sentinel 200 | 480 | byte → word |

Vertical-exaggeration knob: FOCAL_Y alone (54 = what the 94 player saw
on a CRT; 45 = the naive ×1.5 scale, more squashed; larger = taller
mountains). One line.

## Tilt steering (the arrow keys' replacement)

Mosaico has no keys but has a BMI270 on I2C (0x69, SDO high). The
C-side gesture demo (`mosaico-s31/main/imu_gesture.c`) classifies
discrete shake/tilt/flip events (1.2 s cooldown, no direction) — fine
for notifications, useless for steering. This app binds the same
component's driver API (`espressif__bmi270_sensor`, precompiled
`6.1/esp32s31/libbmi270_sensor.a` linked by full path) and reads the
accelerometer's gravity vector once per frame:

- **lean** `atan2(ax, az)` → the 94 #75/#77 turns, proportional to the
  lean angle, capped at the original's 10°/frame (dead zone 12°, full
  at 45°);
- **tilt** `atan2(√(ax²+ay²), az)` → 0° flat = #72 forward, >55°
  vertical = #80 backward, 25–55° dead zone = hover (the original moved
  only on keypress);
- homing always guards the map edge; no IMU → autopilot wander.

Same measurement config as the official BSP defaults (±4G, 100 Hz,
avg4 — the thresholds are tuned against that range; don't change it).
The sensor comes up on the BMGR `i2c_master` bus handle, exactly like
imu_gesture.c. Constants live in the adapter section (`ROLL_DEAD`,
`ROLL_FULL`, `PITCH_FWD`, `PITCH_BACK`, `LEAN_SIGN`). LEAN_SIGN = -1 on
this mounting, chosen so lean-LEFT acts as the 94 #75 (turn left).
Note the visual: a first-person turn-left makes the scene content slide
RIGHT across the screen (new terrain enters from the left edge) — same
as the original; "scene slides left on a left lean" means the sign is
inverted.



- **DMA-direct**: the BMGR-generated panel-io leaves
  `psram_dma_direct` off → the SPI master bounces every frame through
  internal RAM. The app copies the generated io config, turns the flag
  on and creates its own panel-io + CO5300 panel object on the same bus
  (`esp_lcd_new_panel_io_spi` / `esp_lcd_new_panel_co5300`).
- **80 MHz pclk** (generated config: 40 MHz) — full frame over QSPI
  4-line data phase = 11.5 ms.
- **Exclusive coords**: `draw_bitmap` x_end/y_end are exclusive in this
  driver (CASET gets `x_end-1`). Passing `W-1/H-1` leaves the last
  column/row unwritten AND shears every row by one pixel (a diagonal
  "two triangles that don't join" artifact) — the full frame is
  `(0,0,W,H)`.
- **No TE sync (accepted tearing)**: flushes start at a random phase
  of the panel scan; measured on hardware, roughly a third of the
  frames show a tear line. A TE-synced variant (LCD_TE → GPIO43,
  edge-locked flush) was built and A/B'd on hardware: zero tears, but
  it needs an ISR or a spin and quantizes the frame period to whole
  scan cycles — dropped to keep the loop dead simple (the full design
  and the A/B numbers are in the git history). The flush path still
  blocks a few ms per frame inside the SPI driver (descriptor
  recycling), which feeds the idle task.
- **Double buffer**: `draw_bitmap` returns before its DMA completes
  (tx_color queues); rendering into the buffer that is NOT being
  streamed is what makes the async pipeline correct, and takes the
  11.5 ms wire time off the critical path.

## Performance (measured)

~25-30 fps (frame period quantized to 2-3 scan cycles; the frame's
work straddles the 33.4 ms boundary). The bottleneck is the
column-strided paint into PSRAM: each 2-byte pixel write with a
480-wide stride amplifies into a 64-byte cache-line fetch+writeback
(~30× line traffic) — the 94 algorithm's write pattern, unchanged by
design. `te_miss=0`, `err=0` over minutes of flight.

Float note: the SoC FPU is single-only (rv32imafc) and the FPC RTL has
no `fpc_sin_single` — trig calls promote to the double softfloat libm
regardless. The deg→rad arithmetic was forced to `single` (D2R const);
the measured effect is below noise (~0.1 ms of trig per 33-50 ms
frame). A 360-entry integer csf/snf table would remove the float
entirely if ever needed.

## Build

```sh
cd examples/landscape
ESP_FPC_ROOT=/mnt/storage/fpc-cross \
ESP32_SDK_PROJECT=/mnt/storage/fpc-esp/mosaico-s31 \
../../scripts/build.sh landscape.pas --soc esp32s31 \
    --lib espressif__esp_board_manager --lib gen_bmgr_codes \
    --lib esp_lcd --lib espressif__esp_lcd_co5300 \
    --lib waveshare__esp_lcd_touch_cst9217 --lib espressif__esp_lcd_touch \
    --lib espressif__esp_codec_dev --lib espressif__i2c_bus \
    --lib espressif__button --lib espressif__bq27220 \
    --lib espressif__esp_video --lib espressif__esp_cam_sensor \
    --lib espressif__esp_sccb_intf --lib esp_driver_cam --lib esp_driver_ppa \
    --lib esp_hal_cam \
    --lib /mnt/storage/fpc-esp/mosaico-s31/managed_components/espressif__bmi270_sensor/6.1/esp32s31/libbmi270_sensor.a \
    --lib esp_driver_gpio --lib esp_driver_spi \
    --lib esp_driver_i2c --lib esp_driver_i2s --lib esp_driver_ledc \
    --lib esp_hal_ledc --lib esp_hal_gpio --lib esp_hal_lcd \
    --lib esp_hal_i2c --lib esp_hal_i2s --lib esp_timer --lib esp_partition \
    --lib log --lib vfs --lib esp_system
```

The camera family (`esp_video`, `esp_cam_sensor`, `esp_driver_cam`,
`esp_hal_cam`, `esp_driver_ppa`) exists because the whole-archived BMGR
registry references `dev_camera_sub_dvp` regardless of what this app
opens. Extend per link errors otherwise.

## Flash (Mosaico discipline)

```sh
. /mnt/storage/fpc-cross/esp-cfg/env-6.1.sh && esp-env-esp32s31
export ESP32_SDK_PROJECT=/mnt/storage/fpc-esp/mosaico-s31
../../scripts/mkflash.sh --soc esp32s31 --tight landscape.elf
# one-shot alternative (flash.sh gained --no-stub for exactly this board):
# ../../scripts/flash.sh --soc esp32s31 --no-stub --port /dev/serial/by-id/<port> landscape.elf
esptool --no-stub --after hard-reset write-flash 0x0 landscape.flash.img \
    -p /dev/serial/by-id/<mosaico-port>
```

`--no-stub` mandatory (stub upload dies on this Type-C OTG link; the
app's usb_hs_console auto-download protocol accepts esptool's default
reset, which flips the board into the ROM CDC mid-connect — re-read
`/dev/serial/by-id/` after every esptool step, the name alternates
between `Espressif_Device_<mac>-if00` (app console, 303a:1001) and
`ESP32-S31_<mac>-if00` (ROM download, 303a:0020)). Never touch
`ttyACM1` — a different device. Serial capture: raw fd + DTR asserted,
RTS low.

## TThread / fthreads investigation (open, 2026-11-09/10)

The question "can Delphi-style TThread replace the raw
xTaskCreatePinnedToCore?" was tested across three routes; the raw call
stays for now. Findings:

- **ccrause/fpc-esp-freertos fthreads** (a full FPC ThreadManager over
  FreeRTOS: BeginThread/TThread/threadvars via FreeRTOS TLS), ported to
  this tree on the `origin/ccrause/fpc-esp-freertos` branch
  (units/freertos-fpc, correct `$7FFFFFFF` constant, idfheap
  integration): **works on esp32s3/QEMU** (`FTHREADS_DONE`, critical
  sections exact), **hard-hangs the system on esp32s31 hardware**
  (BeginThread → USB stops being serviced). The S31 hang is undiagnosed
  (flash races prevented a clean instrumented run); the S3/QEMU success
  proves the units' Xtensa path is fine — the RISC-V/SMP path is the
  suspect.
- **esp-emu (S31 machine) is broken for our binaries**: even the
  hardware-verified suite binary crashes under it — the emu's own
  TinyUSB console task fails init (emu's OTG emulation gap) and aborts
  the whole emulation at ~5 s; before that, the guest dies in
  `esp_vApplicationTickHook` jumping through a garbage `tick_cb[]`
  entry (the esp_system tick-callback array — disassembled + matched to
  esp_system/freertos_hooks.c). The S31 machine is a private espressif
  build (no public source at v0.51.0), so the runtime defect is not
  fixable from our side. Do not trust esp-emu S31 results for FPC
  binaries.
- The raw `xTaskCreatePinnedToCore` path (current landscape) is
  hardware-proven: 30 fps long-run, `err=0`, heap flat. The only latent
  gap vs TThread: FPC threadvars are not relocated for the raw task
  (harmless here — the ctrl task touches no threadvars; writeln from it
  is avoided by design).

## Verified — on hardware (2026-11-08, ESP-Mosaico)

1. Build exit 0 (three `--lib` iterations for the BMGR-pulled camera
   family); `__wrap_app_main → app_main = PASCALMAIN` chain intact.
2. 774144 B tight image @ 0x0, hash verified.
3. Console: init lines + `fps=24.7-29.8 te_miss=0 err=0` streaming over
   minutes.
4. Screen (user-confirmed): full-panel native render, no shear, no edge
   lines, no tearing; 94-style palette (dark blue sea, green/olive
   land, white peaks), black AMOLED sky.
5. Tilt steering (user-confirmed, 2026-11-08): lean left = the 94 #75
   (view turns left, scene slides right), flat = forward, vertical =
   backward; LEAN_SIGN=-1 on this mounting. Heap footprint of the
   BMI270 create (272 B below the no-IMU build) confirmed the sensor
   came up on the BMGR i2c_master bus.
5. Iterations learned: the exclusive-coordinate shear (first reported
   as "tearing"), the psram_dma_direct bounce, the TE period (60 Hz),
   the render cost model (cache-line amplification of column-strided
   writes), and a rejected band-skip expansion (stale rows above the
   moving band top = sky ghosting — superseded by the native render).
