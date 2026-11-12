# `units/` — utility units for ESP32-family Pascal

Dedicated, reusable units for writing applications on ESP32 MCUs with the
FreePascal freertos target. Every unit here follows one rule: it must make
the platform's hard parts *disappear* from application code without hiding
the platform's limits (see `../AGENTS.md` for the design principles).

FPC and ESP-IDF are external tools; these units use only what the target RTL
plus the IDF SDK libraries (linked into every binary anyway) provide.

Inventory today:

| Path | Kind | One-line personality |
| --- | --- | --- |
| [`idfheap.pp`](#idfheappp--the-idf-heap-memory-manager-bridge) | L2 native | Silent foundation: Pascal `GetMem` becomes IDF heap |
| [`freertos-fpc/`](#freertos-fpc--optional-delphi-style-threads) | L2 + thin bindings | Opt-in Delphi threads; RTL stubs stay loud |
| [`espatomics/`](#espatomics--espatomics-sub-project) | L2 sub-project | Zero-overhead atomics without rewriting callers |

Display-chain L1/L2 units (`c_bmgr`, `c_lvgl_adapter`, `c_lvgl`, `boarddisplay`)
are named in the [grammar](#l1l2-naming-grammar--bindings-vs-native-units)
below for when that chain lands; they are not in this tree yet.

---

## `idfheap.pp` — the IDF-heap memory manager bridge

**Purpose.** Make every Pascal allocation (`GetMem`, strings, objects,
dynarrays, `classes` singletons) come from ESP-IDF's `heap_caps_*` pools
instead of FPC's tiny static `-Ch` block.

**Personality.** The quiet foundation unit. It has almost no API surface —
you `uses` it and forget it. It is stubborn about one thing: it must be
**first** in `uses`, or the rest of the program looks broken for mysterious
`RunError 203` reasons. It never pretends the static heap still matters
while it is installed; it reports real IDF pool numbers through
`GetHeapStatus` / `GetFPCHeapStatus`.

**Problem it resolves.** Bare freertos RTL: no `-Ch` ⇒ first `GetMem`
halts with `RunError 203`. With `idfheap`:

- allocations land in `MALLOC_CAP_8BIT|DEFAULT` (~340 KiB free on a fresh S3),
- `__fpc_initialheap` shrinks to a few bytes of unused BSS,
- PSRAM (when the SDK enables `CONFIG_SPIRAM_USE_MALLOC`) is used transparently,
- heap status reports are real (`heap_caps_get_info`), not fiction.

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
init would otherwise overwrite the IDF manager later. `idfheap` also
`uses heapmgr` internally to pin `heapmgr` → `idfheap` → `sysutils` →
`classes`.

**API (implicit — it replaces the memory manager):**

| What you do | What happens |
|---|---|
| `GetMem/Freemem/ReAllocMem`, `New/Dispose`, strings, objects, generics | routed to `heap_caps_malloc/free/realloc` |
| allocation failure | `RunError 203` (Size ≠ 0), or `nil` if `ReturnNilIfGrowHeapFails`; **`GetMem(0)` → `nil`** for now (IDF `malloc(0)`; contradicts FPC non-nil contract — revisit when a real case needs it) |
| `GetHeapStatus` / `GetFPCHeapStatus` | real IDF heap info numbers |
| `heap_caps_*` directly (declare externals) | unaffected — same pool |

**Footguns.** Not first in `uses` ⇒ first allocation (including `writeln`)
dies with `RunError 203`. Do not mix pointers from an explicit `-Ch` static
heap with this manager.

**SDK link closure.** `scripts/build.sh` whole-archives `libesp_psram.a` /
`libespcoredump.a` when the SDK project needs them. Neither the RTL nor
`idfheap` carries those `{$linklib}`s — FPC's link order would otherwise
miss the symbols. Demo: `../examples/idfheap-smoke.pas`. Suite programs
exercise it implicitly (`idfheap` first everywhere).

---

## `freertos-fpc/` — optional Delphi-style threads

**Purpose.** Give applications that *want* Pascal `BeginThread` /
critical sections / `RTLEvent` / `threadvar` a working `TThreadManager` on
ESP-IDF FreeRTOS — without changing the freertos RTL stubs in FPCSource.

**Personality.** The opt-in complement. Default FPC policy on this target is
loud failure (`RunError 232` / exceptions) for Pascal threading; raw
`xTaskCreatePinnedToCore` remains the escape hatch. This package is for the
programmer who prefers Delphi/FPC idioms and accepts the FreeRTOS limits
(no join, stack sizes in bytes, TLS slots required in sdkconfig). It is
ESP-IDF-shaped (IDF 6.x symbols, `idfheap`, S3/S31 awareness), not a
generic FreeRTOS port dump.

**Usage.**

```pascal
uses idfheap, fthreads, sysutils;   { idfheap first; fthreads before classes }
```

Needs `CONFIG_FREERTOS_THREAD_LOCAL_STORAGE_POINTERS >= 1`. Demo:
`../examples/fpcthreads/`. Package notes: [`freertos-fpc/README.md`](./freertos-fpc/README.md).

### `esp_task.pp`

**Purpose.** Thin cdecl bindings for the FreeRTOS task + TLS surface
`fthreads` (and careful examples) need under IDF 6.x.

**Personality.** Minimal and honest. No full `task.h` mirror — only create /
delete / delay / suspend / resume / priority / current handle / TLS /
`taskYIELD`, plus `xTaskCreate` as pinned-with-`tskNO_AFFINITY`. Stack
depths are documented as **bytes** (ESP-IDF convention).

### `esp_semphr.pp`

**Purpose.** Mutex and binary semaphore wrappers that link against real
queue symbols (`xQueueCreateMutex`, `xQueueSemaphoreTake`, …).

**Personality.** The macro-buster. FreeRTOS `semphr.h` is mostly macros;
FPC cannot `external` those. This unit re-expresses them as Pascal inlines
over the symbols that actually exist in `libfreertos.a`.

### `fthreads.pp`

**Purpose.** Install a FreeRTOS-backed `TThreadManager` at unit init:
`BeginThread` → task, critical sections → mutexes, `RTLEvent` → binary
semaphores, `threadvar` → FreeRTOS TLS index 0.

**Personality.** The Delphi bridge. Adapted from ccrause's `fthreads` for
IDF 6.1 + `idfheap`; TLS blocks are allocated with raw `heap_caps_*` so
setup cannot re-enter Pascal `GetMem` before the TLS pointer exists. It
refuses to load if threading was already stub-touched (`ThreadingAlreadyUsed`).
`WaitForThreadTerminate` stays a non-join stub — FreeRTOS has no join;
apps sync with events/queues.

---

## `espatomics/` — ESP.Atomics sub-project

**Purpose.** A Free Pascal atomics suite for ESP-family SoCs: acquire/release
loads and stores, weak CAS, fetch-ops — with correct portable fallbacks —
without forcing callers to rewrite existing `Interlocked*` code.

**Personality.** The careful concurrent toolkit. Self-contained under
[`espatomics/`](./espatomics/) with its own requirements, design, and agent
rules. Hard constraints: new-API gains only; unmodified old code stays
correct after `uses espatomics`; zero adaptation burden. It is explicit
about ESP limits (e.g. PSRAM is not atomics-safe on S3 for control words).

Entry unit: `espatomics.pas` — unit-level leaves only (`ReadAcquire` /
`WriteRelease`, `AtomicExchangeAcqRel`/`SeqCst`, `Fetch*`,
`CompareExchangeWeak`). No uses clause, no class helper, no baseline unit.
Backends: Xtensa (S3), RV32A, and stock `Interlocked*` fallback.

| Doc | Content |
| --- | --- |
| [`espatomics/REQUIREMENTS.md`](./espatomics/REQUIREMENTS.md) | Constraints + problem examples |
| [`espatomics/DESIGN.md`](./espatomics/DESIGN.md) | Architecture / routing matrix |
| [`espatomics/IMPLEMENTATION.md`](./espatomics/IMPLEMENTATION.md) | File map, backends, how to extend |
| [`espatomics/AGENTS.md`](./espatomics/AGENTS.md) | Agent rules for this sub-project |

---

## L1/L2 naming grammar — bindings vs native units

Two unit kinds share `units/`, and the name tells them apart (FPC itself
uses the `c` prefix for C-library bindings: `cthreads`, `cmem`, `cwstring`):

| Layer | Name grammar | Nature | Units |
|---|---|---|---|
| L1 binding | `c_<C component short name>` | hand-converted C-header shadow: `cdecl; external` functions keep their C names; records are C-ABI-true (`{$packrecords C}`, `{$minenumsize 4}`, sizes verified against the C build) | planned: `c_bmgr`, `c_lvgl_adapter`, `c_lvgl` |
| L2 native | functional name, no `c_` prefix | Pascal-idiomatic service built on L1 (or on IDF/RTL directly): advanced records, value-semantics config, `esp_err_t` visible, no exceptions | `idfheap`, `fthreads` / `freertos-fpc`, `espatomics`; planned: `boarddisplay` |

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

### Planned display-chain units (not in tree yet)

**`c_bmgr` (L1)** — esp_board_manager header shadow: init/device lookup by
name, board info, display/touch device factories. Personality: flat C ABI,
whole-link the board-manager archives or the registry resolves nothing.

**`c_lvgl_adapter` (L1)** — esp_lvgl_adapter surface: init/start/lock,
display + touch registration, sleep/wake. Personality: config macros become
record-returning Pascal helpers; gated FEATURE blocks stay absent when the
sdkconfig compiled them out.

**`c_lvgl` (L1)** — LVGL 9.x working subset (screen/objects/label/button/
style/events), grown per need — not a full `lvgl.h` dump. Personality:
deliberately small; bakes v9 symbol facts (`lv_screen_active`, packed color).

**`boarddisplay` (L2)** — facade over the three devices + adapter so
`TBoardDisplay.Start` leaves `lv_screen_active()` live under
`UILock`/`UIUnlock`. Personality: one `uses` and a Start call instead of
hand-wiring L1.

---

## `esp-units.pas` root

The repo ships `units/` in reusable form; automation lives in `scripts/`
(`build.sh`, `run-qemu.sh`), the regression body in `tests/`.

| Directory | Content |
|---|---|
| `units/` | `idfheap` + `freertos-fpc/` + `espatomics/` |
| `units/freertos-fpc/` | ESP-IDF task/semphr bindings + `fthreads` |
| `units/espatomics/` | ESP.Atomics docs + sources (see its `AGENTS.md`) |
| `examples/` | hand-run unit demos (`examples/README.md`) |
| `tests/` | compiler verification programs (`tests/README.md`) |
| `scripts/` | build / QEMU / esp-emu / flash automation |
