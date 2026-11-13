# AGENTS.md — esp-units.pas (for AI agents; humans are welcome)

**State one-liner:** standalone application-side repository: ESP32-family
Pascal utility units + compiler verification programs + SoC-parameterized
automation scripts + unit examples. fpc / esp-idf / qemu are **external
tools**. Inventory 2026-10-24 with the current toolchain: **34 runtime programs +
1 compile-only** in this path (§5) plus the
`examples/` `idfheap-smoke` demo verified built+booted (SPIRAM on and off);
`fpc-hello` in the toolchain
workspace was removed *after* every one of its functions moved here.
**Nothing is committed until the user asks.**

---

## 1. Identity & purpose (from the user's own words — treat as design law)

- Name: **esp-units.pas** (the `.pas` is part of the project's name and
  will appear on GitHub as such; the repo dir carries it too).
- **Two kinds of content** and only those:
  1. *test programs* — verify and demonstrate the compiler's abilities on
     ESP32 MCUs;
  2. *utility units dedicated to ESP32* for programmer convenience:
     one unit per subdirectory under `units/`; today an IDF-heap manager
     bridge (`idfheap`), an opt-in FreeRTOS thread manager (`freertos-fpc`),
     and an atomics library for dual-core SoCs (see `units/README.md` for the
     current list).
- **Automation scripts** (`scripts/`) work across multiple SoCs of the
  ESP32 family (esp32s3 in QEMU today, esp32s31 on the riscv32 path via
  `run-esp-emu.sh`): they build
  Pascal programs, load them in QEMU, generate flash images for real hardware.
- **fpc and esp-idf are external tools.** Keep the project light, simple,
  readable for human learners. Do not vendor toolchains; no build system
  beyond the thin scripts.
