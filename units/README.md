# `units/` — utility units for ESP32-family Pascal

Dedicated, reusable units for writing applications on ESP32 MCUs with the
FreePascal freertos target. Every unit here follows one rule: it must make
the platform's hard parts *disappear* from application code without hiding
the platform's limits (see `../AGENTS.md` for the design principles).

FPC and ESP-IDF are external tools; these units use only what the target RTL
plus the IDF SDK libraries (linked into every binary anyway) provide.

---

## `idfheap.pp` — the IDF-heap memory manager bridge

**Problem it resolves.** In the bare freertos RTL the Pascal memory manager
(heapmgr) has exactly one memory source: a static block whose size the
compiler bakes in per program via `-Ch<bytes>`. No `-Ch` ⇒ the first `GetMem`
halts with `RunError 203`. `idfheap` replaces that manager at unit
initialization with one routed to ESP-IDF's `heap_caps_*` allocator, so:

- every `GetMem`/`New`/`SetLength`/`AnsiString`/object allocation lands in
  IDF's `MALLOC_CAP_8BIT|DEFAULT` pool (~340 KiB free on a fresh S3 program),
- no compiler-baked static heap block wastes BSS (with nothing but
  `idfheap`, the `__fpc_initialheap` symbol shrinks to 4 bytes),
- once PSRAM is enabled in the IDF project, the same unit transparently
  benefits (allocations can come from PSRAM under
  `CONFIG_SPIRAM_USE_MALLOC`),
- `GetHeapStatus`/`GetFPCHeapStatus` report **real** numbers
  (`heap_caps_get_info`-derived) instead of fiction.

**Usage — the one rule: FIRST in the `uses` clause.**

```pascal
program hello;
uses idfheap, classes, sysutils;   { idfheap FIRST — always }
var
  L: TStringList;
  S: THeapStatus;
begin
  L := TStringList.Create;
  L.Sorted := True;               { exercises the ReAllocMem in-place contract }
  L.Add('heap from the IDF pool');
  S := GetHeapStatus;             { real IDF-pool numbers, not fiction }
  writeln(S.TotalAllocated, ' allocated; ', GetFPCHeapStatus.CurrHeapFree);
  L.Free;
end.
```

Why first: FPC runs unit initializations in `uses` order, and `heapmgr`'s
init would otherwise overwrite the IDF manager later (reinstalling the
empty static manager). `idfheap` therefore also `uses heapmgr` internally
to pin `heapmgr` → `idfheap` → `sysutils` → `classes` ordering.

**API (implicit — it replaces the memory manager):**

| What you do | What happens |
|---|---|
| `GetMem/Freemem/ReAllocMem`, `New/Dispose`, strings, objects, generics | routed to `heap_caps_malloc/free/realloc` |
| `GetMem(nil …)`-style failure | mirrors heapmgr: `RunError 203`, or `nil` *only* if the program itself set `ReturnNilIfGrowHeapFails := true` |
| `GetHeapStatus` / `GetFPCHeapStatus` | real IDF heap info numbers |
| `heap_caps_*` directly (declare externals) | unaffected — the same pool serves both |

**Footgun(s):**
- NOT first in uses ⇒ normal-looking code dies with `RunError 203` on the
  first allocation (including `writeln`, which allocates its console
  buffer). Review the `uses` order, not the allocation code.
- A pointer allocated on the static-heap manager (e.g. from a program that
  deliberately opts into the static heap with an explicit `-Ch`) cannot be
  freed through this manager — mixing the two managers' pointers is not
  supported by design, and nothing in this repo does it.

**SDK-config-dependent link closure (esp_psram / espcoredump).** IDF
archives whose existence depends on the sdkconfig are linked by
`scripts/build.sh`, keyed on the SDK project's own build output — the
identical rule for both SoCs (replaces the 2026-10-24 `-dESPSDK_SPIRAM` +
conditional-`{$linklib}`-in-idfheap mechanism, since 2026-10-31):

- `libesp_psram.a` when the project was built with `CONFIG_SPIRAM=y`: its
  startup/heap archives then reference `esp_psram_*` symbols. Detected from
  `build/config/sdkconfig.h`, with a hard error if the archive is missing.
- `libespcoredump.a` whenever the project built it: `libesp_system.a`'s
  panic handling references `esp_core_dump_write` then. Detected by archive
  presence, not config keys — a coredump-disabled project can still carry
  `CONFIG_ESP_COREDUMP_ENABLE_TO_NONE=y`.
- Mechanics (verified by experiment, and the reason neither the RTL nor any
  repo unit — `idfheap` included — carries a `{$linklib}` for these): FPC
  only injects an archive for a `{$linklib <name>,static}` found in a
  **used** unit, and it hands `-k` arguments to the linker *before* its own
  objects. A plain `-k-l<name>` or bare archive path is scanned *before*
  the IDF objects pull the references — a static archive is only scanned
  once — so it silently links nothing. The script therefore wraps each
  archive in `-k--whole-archive … -k--no-whole-archive` (a few KB each).
  The comma suffix stays **mandatory** for hand-written unit `{$linklib}`s:
  without `,static` the directive does not register at all.
