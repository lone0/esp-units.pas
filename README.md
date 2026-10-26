# esp-units.pas — Pascal utilities and compiler-verification programs for ESP32 MCUs

A light, readable project: FreePascal source only. The compiler
(`fpc`), the SDK (`esp-idf`) and the emulator (`qemu-system-xtensa`,
Espressif build) are **external tools** — this repo ships none of them.

It contains two kinds of things:

1. **Test programs** — verify and demonstrate what this compiler can do on
   real ESP32 MCUs: a curated subset of the FPC trunk regression suite
   (`t_*.pas`, provenance embedded line-by-line), capability demos
   (`t_generics_collections_tstack.pas`, `t_encoding_roundtrip.pas`), and
   designed-failure demos of the
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
     (C3/C6), an ARM32 backend, and a stock fallback; the active
     backend is selected at compile time.

## Quickstart

Scripts take **no host-path defaults**. Export the toolchain locations first
(`scripts/build.sh --help` prints the same contract with concrete examples):

```sh
export ESP_IDF_VERSION=6.1                 # whatever -WP your RTL expects
export ESP_IDF_PATH=/path/to/esp-idf       # or set ESP_PYTHON_BIN
# optional: ESP_TOOLCHAIN_BIN, ESP_PYTHON_BIN, ESP_QEMU, ESP_EMU

# ESP_FPC_ROOT = install for *this* build. Switch it when you switch SoC.
# --soc only selects ppcrossxtensa vs ppcrossriscv32 + MCU flags inside that root.

export ESP_FPC_ROOT=/path/to/fpc-cross-xtensa
export ESP32_SDK_PROJECT=/path/to/built-idf-project-for-s3
scripts/build.sh examples/idfheap-smoke.pas
scripts/run-qemu.sh examples/idfheap-smoke.elf

export ESP_FPC_ROOT=/path/to/fpc-cross-riscv32
export ESP32_SDK_PROJECT=/path/to/built-idf-project-for-s31
scripts/build.sh --soc esp32s31 examples/idfheap-smoke.pas
scripts/run-esp-emu.sh examples/idfheap-smoke.elf
```

## SoC support

| SoC | Cores/ISA | State |
|---|---|---|
| esp32s3 | 2× xtensa lx7 | implemented (`run-qemu.sh`) |
| esp32s31 | 1× riscv32 ILP32F | implemented (`--soc esp32s31`); boot with `run-esp-emu.sh` (QEMU unsupported) |
| others | — | add a row in `scripts/build.sh`'s SoC table |

## Prerequisites (all external, all required via env)

| Need | Env |
|---|---|
| FreePascal freertos cross toolchain | `ESP_FPC_ROOT` (point at the install for the SoC you are building); no `fpc.cfg` editing needed — `build.sh` derives the binutils prefix, FPU mode, libc scheme and the IDF link closure |
| IDF version for `-WP` | `ESP_IDF_VERSION` (no default) |
| Built ESP-IDF project | `ESP32_SDK_PROJECT` — its app must `REQUIRES` the components the freertos RTL link-lists (see `AGENTS.md` §4), or the archives simply do not exist |
| ESP-IDF / esptool python | `ESP_IDF_PATH` and/or `ESP_PYTHON_BIN` (also discoverable from `fpc.cfg` `-Fl` for IDF root + binutils); esptool 4.x and 5.x CLI spellings are both handled |
| Espressif QEMU | `ESP_QEMU` or `qemu-system-xtensa` on `PATH` |
| esp-emu (S31) | `ESP_EMU` or `esp-emu` on `PATH` |

## Layout

| Path | Content |
|---|---|
| `units/README.md` | **API documentation for the utility units** (usage, examples, problems resolved) |
| `units/espatomics/DESIGN.md` | backend-selection design rationale (kept with its sources) |
| `tests/README.md` | **per-test documentation**: purpose, expected outcome, pitfalls |
| `tests/run-tests.sh` | the suite runner |
| `examples/` | **example programs demonstrating units** (read-first, run-by-hand; `examples/README.md` table) |
| `scripts/` | `build.sh` · `run-qemu.sh` (QEMU) · `run-esp-emu.sh` (esp32s31) · `mkflash.sh` · `flash.sh` |
| `AGENTS.md` | design criteria, verification recipe and decisions record for AI agents |
