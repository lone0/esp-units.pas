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

**PSRAM SDK link closure (introduced 2026-10-24).** When the external SDK
project is built with `CONFIG_SPIRAM=y`, IDF's startup/flash archives gain
references to `esp_psram_*` symbols — and the link then needs
`libesp_psram.a`. The mechanics, verified by experiment:

- FPC only injects an extra archive for a `{$linklib <name>,static}` found
  in a **used** unit. A command-line `-k-l<name>` also reaches `ld`, but is
  scanned *before* the IDF object list pulls the `esp_psram_*` references —
  a static archive is only scanned once — so it silently links nothing.
- The comma suffix is **mandatory**: `{$linklib esp_psram}` without
  `,static` does not register at all.
- `idfheap.pp` therefore carries
  `{$ifdef ESPSDK_SPIRAM} {$linklib esp_psram,static} {$endif}`, and
  `scripts/build.sh` auto-detects the SPIRAM state from
  `$ESP32_SDK_PROJECT/build/config/sdkconfig.h`: it passes
  `-dESPSDK_SPIRAM` + `-Fl$PRJ/build/esp-idf/esp_psram` on a SPIRAM build,
  and nothing on a non-SPIRAM build (where the archive may not even exist).
- **ppu staleness trap:** FPC tracks source timestamps, not conditional
  defines — a `idfheap.ppu` compiled without `-dESPSDK_SPIRAM` would
  silently keep failing links after the SDK flips to SPIRAM. `build.sh`
  wipes `units/idfheap.ppu/.o` whenever the detected state differs from the
  stamp file `units/.idfheap-spiram-state`. If you build by hand instead of
  via `build.sh`, delete the ppu yourself after changing the define state.
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

## A frozen atomics suite under `units/`

A second unit suite (atomics for ESP-family SoCs, dual-core safe: machine-
locked operations with compile-time backend selection for Xtensa / RV32A /
ARM32 and a stock fallback) is present as a **frozen** unit directory (repo
`AGENTS.md` §1) and ships in this version **without API documentation or
tests**: unit names, class APIs and per-unit docs are reserved for a future
version. It is maintained-verified as-is (compiled + hardware-verified in the
sibling prototype from which it was copied verbatim); changes and tests for
it belong to the upstream prototype, not this tree.

---

## `esp-units.pas` root

The repo ships `units/` in reusable form; automation lives in `scripts/`
(`build.sh`, `run-qemu.sh`), the regression body in `tests/`.
Where to look for what:

| Directory | Content |
|---|---|
| `units/` | the bridge to the IDF memory manager (`idfheap`) and a frozen atomics suite (API detail reserved for a future version) |
| `units/<unit-dir>/DESIGN.md` | kept with its unit's sources; backend-selection rationale |
| `tests/` | compiler verification + demonstration programs (`tests/README.md` per test) |
| `scripts/` | build / QEMU / flash automation, SoC-parameterized |