- Hand links without `build.sh`: declare the archive in an application
  unit (see above) or pass the whole-archive `-k` triple yourself.
- End-to-end proven with the QEMU octal-PSRAM boot (see the repo AGENTS.md
  §8): IDF maps the emulated 32 MB PSRAM and *every* Pascal allocation then
  comes from it (see `examples/idfheap-smoke.pas`).

---

### `idfheap` — reference programs

`../examples/idfheap-smoke.pas` is the worked demonstration
(GetMem/sorted TStringList/50 000-slot dynarray through the IDF pool; output
documented in `../examples/README.md`). Inside the suite, *every* runtime
program exercises it implicitly (it is first in `uses` everywhere); the pool
used/free/size numbers it prints through `GetHeapStatus` are real
`heap_caps_get_info` figures. Per-test details: `tests/README.md`.

## `freertos-fpc/` — opt-in Pascal threading

The freertos RTL deliberately leaves Pascal threading as loud stubs.
Applications that explicitly opt in can use an application-side
`TThreadManager` backed by ESP-IDF FreeRTOS tasks, mutexes, and binary
semaphores, without changing the RTL.

Put `idfheap` first and `fthreads` before units that initialize threading
(especially `classes`):

```pascal
uses idfheap, fthreads, sysutils;
```

The SDK must set `CONFIG_FREERTOS_THREAD_LOCAL_STORAGE_POINTERS` to at least
1. `BeginThread`, critical sections, `RTLEvent`, and thread-local storage are
provided by the opt-in manager. It does not provide a thread join:
`WaitForThreadTerminate` is not a completion wait, so synchronize through
events or queues. Task stack sizes are in bytes.

The package targets the linkable ESP-IDF 6.x FreeRTOS symbols. In
`esp_task.pp`, `portTICK_PERIOD_MS` must match the SDK's `CONFIG_FREERTOS_HZ`
when using timed RTLEvent waits; the Waveshare S3 project used for the example
is configured for 1000 Hz. The working example is
[`fpcthreads`](../examples/fpcthreads/README.md).

`esp_task.pp` contains the small task/TLS API surface used by the manager;
`esp_semphr.pp` wraps the linkable queue symbols used to implement FreeRTOS
mutex and binary-semaphore macros; `fthreads.pp` installs the manager. None
of these units changes the default RTL stubs unless the application includes
`fthreads`.

## `espatomics` — ESP.Atomics sub-project

Self-contained under [`espatomics/`](./espatomics/):

| Doc | Content |
| --- | --- |
| [`espatomics/REQUIREMENTS.md`](./espatomics/REQUIREMENTS.md) | Constraints + problem examples |
| [`espatomics/DESIGN.md`](./espatomics/DESIGN.md) | Architecture / routing matrix |
| [`espatomics/IMPLEMENTATION.md`](./espatomics/IMPLEMENTATION.md) | File map, backends, how to extend |
| [`espatomics/AGENTS.md`](./espatomics/AGENTS.md) | Agent rules for this sub-project |

Entry unit: `espatomics.pas` — unit-level leaves only (ReadAcquire/WriteRelease, AtomicExchangeAcqRel/SeqCst, Fetch*, CompareExchangeWeak). No uses clause, no class helper, no baseline unit.

---

## L1/L2 naming grammar — bindings vs native units

Two unit kinds share `units/`, and the name tells them apart (FPC itself
uses the `c` prefix for C-library bindings: `cthreads`, `cmem`, `cwstring`):

| Layer | Name grammar | Nature | Units |
|---|---|---|---|
| L1 binding | `c_<C component short name>` | hand-converted C-header shadow: `cdecl; external` functions keep their C names; records are C-ABI-true (`{$packrecords C}`, `{$minenumsize 4}`, sizes verified against the C build) | `c_bmgr`, `c_esp_lcd`, `c_lvgl_adapter`, `c_lvgl`, `c_bmi270` |
| L2 native | functional name, no `c_` prefix | Pascal-idiomatic service built on L1: advanced records with static methods, value-semantics config, `esp_err_t` visible, no exceptions | `boarddisplay` (panel chain), `boardlvgl` (LVGL facade), `imuattitude` (the functional `idfheap` and the `espatomics` sub-project predate the grammar and are L2 by nature) |

Rules the grammar enforces:

- An L1 unit is only ever edited as a header re-conversion: the source of
  truth is the C component + the consuming SDK project's sdkconfig, and the
  header comment records the conversion basis and validity domain. Never
  "improve" a C name inside L1 — idiomatization happens in L2.
- An L2 unit names its L1 dependencies, states its contract (what auto-runs
  at `uses`, what stays explicit), and only exists where a real consumer
  repeats friction — no speculative layer.
- L2 config surfaces are value-only (scalars/enums in one record); callback
  hooks stay L1.

## `c_bmgr` — esp_board_manager binding (L1)

