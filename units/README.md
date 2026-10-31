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

## `espatomics` — ESP.Atomics sub-project

Self-contained under [`espatomics/`](./espatomics/):

| Doc | Content |
| --- | --- |
| [`espatomics/REQUIREMENTS.md`](./espatomics/REQUIREMENTS.md) | Constraints + problem examples |
| [`espatomics/DESIGN.md`](./espatomics/DESIGN.md) | Architecture / routing matrix |
| [`espatomics/IMPLEMENTATION.md`](./espatomics/IMPLEMENTATION.md) | File map, backends, how to extend |
| [`espatomics/AGENTS.md`](./espatomics/AGENTS.md) | Agent rules for this sub-project |

Entry unit: `espatomics.pas` (class helper on `TInterlocked` + `TAtomicFlag`).
FreeRTOS builds also need `freertosinterlocked.pas` for the 32-bit baseline.

---

## `esp-units.pas` root

The repo ships `units/` in reusable form; automation lives in `scripts/`
(`build.sh`, `run-qemu.sh`), the regression body in `tests/`.
Where to look for what:

| Directory | Content |
|---|---|
| `units/` | `idfheap` + self-contained `espatomics/` sub-project |
| `units/espatomics/` | ESP.Atomics docs + sources (see its `AGENTS.md`) |
| `tests/` | compiler verification + demonstration programs (`tests/README.md` per test) |
| `scripts/` | build / QEMU / flash automation, SoC-parameterized |
