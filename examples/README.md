# `examples/` — programs demonstrating how to use the units

Each program here is a small, complete demonstration of one unit (or one
interop pattern) from `units/`. Unlike `tests/` (compiler regressions under
the automated runner), these are meant to be **read first**, then built and
booted by hand.

Build/boot from the repo root:

```sh
scripts/build.sh examples/idfheap-smoke.pas
scripts/run-qemu.sh examples/idfheap-smoke.elf

# Pascal + C example (extra --lib names are LCD driver archives)
scripts/build.sh examples/pispigot-lcd.pas --c examples/waveshare_lcd.c \
  --lib esp_hal_i2c --lib esp_lcd --lib esp_driver_i2c --lib esp_driver_spi \
  --lib esp_driver_gpio --lib log
```

| Program | Shows | Personality |
| --- | --- | --- |
| [`idfheap-smoke`](#idfheap-smokepas) | `idfheap` in production shape | Proof that the pool is real |
| [`fpcthreads/`](#fpcthreads) | `fthreads` BeginThread / CS / RTLEvent / TLS once-only | Upstream demo (spin + blink) + 64-create stress for both emulators |
| [`leibniz`](#leibnizpas) | float timing with `esp_timer_get_time` | Relative benchmark, not a unit demo |
| [`pispigot-lcd`](#pispigot-lcdpas--waveshare_lcdc) | Pascal↔C + LCD console | Board-facing interop showcase |

Adding an example: keep it minimal and self-explaining, add a section here,
and keep the `idfheap`-first rule if it allocates anything (see `AGENTS.md`).

---

## `idfheap-smoke.pas`

**Purpose.** Prove that with `idfheap` first in `uses`, every observable
allocation — `GetMem`, sorted `TStringList` (in-place `ReAllocMem`), growing
dynarray — lives in the IDF pool, and that `GetFPCHeapStatus` reports real
`heap_caps_get_info` numbers. Pointers are classified with IDF's
`esp_ptr_external_ram` (never by address ranges).

**Personality.** The canonical “does the foundation work?” demo. Calm,
linear, exit 0. It exists so you can see SRAM vs PSRAM migration under
`CONFIG_SPIRAM_USE_MALLOC` without reading linker maps.

**Expected output (esp32s3).**

- **SDK without SPIRAM:** `GetMem(4096) @3FCAxxxx -> internal SRAM`,
  `IDF pool: used=~27KB free=~343KB size=~370908`, TStringList /
  dynarray lines also `-> internal SRAM`, `dynarray content ok, big[99]=9801`,
  exit 0.
- **SDK with SPIRAM (QEMU octal PSRAM):** boot shows `esp_psram: Found 32MB…`,
  then the same lines with `-> PSRAM` and a ~32 MB heap size.

**Pitfalls.** `uses idfheap` must be FIRST. Do not declare `esp_ptr_internal`
(header inline in IDF 5.x, not a linkable symbol). PSRAM variant needs the
SPIRAM link closure — `scripts/build.sh` handles it.

---

## `fpcthreads/`

**Purpose.** Demonstrate optional Delphi-style threading via
`units/freertos-fpc/fthreads`. Two programs:

- `fpcthreads.pas` — the upstream demo shape: 2 spin tasks via
  `BeginThread` released by an `RTLEvent`, plus a `blink` task via
  `fBeginThreadNamed` toggling GPIO 2 under a critical-section gate
  (`Resume blink` / `Pause blink` every ~2 s). Runs forever.
- `fthreads-stress.pas` — 64 `BeginThread`s (8×8 waves) with threadvars;
  asserts `GetFPCThreadVarBlockSize` stays fixed after the first create
  (guards against re-entering `InitThreadVars`).

Ported from ccrause's `fpcthreads` for IDF 6.1 + `idfheap` with the
upstream structure kept; the necessary deviations are `{ CHANGE: ... }`-marked
in the sources: the run-time stats table is dropped (no trace facility in
the hello-s3/hello-s31 anchors — `uxTaskGetSystemState` not linkable), the
core-ID line is dropped (`xPortGetCoreID` is a static inline in IDF 6.1),
and the GPIO calls are declared locally with `gpio_config` taking
`gpio_config_t` by reference (`constref`; by-value cdecl hands the first
struct word to the callee). The tick period is calibrated at esp_task's unit
initialization from the running kernel (`xPortGetTickRateHz`), so demo
timings are correct for any `CONFIG_FREERTOS_HZ` (100 Hz anchors: 10
ms/tick; 1000 Hz projects like mosaico-s31: 1 ms/tick).

**Personality.** The "Pascal threads without touching the RTL" suite.
Only the main task writes to the console. Marker: `FTHREADS_STRESS_DONE`
(stress); the demo runs forever and is killed by `timeout` by design.

**Expected output.**

- Demo S3/S31: `Creating fpc task 0/1`, `Starting spinTasks`,
  `After blink thread`, then alternating `Resume blink` / `Pause blink`.
- Stress: `TLS block size after first BeginThread=<n>`, eight `wave N done`
  lines with the same TLS size, `shared=2560`, `FTHREADS_STRESS_DONE`, exit 0
  (esp-emu exits via `--exit-on _haltproc`).

**Pitfalls.** `uses idfheap, fthreads` early (before `classes`). Needs
`CONFIG_FREERTOS_THREAD_LOCAL_STORAGE_POINTERS >= 1`. S3 runs anchor on
**hello-s3** (waveshare-s3's bootloader currently hangs this QEMU). See
`fpcthreads/README.md` for build commands.

---

## `leibniz.pas`

**Purpose.** Show a timing pattern: 10⁶ Leibniz π iterations bracketed by
`esp_timer_get_time` (µs, monotonic, external from `esp_timer`), and print
the float type via `TypeInfo`.

**Personality.** A stopwatch sketch, not a unit showcase. Useful for
relative single vs double cost on targets without a double FPU. Numbers are
emulator wall-clock — compare modes, do not treat them as board MIPS.

**Expected output.** `Leibniz Pi rounds 1000000 of type Double`,
`rounds: 1000000`, `loop: <n> us = <n> ms`, exit 0. On QEMU S3 here:
**double ≈ 8.8–9.7 s**, **single ≈ 1.05 s**.

**Pitfalls.** `idfheap` must be first — formatting a float in `writeln`
allocates.

---

## `pispigot-lcd.pas` (+ `waveshare_lcd.c`)

**Purpose.** One binary, Pascal + C: spigot π fills a buffer inside a timed
region (no I/O in the timer), then feeds the first screenful to
`waveshare_lcd.c`'s ST7796 SPI LCD console (power/expander/esp_lcd/FreeRTOS
render task + `/dev/lcdcon` VFS). Serial reports time, digit count, and
dropped LCD bytes.

**Personality.** The board interop showcase — where Pascal computation
meets a real C driver stack. Deliberately paced writes so the LCD queue
does not drop the visible screenful. QEMU is a partial stand-in (no LCD/I2C);
treat serial `Time:` + exit 0 as the emulator verdict.

**Expected output (board).** Serial: IDF boot, `Time:` / `digits:` /
`lcd dropped bytes: 0`, `_haltproc … exit code: 0`. LCD holds
`Pi = 0314159265…` (first 795 digits = 40×20). Digits byte-exact vs the C
twin for n=5000; board ~17.4 s at `-O2` vs ~10.9 s for C.

**Pitfalls.** `idfheap` first. Pass the `--lib` set in the header snippet;
SDK project must build those components. Build `-O2` when comparing to C.

---

## Note on SPIRAM placement

With `CONFIG_SPIRAM_USE_MALLOC`, even *small* allocations can land in PSRAM:
IDF reserves internal SRAM for capability-tagged internal allocs
(`CONFIG_SPIRAM_MALLOC_RESERVE_INTERNAL`), and free space under that
threshold pushes default allocations outward.
