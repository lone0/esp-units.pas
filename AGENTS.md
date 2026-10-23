# AGENTS.md — esp-units.pas (for AI agents; humans are welcome)

**State one-liner:** standalone application-side repository: ESP32-family
Pascal utility units + compiler verification programs + SoC-parameterized
automation scripts + unit examples. fpc / esp-idf / qemu are **external
tools**. Verified 2026-10-24 with the current toolchain: suite **35 runtime
PASS / 0 CRASH / 0 COMPFAIL** + 1 compile-only from this path (§5) plus the
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
  2. *utility units dedicated to ESP32* for programmer convenience
     (`idfheap` = bridge to the IDF heap manager; `espatomics` = atomics
     library for dual-core SoCs).
- **Automation scripts** (`scripts/`) work across multiple SoCs of the
  ESP32 family (S3 implemented today, C3 the designed second): they build
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
- **`units/espatomics/` is FROZEN — user decision 2026-10-23:** no changes,
  no tests written for it, in this repo. The directory is a verbatim copy
  of the prototype used in its DESIGN (sources only; verified by checksum
  at copy time). Document its API in `units/README.md`; do not edit
  the sources; do not add `t_atomics_*` tests. Demand for unit changes goes
  back to the user, not into this tree.
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
| `units/espatomics/` | atomics unit pair **(frozen, §1)**: `espatomics.pas` (class helper `TInterlockedEsp` + `TAtomicFlag`, backend selection via `$I`: xtensa / rv32a / arm32 / stock), `freertosinterlocked.pas` (32-bit `TInterlocked` baseline), 6 `.inc`, `DESIGN.md` |
| `units/README.md` | API docs + examples for both units |
| `tests/` | the suite: 33 renamed webtbs regressions + `t_generics_collections_tstack` (moved demo) + probes (`probe-enc`, `probe-idfheap`) + compile-only unit `u_generics_pubsub_events.pas`; subdir `thread-stubs/` (designed-loud failures, out of stats); `run-tests.sh`, `README.md` per-test docs |
| `examples/` | unit demonstrations, read-first/run-by-hand (`idfheap-smoke.pas` + `README.md` table); NOT part of the suite runner |
| `scripts/build.sh` | cross-compile (`--soc esp32s3|esp32s31`; per-SoC table at top; env required, no path defaults) |
| `scripts/mkflash.sh` | elf/bin → flash image (bootloader/PT offsets from SDK sdkconfig; app @ 0x10000) |
| `scripts/run-qemu.sh` | image → QEMU boot (esp32s3); esp32s31 is a placeholder → `run-esp-emu.sh` |
| `scripts/run-esp-emu.sh` | image → esp-emu boot for esp32s31 (QEMU has no S31 machine yet) |
| `scripts/flash.sh` | image → real port **only** when `--port` given |
| `.gitignore` | build/run artifacts; the durable record is these docs + reruns |

## 3. Ground rules for this repo

1. `idfheap` FIRST in the `uses` of every runtime program (every suite
   program follows it; the compile-only `u_generics_pubsub_events.pas`
   deliberately doesn't — do not "fix" that). Suite programs must run
   without `-Ch`.
2. Threading contract: the **Pascal** thread API fails loud
   (`TThread.Create` → exception, `TEvent.WaitFor`/RTLEventWaitFor →
   `RunError 232`, `threadvar` → 232 at first touch); raw FreeRTOS tasks
   via `xTaskCreatePinnedToCore` externals are the supported escape hatch
   (exact signatures and rules in §7). Do not weaken the Pascal stubs;
   do not use Pascal threadvars in real tasks.
3. `espatomics` frozen (§1). New shared-state code in tests/units uses
   FreeRTOS primitives or idfheap-routed plain variables, never edits the
   frozen unit.
4. Test naming: trunk-derived or moved-in tests keep `t_<topic>_<what>.pas`
   + line-1 provenance comment + a row in `tests/README.md`. Never re-add
   the two trunk tests known un-compilable for this target (tw16315b
   const-fold, tw3721 heaptrc) — see the "Removed as not applicable" note
   in `tests/README.md`.
5. No new SoC is "supported" until its row exists in `scripts/build.sh`'s
   table AND one boot is verified; otherwise mark *designed for* with the
   missing prerequisite.
6. Keep docs honest in both directions: don't claim suite coverage that
   doesn't exist (e.g. currently none for espatomics), and don't hide
   designed failures as bugs.

## 4. Environment interfaces

No host-path or IDF-version defaults. Required vars error out if unset.
Binutils / IDF root may still be *discovered* from the toolchain `fpc.cfg`
`-Fl` lines once `ESP_FPC_ROOT*` is set.

| Variable | Required? | Note |
|---|---|---|
| `ESP_FPC_ROOT` | yes | fpc-cross install for this build; `--soc` selects `ppcrossxtensa` / `ppcrossriscv32` inside it |
| `ESP_IDF_VERSION` | yes | passed as `-WP…` (e.g. `6.1`); no default |
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
scripts/flash.sh examples/idfheap-smoke.elf     # image only (no port -> no write)

# designed failures (run manually, each prints its designed outcome):
cd tests/thread-stubs
../scripts/build.sh t_cs_noop.pas && timeout 8 ../scripts/run-qemu.sh "$PWD/t_cs_noop.elf"
```

The suite floor is **all green**: 35 runtime PASS / 0 CRASH / 0 COMPFAIL
(33 webtbs + 2 probes + 1 moved demo) plus the compile-only unit verdict
`u_generics_pubsub_events` (COMPILE-ONLY, no boot), plus the three
`thread-stubs/` designed outcomes (`cs ok`, `ESyncObjectException`,
TThread-stub exception) and the `examples/` demonstration built+booted by
hand (its output is listed in `examples/README.md`). If a regression fails
for compiler-internal reasons, verify against a known-good toolchain
rebuild (the private toolchain workspace's build documentation) before
suspecting this repo.

**SPIRAM variant (enabled in `blink-s3` since 2026-10-24, verified
2026-10-24).** Same commands; expected differences:
- `build.sh` auto-detects `CONFIG_SPIRAM 1` in the SDK project's
  `sdkconfig.h` and adds `-dESPSDK_SPIRAM -Fl…/esp_psram` (see
  `units/README.md` for why + traps).
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

**Threading escape hatch (real tasks, no RTL threading):**

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
  `RunError 232`) — pass state via the `param` pointer and queues.
- `idfheap` (heap_caps layer) IS task-safe; containers/objects are NOT —
  share them only behind `xSemaphoreCreateMutex`/`xQueue*` or a
  `TAtomicFlag`-style guarded window of your own.
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
`SPIRAM or 8BIT` (0 = off — exactly what `probe-idfheap.pas` prints). Ask
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
- **The PSRAM link closure lives in FPC-land, not QEMU-land** (see
  `units/README.md`): SPIRAM links need a used unit with
  `{$linklib esp_psram,static}` — command-line `-k-l<name>` does not work.
- 15 s wall-clock cap per boot is plenty for every current suite program.
- Guru/panic text appears verbatim in the serial log; symbolize crashes with
  `xtensa-esp32s3-elf-addr2line` on the program's `.elf` (espressif toolchain
  under `~/.espressif/tools/xtensa-esp-elf`).