Hand-converted from the esp_board_manager C headers (`esp_board_manager.h`,
`_defs.h`, `dev_display_lcd.h`, `dev_lcd_touch.h`) flattened with the
lvgl-s31 SDK project's own toolchain against its sdkconfig (ESP-Mosaico: of
the display sub-types only SPI survives the CONFIG gating; `CONFIG_SPIRAM=y`).
Record sizes verified against the C build (`dev_display_lcd_config_t` = 108 B,
touch config 108 B, SPI IO config 44 B, …). API: `init`,
`init/deinit_device_by_name`, `get_device_handle/config`, `get_board_info`,
plus the two device factories' entry points. The registry resolves only when
the component archives are whole-linked — `--lib espressif__esp_board_manager
--lib gen_bmgr_codes` (full closures in the examples' READMEs).

## `c_lvgl_adapter` — esp_lvgl_adapter binding (L1)

Hand-converted from `espressif__esp_lvgl_adapter` headers against the same
sdkconfig (the `CONFIG_ESP_LVGL_ADAPTER_ENABLE_FS/_DECODER/_FREETYPE/_BUTTON/
_KNOB/_FPS_STATS` blocks compile out there and are absent here). Covers the
active surface: adapter init/start/deinit, display + touch registration,
lock/unlock, activity/wake, pause/resume, sleep prepare/recover, dummy draw.
The C designated-initializer config macros have record-returning Pascal
equivalents verified field-for-field.

## `c_lvgl` — LVGL 9.6 working subset (L1)

Hand-converted working subset of `lvgl__lvgl` 9.6.0: screen/objects, label +
button, geometry, style setters, events, display info, `lv_font_montserrat_14`.
Grows per business need — deliberately NOT the full lvgl.h. The header comment
records the v9 facts it bakes in: int32_t coordinates, the real symbol
`lv_screen_active` (v8's `lv_scr_act` is only a macro), `lv_obj_is_in_widget_tree`
(v8's `lv_obj_is_valid` ditto), and the packed-`lv_color_t` by-value strategy
(psABI-bitified `cuint`; no C function returning `lv_color_t` is ever bound).

## `boarddisplay` — panel chain (L2)

The LVGL-free half of the display chain: `TBoardDisplay.Start` brings the
BMGR `display_lcd` device up with this board's two overrides
(`psram_dma_direct` + 80 MHz pclk) patched onto the generated config via
BMGR's official re-init path (deinit → override_config → init — an esp_lcd
panel object binds its io at creation, so patching means rebuilding), then
hands out the BMGR-owned handle via `TBoardDisplay.Panel`. Halts on failure
(landscape esp_init semantics); brightness is a CO5300 vendor register,
carried commented exactly as landscape runs it. Consumers:
`../examples/landscape/` (direct esp_lcd driver) and `boardlvgl`.

## `boardlvgl` — LVGL display-chain facade (L2)

`uses boardlvgl` lazily initializes the optional chain devices (lcd_touch,
lcd_brightness; warn-and-continue) in the unit initialization;
`TBoardLvgl.Start` (or `StartEx(TBoardLvglConfig)`) brings the panel up
through the `boarddisplay` chain, then brings the esp_lvgl_adapter up with
display + touch registered and the worker running — then
`lv_screen_active()` is live and Pascal UI code runs under
`TBoardLvgl.UILock/UIUnlock`. `Stop` is the terminal teardown (main.c's
cleanup path as a function). Full-board init stays L1
(`esp_board_manager_init`); callback hooks and TE/mono display profiles stay
L1 (`c_lvgl_adapter`). Consumer: `../examples/display-native/`.

## `imuattitude` — tilt angles (L2)

`TImuAttitude.InitBmi270(periph_name, addr)` opens the BMI270 on the BMGR
bus (borrowed handle; the bus lifecycle stays BMGR's), configures
accelerometer +-4G/100 Hz and samples the boot-pose lateral baseline;
`Read` returns roll (pose-relative) + tilt (gravity-absolute). Honest
boundary: roll+pitch only — yaw needs gyro/magnetometer fusion and is not
provided. L1 below: `c_bmi270`. Consumer: `../examples/landscape/`.

## `esp-units.pas` root

The repo ships `units/` in reusable form; automation lives in `scripts/`
(`build.sh`, `run-qemu.sh`), the regression body in `tests/`.
Where to look for what:

| Directory | Content |
|---|---|
| `units/` | `idfheap` + self-contained `espatomics/` sub-project + L1 bindings (`c_bmgr`, `c_esp_lcd`, `c_lvgl_adapter`, `c_lvgl`, `c_bmi270`) + L2 (`boarddisplay` panel chain, `boardlvgl` LVGL facade, `imuattitude`) |
| `units/espatomics/` | ESP.Atomics docs + sources (see its `AGENTS.md`) |
| `tests/` | compiler verification + demonstration programs (`tests/README.md` per test) |
| `scripts/` | build / QEMU / flash automation, SoC-parameterized |
