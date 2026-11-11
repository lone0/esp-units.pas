# `fpcthreads` — Delphi-style threads via `fthreads`

Application-side demos of `units/freertos-fpc/fthreads.pp`: Pascal
`BeginThread` / `fBeginThreadNamed` / critical sections / `RTLEvent` on
ESP-IDF FreeRTOS, without changing the freertos RTL stubs in FPCSource.

Ported from [ccrause/fpc-esp-freertos `examples/fpcthreads`](https://github.com/ccrause/fpc-esp-freertos/tree/esp-idf-v5.5/examples/fpcthreads)
for IDF 6.1 + `idfheap`, with the upstream program structure kept; the
necessary deviations are marked `{ CHANGE: ... }` in the sources:

- `printRealTimeStats` (upstream's per-task run-time stats table) is
  dropped: it needs `CONFIG_FREERTOS_USE_TRACE_FACILITY`, which neither
  closure anchor enables (`uxTaskGetSystemState` is not compiled into
  their `libfreertos.a`), and enabling it would change the frozen SDK
  baselines (hello-s31 is the esp32s31 closure anchor and must stay
  untouched).
- the "Main running on core ID" line is dropped: IDF 6.1 implements
  `xPortGetCoreID` as a static inline, no linkable symbol.
- the GPIO calls are declared locally against the IDF 6.1
  esp_driver_gpio symbols; `gpio_config` must take the 24-byte
  `gpio_config_t` by **reference** (`constref`), matching the C ABI — a
  by-value cdecl declaration hands the first struct word to the callee in
  a register (observed as `LoadProhibited`).
- `portTICK_PERIOD_MS` in `esp_task` is calibrated at unit initialization
  from the running kernel (`xPortGetTickRateHz`), so timings are correct
  for any `CONFIG_FREERTOS_HZ` (100 Hz anchors: 10 ms/tick; 1000 Hz
  projects like mosaico-s31/waveshare-s3: 1 ms/tick).

| Program | Role |
| --- | --- |
| `fpcthreads.pas` | the upstream demo: 2 spin tasks started via `BeginThread` and released by an `RTLEvent`, plus a `blink` task started via `fBeginThreadNamed` that toggles GPIO 2 while gated by a critical section the main task opens/closes (`Resume blink` / `Pause blink` every ~2 s). Runs forever — kill it with a timeout |
| `fthreads-stress.pas` | 64 `BeginThread`s (8×8 waves) + threadvars; asserts the TLS block size stays fixed after the first create → `FTHREADS_STRESS_DONE` |

## Requires

- ESP-IDF project with `CONFIG_FREERTOS_THREAD_LOCAL_STORAGE_POINTERS >= 1`
- `idfheap` then `fthreads` early in `uses` (before `classes`)
- The S3 runs below use **hello-s3** as the SDK anchor, like the original
  fthreads verification. `esp-env-esp32s3` in the workspace env file
  points at waveshare-s3 (its bootloader currently hangs this QEMU at
  ROM `entry`, even for unrelated binaries) — for the fthreads examples
  override `ESP32_SDK_PROJECT` to hello-s3 as shown.

## Build & run

```sh
. /mnt/storage/fpc-cross/esp-cfg/env-6.1.sh

# esp32s3 (QEMU) — anchor = hello-s3
esp-env-esp32s3
export ESP32_SDK_PROJECT=/mnt/storage/fpc-esp/hello-s3
scripts/build.sh examples/fpcthreads/fpcthreads.pas
timeout 30 scripts/run-qemu.sh examples/fpcthreads/fpcthreads.elf
scripts/build.sh examples/fpcthreads/fthreads-stress.pas
timeout 40 scripts/run-qemu.sh examples/fpcthreads/fthreads-stress.elf

# esp32s31 (esp-emu) — anchor = hello-s31 (per esp-env-esp32s31)
esp-env-esp32s31
scripts/build.sh --soc esp32s31 examples/fpcthreads/fpcthreads.pas
timeout 40 scripts/run-esp-emu.sh --soc esp32s31 examples/fpcthreads/fpcthreads.elf
scripts/build.sh --soc esp32s31 examples/fpcthreads/fthreads-stress.pas
timeout 60 scripts/run-esp-emu.sh --soc esp32s31 examples/fpcthreads/fthreads-stress.elf
```

Expected markers: the demo prints `Creating fpc task 0/1`,
`Starting spinTasks`, `After blink thread`, then alternating
`Resume blink` / `Pause blink`; the stress prints `shared=2560`,
stable `TLS=1864`, `fail=FALSE` and `FTHREADS_STRESS_DONE` (on esp-emu it
exits 0 via `--exit-on _haltproc`). Verified 2026-11-12: S3 QEMU +
S31 esp-emu, demo and stress.
