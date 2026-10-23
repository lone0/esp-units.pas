# esp-units.pas — Pascal utilities and compiler-verification programs for ESP32 MCUs

A light, readable project: FreePascal source only. The compiler
(`fpc`), the SDK (`esp-idf`) and the emulator (`qemu-system-xtensa`,
Espressif build) are **external tools** — this repo ships none of them.

It contains two kinds of things:

1. **Test programs** — verify and demonstrate what this compiler can do on
   real ESP32 MCUs: a curated subset of the FPC trunk regression suite
   (`t_*.pas`, provenance embedded line-by-line), capability demos
   (`t_generics_collections_tstack.pas`), probes for the memory
   manager and IDF-heap capabilities, and designed-failure demos of the
   threading contract (`tests/thread-stubs/`). `tests/run-tests.sh` compiles
   each one with the cross compiler and boots it in QEMU, classifying the
   result (`PASS` = clean boot, clean exit).
2. **Utility units** — programmer conveniences dedicated to ESP32:
   - [`units/idfheap.pp`](units/README.md) — bridge to the IDF heap
     manager: all Pascal dynamic memory flows into the IDF pool
     (PSRAM-eligible once enabled) instead of a compiler-baked static block.
   - [`units/espatomics/`](units/README.md) — atomic operations for
     ESP32 dual-core (and other ESP family) SoCs:
     `TInterlocked` baseline (missing from the freertos RTL),
     `TInterlockedEsp` fetch/CAS/acquire-release via the chip's
     compare-and-swap instruction, `TAtomicFlag` spin lock. Multi-SoC by
     construction: an xtensa backend (S3/S2/classic), an RV32A backend
     (C3/C6), an ARM32 backend, and a stock fallback; the activ
     backend is selected at compile time.

## Quickstart

```sh
# one-time: an IDF project must have been built once (bootloader + partition
# table + sdkconfig for linking/QEMU). Defaults point at the sibling
# workspace's blink-s3; override with ESP32_SDK_PROJECT=/your/own/project.

# 1. build a program (default SoC: esp32s3)
scripts/build.sh examples/idfheap-smoke.pas

# 2. boot it in QEMU (serial console on stdout)
scripts/run-qemu.sh examples/idfheap-smoke.elf

# 3. full regression suite
cd tests && ./run-tests.sh

# 4. produce the flash image for real hardware (writes only with --port!)
scripts/flash.sh examples/idfheap-smoke.elf
```

## SoC support

| SoC | Cores/ISA | State |
|---|---|---|
| esp32s3 | 2× xtensa lx7 | implemented & tested here |
| esp32c3 | 1× riscv32 | designed for (`--soc esp32c3`, rv32a atomics backend present); needs an external ppcrossriscv32 toolchain install |
| others | — | add a row in `scripts/build.sh`'s SoC table |

## Prerequisites (all external, all overridable)

| Need | Where/How |
|---|---|
| FreePascal freertos cross toolchain | `ESP_FPC_ROOT` (default: the sibling toolchain workspace on this machine; the tree with `lib/fpc/3.3.1/ppcrossxtensa`) |
| ESP-IDF project, built once | `ESP32_SDK_PROJECT` (default: the sibling workspace's `blink-s3`) — its `build/` provides bootloader, partition table, and the SDK libs the fpc.cfg links against |
| `esptool` | comes with an IDF install (`ESP_IDF_PATH`, python env) |
| Espressif QEMU | auto-found under `~/.espressif/tools/qemu-xtensa/*` |

No ESP-version tie: set `ESP_IDF_VERSION` to match the interface unit your
toolchain ships (default `5.2.8` → `espidf_50200`); the unit sources and
scripts never hardcode an IDF version.

## Layout

| Path | Content |
|---|---|
| `units/README.md` | **API documentation for the utility units** (usage, examples, problems resolved) |
| `units/espatomics/DESIGN.md` | backend-selection design rationale (kept with its sources) |
| `tests/README.md` | **per-test documentation**: purpose, expected outcome, pitfalls |
| `tests/run-tests.sh` | the suite runner |
| `examples/` | **example programs demonstrating units** (read-first, run-by-hand; `examples/README.md` table) |
| `scripts/` | `build.sh` · `run-qemu.sh` (QEMU boot image + boot) · `mkflash.sh` (image only) · `flash.sh` (image → a real port when you pass `--port`) |
| `AGENTS.md` | design criteria, verification recipe and decisions record for AI agents |