- **ESP-version decoupled.** Nothing in the repo may hardcode an ESP-IDF
  version or assume IDF internals beyond the stable `heap_caps_*` /
  FreeRTOS API surface; the version enters only via `ESP_IDF_VERSION`
  (→ the toolchain's `espidf_<NNN>` interface unit).
- **fpc patches do not belong here.** Compiler/toolchain fixes live in the
  separate (private) toolchain workspace: a pristine-upstream FPC worktree
  + a 4-patch series + a guarded rebuild setup. If a test here fails for a
  *compiler-internal* reason, that is a report-upstream topic, not a reason
  to enlarge this repo.
- **`units/espatomics/` is a self-contained sub-project (ESP.Atomics).**
  Requirements, design, implementation, and its own agent knowledge live
  under that directory (`REQUIREMENTS.md`, `DESIGN.md`,
  `IMPLEMENTATION.md`, `AGENTS.md`). Treat it as the atomics product
  surface; do not duplicate its API docs in the parent. Changes to atomics
  sources or docs are made there, following that sub-project's AGENTS.md.
- **Docs have prescribed forms:**
  - *test programs*: `tests/README.md` explains, per test, purpose /
    expected outcome / pitfall.
  - *utility units*: `units/README.md` is an API document with simple
    examples explaining intended use and the problem each unit resolves.
- **Agent conduct rules from the user:** no arbitrary decisions — ask when
  in real doubt; **do not commit without the user's request**; tests must be
  verifiable with the *current* fpc/ESP-IDF/QEMU.

## 2. Layout map

| Path | What it is |
|---|---|
| `units/idfheap.pp` | IDF-heap memory-manager bridge (**first in uses** rule); suite-exercised every run |
| `units/freertos-fpc/` | optional ESP-IDF FreeRTOS task/semaphore bindings + FPC thread manager; opt-in only, RTL stubs unchanged |
| `units/espatomics/` | self-contained ESP.Atomics sub-project (§1): sources + `REQUIREMENTS` / `DESIGN` / `IMPLEMENTATION` / `AGENTS` |
| `units/c_bmgr.pas` | L1 binding: esp_board_manager (hand-converted against the lvgl-s31 sdkconfig; registry needs whole-archive `--lib espressif__esp_board_manager --lib gen_bmgr_codes`) |
| `units/c_lvgl_adapter.pas` | L1 binding: espressif__esp_lvgl_adapter (CONFIG-gated active surface; designated-initializer macros as field-verified Pascal record functions) |
| `units/c_lvgl.pas` | L1 binding: LVGL 9.6 working subset (grows per business; bakes the v9 facts incl. the packed-`lv_color_t` by-value strategy — psABI-bitified cuint, **hardware-verified pure-red 2026-11-07**) |
| `units/c_esp_lcd.pas` | L1 binding: esp_lcd panel ops (`esp_lcd_panel_draw_bitmap` etc.; opaque handles live in `c_bmgr`) |
| `units/c_bmi270.pas` | L1 binding: espressif bmi270_sensor (precompiled component archive, path in its header) |
| `units/boarddisplay.pas` | L2 panel chain (LVGL-free): `TBoardDisplay.Start` = BMGR display_lcd + `psram_dma_direct`/80MHz override via the official deinit→override_config→init re-init; `TBoardDisplay.Panel`; halts on failure |
| `units/boardlvgl.pas` | L2 LVGL facade (ex boarddisplay, renamed 2026-11-11): use → lcd_touch/lcd_brightness lazy-init; `TBoardLvgl.Start/StartEx(config)/Stop/UILock/UIUnlock`; panel via `boarddisplay`; value-semantics config, callbacks/TE/mono stay L1 |
| `units/imuattitude.pas` | L2 tilt angles (ex bmi270tilt, renamed 2026-11-11): `TImuAttitude.InitBmi270(periph, addr)/Read`; boot-pose baseline; roll+pitch only (yaw = not provided); consumers keep board facts (addr) app-side |
| `units/README.md` | API docs + the **L1/L2 naming grammar** (`c_<C component>` = binding shadow, functional name = Pascal-native) + examples for published units; points at `units/espatomics/` for atomics |
| `tests/` | the suite: 32 renamed webtbs regressions (incl. compile-only `u_generics_pubsub_events.pas`) + `t_generics_collections_tstack` (moved demo); `run-tests.sh`, `README.md` per-test docs. Self-authored cases are NOT committed (policy 2026-10-24; the self-authored `t_encoding_roundtrip` and `tests/thread-stubs/` were removed 2026-11-12 — upstream thread cases live in FPCSource `tests/test/`). |
| `examples/` | unit demonstrations, read-first/run-by-hand (`idfheap-smoke.pas`, `fpcthreads/`, `leibniz.pas`, `pispigot-lcd.pas` + `waveshare_lcd.c`, `display_lvgl/`, `display-native/` + `README.md` table); NOT part of the suite runner |
| `scripts/build.sh` | cross-compile (`--soc esp32s3|esp32s31`; per-SoC table at top; env required, no path defaults; `--c`/`--obj`/`--lib`/`--cflags` for C interop) |
| `scripts/mkflash.sh` | elf/bin → flash image (bootloader/PT offsets from SDK sdkconfig; app @ 0x10000). Default padding = full flash size (QEMU needs 2/4/8/16 MB); `--tight` pads to the content end only |
| `scripts/run-qemu.sh` | image → QEMU boot (esp32s3); esp32s31 is a placeholder → `run-esp-emu.sh` |
| `scripts/run-esp-emu.sh` | image → esp-emu boot for esp32s31 (QEMU has no S31 machine yet) |
| `scripts/flash.sh` | image → real port **only** when `--port` given; writes the `--tight` (content-only) image at 460800 baud (`--baud`/`ESP_BAUD` to change) |
| `.gitignore` | build/run artifacts; the durable record is these docs + reruns |

## 3. Ground rules for this repo

1. `idfheap` FIRST in the `uses` of every runtime program (every suite
   program follows it; the compile-only `u_generics_pubsub_events.pas`
   deliberately doesn't — do not "fix" that). Suite programs must run
   without `-Ch`.
2. Threading contract: by default the **Pascal** thread API fails loud
   (`TThread.Create` → exception, `TEvent.WaitFor`/RTLEventWaitFor →
   `RunError 232`, `threadvar` → 232 at first touch). Raw FreeRTOS tasks
   via `xTaskCreatePinnedToCore` remain the low-level escape hatch (exact
   signatures and rules in §7); `units/freertos-fpc/` is a separate, explicit
   opt-in supplement for applications needing the supported Pascal subset.
   Do not weaken the RTL stubs. Do not use Pascal threadvars with raw tasks;
   the opt-in manager requires a configured FreeRTOS TLS slot.
3. Atomics changes go in `units/espatomics/` per that sub-project's
   `AGENTS.md` (§1). Do not duplicate its API docs in the parent.
4. Test naming: trunk-derived or moved-in tests keep `t_<topic>_<what>.pas`
   + line-1 provenance comment + a row in `tests/README.md`. Never re-add
   the two trunk tests known un-compilable for this target (tw16315b
   const-fold, tw3721 heaptrc) — see the "Removed as not applicable" note
   in `tests/README.md`.
5. No new SoC is "supported" until its row exists in `scripts/build.sh`'s
   table AND one boot is verified; otherwise mark *designed for* with the
   missing prerequisite.
6. Keep docs honest in both directions: don't claim suite coverage that
   doesn't exist (e.g. currently none for `espatomics`), and don't hide
   designed failures as bugs.
7. Official Espressif MCP servers are configured globally in the user's
   OpenCode (`mcp.espressif.com` catalog, 2026-11-06): documentation (`mcp.espressif.com/docs`),
   component registry, engineering/troubleshooting, RainMaker, ESP-VISION,
   ESP-Pilot. When a question concerns ESP chips or ESP SDKs (ESP-IDF,
   peripheral behavior, hardware parameters), or a reusable ESP-IDF
   component might exist, use the documentation and component-registry
   servers without waiting to be asked; prefer them over web search.
8. C components get L1 `c_<name>` bindings; Pascal-native services get
   unprefixed L2 units (grammar in `units/README.md`). Decision record
   (2026-11-07): for esp_board_manager the L2 is the **business-chain
   facade** `boarddisplay` (2026-11-11 split: panel chain kept the name
   `boarddisplay`, the LVGL facade became `boardlvgl`), and deliberately NOT an interface class (the C
   registry is global, string-keyed, refcounted — a class would invent
   ownership the C design does not have) and NOT a per-device record
   family (the only consumers' real shape is "module-level var holds the
   handle"; the mosaico business blocks need ~10 lines of extra struct
   bindings total, all on the IDF-component side — iot_button, bq27220 —
   not on bmgr). Build L2 only where a consumer repeats friction.

## 4. Environment interfaces

No host-path or IDF-version defaults. Required vars error out if unset.
Binutils / IDF root may still be *discovered* from the toolchain `fpc.cfg`
`-Fl` lines once `ESP_FPC_ROOT*` is set.
`scripts/build.sh --help` prints this contract with example values (it runs
with no environment set).
The link closure and binutils prefix are **derived by `build.sh`** from
`ESP32_SDK_PROJECT` / `ESP_IDF_PATH` / `ESP_TOOLCHAIN_BIN`: `-XP<…>-esp-…-elf-`
from the toolchain dir, plus `-Fl` for the project's `build/esp-idf/**`
(recursive — some components keep archives below the top level, e.g.
`mbedtls/mbedtls/library/libmbedcrypto.a`), IDF's per-chip `ld` scripts and
prebuilt libs, and the toolchain's libgcc/sysroot.
If neither the env nor the toolchain `fpc.cfg` names the binutils dir / IDF
root, they are read from the SDK project's `build/project_description.json`
(`c_compiler`, `idf_path`). The FPU mode is read from the installed RTL with
`ppudump` (`-Cfsoft`/`-Cfhard`) so it cannot mismatch the units; the package
units are probed the same way, because a *partially* reinstalled toolchain
(RTL rebuilt with one FPU mode, `rtl-generics`/`rtl-objpas` left from an older
build) makes every package unit look like a missing one — `build.sh` warns
about exactly that and the cure is `make all install` with a single flag set.
**Libc scheme:** IDF 6.x builds `esp_libc` on top of the toolchain's
*picolibc*, while the same toolchain still ships a legacy newlib `libc.a` in
`xtensa-esp-elf/lib/<chip>`. Both define `printf`/`malloc`, so order decides:
when the project built `esp_libc`, its startup object needs picolibc's
`__bufio_*`, so `…/picolibc/*/lib/<chip>` is placed **before** the other
`-Fl` dirs automatically.
A plain `make install` `fpc.cfg` therefore works; a hand-prepared cfg keeps
working — duplicate `-Fl` lines are harmless. The cfg is in fact **optional**
(`build.sh` runs when `lib/fpc/etc/fpc.cfg` is absent): unit search paths come
from `…/units/<target>-freertos`, and binutils/IDF come from
`ESP_TOOLCHAIN_BIN`/`ESP_IDF_PATH` or `project_description.json`.

**C interop (`--c` / `--obj` / `--lib` / `--cflags`).** A Pascal program that
declares `cdecl; external` symbols is built in one command with the C sources:
`scripts/build.sh prog.pas --c module.c`. `--c` compiles with the *derived*
cross gcc using the command IDF recorded for the project's `main/` component in
`build/compile_commands.json` (exact include order — a guessed
`-I components/*/include` set picks up the unused Linux-compat component whose
`bsd/sys/cdefs.h` breaks libc headers). `--obj` links prebuilt objects, `--lib`
links archives by name (`lib<name>.a` searched in the derived `-Fl` dirs) or by
path; archives go in with `-k--whole-archive … -k--no-whole-archive` because FPC
passes `-k` arguments **before** its own objects. No C code or Makefile enters
the repo, and the SDK project is untouched.

**The SDK project must build what the RTL and build.sh link.** The freertos
binding (`espidf_<NNN>`) carries `{$linklib}` entries for a fixed,
config-independent archive list; `scripts/build.sh` additionally links
`libesp_psram.a` (SPIRAM sdkconfig) and `libespcoredump.a` (archive
present) whole-archive from the same project. A component that the app
never required is never built, so its `.a` does not exist and the link
fails with `cannot find lib….a`. Minimal working `main/CMakeLists.txt`
closure for a Pascal app:

```cmake
idf_component_register(SRCS "hello_world_main.c"
                       PRIV_REQUIRES spi_flash
                       REQUIRES esp_phy esp_coex esp_gdbstub espcoredump driver
                                vfs mbedtls esp_driver_uart
                                esp_driver_usb_serial_jtag esp_ringbuf
                                esp_psram
                       INCLUDE_DIRS "")
```

(`esp_psram` only when SPIRAM is on.) Trimming the binding is *not* the fix;
widening the project's `REQUIRES` is.

| Variable | Required? | Note |
|---|---|---|
| `ESP_FPC_ROOT` | yes | fpc-cross install for this build; `--soc` selects `ppcrossxtensa` / `ppcrossrv32` inside it |
| `ESP_IDF_VERSION` | no | passed as `-WP…` (e.g. `6.1`); default `6.1` |
| `ESP32_SDK_PROJECT` | yes | built ESP-IDF project (bootloader/PT/sdkconfig / SPIRAM libs) |
| `ESP_IDF_PATH` | if no `ESP_PYTHON_BIN` / no `-Fl` hit | ESP-IDF root |
| `ESP_TOOLCHAIN_BIN` | optional | else from `fpc.cfg` `-Fl` …/`<toolchain>`/… |
| `ESP_PYTHON_BIN` | optional | else `~/.espressif/python_env/idf<MM>_*/bin` from IDF path name |
| `ESP_QEMU` | optional | else `qemu-system-xtensa` on `PATH` / under `~/.espressif/tools` |
| `ESP_EMU` | optional | else `esp-emu` on `PATH` |

## 5. Verification recipe (current toolchain, expected results)

```sh
cd esp-units.pas                                # repo root
# export ESP_FPC_ROOT ESP_IDF_VERSION ESP32_SDK_PROJECT ESP_IDF_PATH …
scripts/build.sh examples/idfheap-smoke.pas     # cross-compile ok (esp32s3)
scripts/run-qemu.sh examples/idfheap-smoke.elf   # boots; pool numbers + exit 0
# point ESP_FPC_ROOT (+ ESP32_SDK_PROJECT) at the riscv32 install, then:
scripts/build.sh --soc esp32s31 examples/idfheap-smoke.pas
scripts/run-esp-emu.sh examples/idfheap-smoke.elf  # S31 via esp-emu (not QEMU)
cd tests && ./run-tests.sh                      # expect all green (see below)
scripts/flash.sh examples/idfheap-smoke.elf     # image only (no port -> no write; --tight size ~0.3 MB, not 16 MB)

# optional Pascal threading demo (manual; not part of the test suite):
scripts/build.sh examples/fpcthreads/fpcthreads.pas
timeout 20 scripts/run-qemu.sh examples/fpcthreads/fpcthreads.elf
```

The suite is **33 runtime programs + 1 compile-only** (32 webtbs programs,
one of them the compile-only unit, + the moved `t_generics_collections_tstack`
demo; the self-authored `t_encoding_roundtrip` and `tests/thread-stubs/`
were removed on 2026-11-12 — upstream FPCSource's own thread cases under
`FPCSource-esp-idf/tests/test/` replace the latter). The floor is **all green**: 33 runtime PASS /
0 CRASH / 0 COMPFAIL, with `u_generics_pubsub_events` COMPILE-ONLY (a unit —
it builds but never boots). A full-suite green run is a per-toolchain
milestone, not something the inventory alone guarantees. **Last full green run:
2026-10-28, ESP-IDF 6.1 toolchain with SPIRAM SDK (34 PASS + 1 COMPILE-ONLY,
including the since-removed `t_encoding_roundtrip`);
`examples/idfheap-smoke.pas` built and booted in the same session. 2026-11-02:
Mosaico real-hardware run also all green (34 PASS + 1 COMPILE-ONLY).** Add the
`examples/` demonstration built+booted by
hand (its output is listed in `examples/README.md`). If a regression fails
for compiler-internal reasons, verify against a known-good toolchain
rebuild (the private toolchain workspace's build documentation) before
suspecting this repo.

A PASS requires the image to have *run*: the runner demands boot evidence
(`ESP-ROM:`, `rst:0x…`, `Build:` or `_haltproc`) before it accepts a log as
clean, and reports **NOBOOT** when imaging/emulation never got that far —
otherwise a broken `mkflash.sh`/QEMU invocation would show up as a green run
with the tool's error text in the detail column.

**esptool dialects.** `mkflash.sh` and `flash.sh` detect the esptool major
version and use v4's underscore spelling (`--flash_size`, `merge_bin`,
`write_flash`) or v5+'s hyphenated one (`--flash-size`, `merge-bin`,
`write-flash`), so an IDF 5.x venv and an IDF 6.x venv both work; the version
in the `-WP` unit and the venv on `PATH` are independent choices.

**SPIRAM variant (enabled in `blink-s3` since 2026-10-24, verified
2026-10-24).** Same commands; expected differences:
- `build.sh` auto-detects `CONFIG_SPIRAM 1` in the SDK project's
  `sdkconfig.h` and links `libesp_psram.a` whole-archive from the project's
  build tree; `libespcoredump.a` is linked the same way whenever the
  project built it. Identical rule for esp32s3 and esp32s31 (see
  `units/README.md` for the mechanics).
- the example then prints `-> PSRAM` for *every* line and a ~32 MB heap
  (`IDF pool: … size=~33591564`); even the 4096-byte `GetMem` is PSRAM —
  IDF reserves 32 KiB internal for cap-flagged allocations
  (`CONFIG_SPIRAM_MALLOC_RESERVE_INTERNAL`), pushing default allocations
  to the external pool.
- `run-qemu.sh` auto-switches to the PSRAM boot (bootlog: `octal_psram`
  detection + `esp_psram: Found 32MB PSRAM device`); suite re-verified
  all-green under the SPIRAM SDK with the same auto-switching.

## 6. Open threads (recorded, not decided)

- `esp32s31`: build + `run-esp-emu.sh` when `ESP_FPC_ROOT` points at a
  riscv32 install and `ESP32_SDK_PROJECT` is set. QEMU has no S31 machine —
  `run-qemu.sh --soc esp32s31` is a placeholder that points at `run-esp-emu.sh`.
- A multi-MB PSRAM alloc + checksum *test* program (the user asked for the
  example-level PSRAM demo, delivered 2026-10-24; a suite-grade test with a
  checksum over several MB in PSRAM is still unwritten).
- `examples/pispigot-lcd.pas`: builds and boots (link path verified in QEMU,
  exit 0), but the on-display rendering is **unverified** — QEMU models neither
  the LCD nor I2C, so a `flash.sh` run on real hardware is still missing.

## 7. ESP32 programming knowledge for writing code in this repo

Distilled, hardware/RTM-verified facts an agent needs when writing a new
test or unit here. (The private toolchain workspace documentation is the
deeper version; this section is self-sufficient for application-side work.)

**Memory model.** Everything runs in internal SRAM by default:
data SRAM `0x3FC88000–0x3FD00000` (FPC heap + RTOS stacks + IDF), IRAM
`0x40370000+`, and the cache window `0x3C000000–0x3E00000` holds flash DROM
*and* PSRAM indistinguishably by address alone. With `idfheap` first in
uses, ~340 KiB of IDF pool is free at program start; read logs accordingly
(3FC… = internal SRAM, 3C/3D… = cache window). Don't hardcode ranges in
code; in logs they orient.

**`idfheap` invariants (reading the source isn't optional before touching
the unit — but here are the load-bearing ones):** installed at unit init;
`uses heapmgr` inside it pins init order (heapmgr → idfheap → sysutils →
typinfo → classes); `TMemoryManager.ReAllocMem` must write `p` in place;
failure mirrors `ReturnNilIfGrowHeapFails`. Everything Pascal-allocated —
`GetMem/New/SetLength/AnsiString/TStringList/generics` — routes to
`heap_caps_malloc/free/realloc`, no special embedded style.

**Threading choices.** The default Pascal threading stubs remain loud; raw
FreeRTOS tasks are the low-level escape hatch, and
[`units/freertos-fpc/`](units/freertos-fpc/README.md) is a separate opt-in
`TThreadManager` for applications that need `BeginThread`, critical sections,
`RTLEvent`, or `threadvar`. Its limitations (notably no thread join), TLS
requirement, and `idfheap`/unit ordering are documented with the package.

**Raw FreeRTOS tasks (without the opt-in manager):**

```pascal
type TTaskFn = procedure(arg: pointer); cdecl;   { TaskFunction_t }
function xTaskCreatePinnedToCore(fn: TTaskFn; name: pchar; stackDepth: uint32;
  param: pointer; prio: uint32; handle: ppvoid; coreId: longint): longint;
  cdecl; external name 'xTaskCreatePinnedToCore';
```

- `stackDepth` is in **BYTES**; `uxTaskGetStackHighWaterMark` returns
  **WORDS** (divide by 4 when comparing) — the units asymmetry is the trap.
- cores `0`/`1` (S3), `tskNO_AFFINITY = $7FFFFFFF`; start stacks ≥ 4096 and
  tune via the high-water mark.
- workers must be `cdecl`; **Pascal `threadvar` is non-functional** (loud
  `RunError 232`) with the default RTL manager — pass state via the `param`
  pointer and queues.
- `idfheap` (heap_caps layer) IS task-safe; containers/objects are NOT —
  share them only behind `xSemaphoreCreateMutex`/`xQueue*` or a
  or an atomic-flag-style guarded window of your own.
- Exceptions in workers are unproven — workers fail via return values or
  queues, never by raising.
- Exit discipline: end the program only after workers self-deleted
  (`vTaskDelete(xTaskGetCurrentTaskHandle())`) or were deleted.
- `writeln` from two tasks interleaves without a lock; guard if order matters.

**Stacks.** The Pascal main-task stack = IDF main task stack =
`CONFIG_ESP_MAIN_TASK_STACK_SIZE` = **8192 bytes** in the SDK project —
one historical crash (t_formatfloat_neg_zeropad) was traced to the 3584
default. No deep recursion, no multi-KB locals.

**PSRAM facts** (for probing): caps — `MALLOC_CAP_8BIT = 1 shl 2`,
`MALLOC_CAP_SPIRAM = 1 shl 10`, `MALLOC_CAP_INTERNAL = 1 shl 11`,
`MALLOC_CAP_DEFAULT = 1 shl 12`. Ask "exists": free size of
`SPIRAM or 8BIT` (0 = off — declare `heap_caps_get_free_size` as an external,
or read the used/free/size figures `examples/idfheap-smoke.pas` prints through
`idfheap`'s `GetHeapStatus`). Ask
"this pointer?": `esp_ptr_external_ram(p)` (PSRAM-specific), never raw range
checks. Untouchable from ISRs / while flash cache disabled; slow vs SRAM;
DMA buffers stay internal by default.

## 8. QEMU facts (espressif qemu-system-xtensa 9.2.2 esp_develop_…20260417)

- The `esp32s3` machine **already contains an `ssi_psram` device** — never
  add a second one with `-device` (duplicates fail/segfault). To match an
  octal-PSRAM sdkconfig flip the property:
  `-global driver=ssi_psram,property=is_octal,value=true` (modeled 32 MB —
  capacity differs from real boards; presence/mode match).
- A SPIRAM-enabled sdkconfig reset-loops under the plain
  `-M esp32s3 -drive …,if=mtd` boot this repo's `run-qemu.sh` uses (correct
  only for non-PSRAM configs). The full recipe adds the efuse backing store
  (`-drive file=efuse.img,if=none,format=raw,id=efuse` +
  `-global driver=nvram.esp32s3.efuse,property=drive,value=efuse`) and
  `-global driver=timer.esp32s3.timg,property=wdt_disable,value=true`;
  `idf.py qemu` in any IDF ≥5.x builds this command line automatically
  (`tools/idf_py_actions/qemu_ext.py` — copy it from there when a PSRAM test
  comes). Bootloader then logs `octal_psram` detection.
- **The machine does not model USB-Serial-JTAG.** Console choice in the SDK
  project matters: `CONFIG_ESP_CONSOLE_UART_DEFAULT=y` (+ secondary USJ)
  shows serial in QEMU; `CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG=y` alone boots
  fine but prints *nothing*.
- **`run-qemu.sh` auto-switches now (2026-10-24).** It reads the SDK
  project's `build/config/sdkconfig.h`: with `CONFIG_SPIRAM 1` it boots the
  full recipe above (`-m 32M`, efuse drive + `nvram`/`timg` `-global`s,
  octal `-global` when `CONFIG_SPIRAM_MODE_OCT 1`), generating
  `build/qemu_efuse.bin` on first use (1 KiB, byte 38 = `0x0c` — identical
  to `idf.py qemu`'s own image, md5 `ad7ad345bc3a2fb71a55c0d6a44fa612`);
  without it the plain `-M <machine> -drive …,if=mtd` boot is unchanged.
  QEMU never exits after the program halts — keep the `timeout` cap
  (30 s for the PSRAM boot, which takes a few more seconds to initialize).
- **The SPIRAM link closure lives in build.sh, not QEMU-land** (see
  `units/README.md`): the script whole-archives `libesp_psram.a` (and
  `libespcoredump.a` when the project built it) from the SDK project —
  a command-line `-k-l<name>` does not work (it is scanned before the
  references exist).
- 15 s wall-clock cap per boot is plenty for every current suite program.
- Guru/panic text appears verbatim in the serial log; symbolize crashes with
  `xtensa-esp32s3-elf-addr2line` on the program's `.elf` (espressif toolchain
  under `~/.espressif/tools/xtensa-esp-elf`).
