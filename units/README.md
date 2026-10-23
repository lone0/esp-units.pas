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
- no 64 KiB `-Ch` block wastes BSS (the symbol shrinks to 4 bytes),
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
  also uses no idfheap and relies on `-Ch`) cannot be freed through this
  manager — that crossing is only meaningful for hot-swap experiments and
  is deliberately not supported here.

---

## `espatomics/` — atomics for ESP family SoCs (dual-core safe)

**Problem it resolves.** The freertos RTL's `TCriticalSection`/event API is
a single-task no-op stub (see the repo tests `tests/thread-stubs/`), and
`SyncObjs`-style `TInterlocked` does not exist for this target. With real
freeRTOS tasks on two cores you therefore had no Pascal-native way to
update shared state safely. `espatomics` provides machine-locked atomics
with **zero call-open overhead**: the selected backend is textually
included (no virtual dispatch, no backend-unit call boundary).

### `freertosinterlocked.pas` — the `TInterlocked` baseline

Renames/bridges the classic Interlocked operations the RTL lacks on
freertos. Class-static, thread-safe for shared 32-bit state:

```pascal
uses freertosinterlocked;
var Counter: LongInt = 0;
begin
  TInterlocked.Increment(Counter);
  TInterlocked.Add(Counter, 10);          { returns the new value }
  if TInterlocked.CompareExchange(Counter, 42, 10) = 10 then ...
    { Only when it was 10: set 42; returns the previous value }
end.
```

Overloads: `LongInt` (Add, Increment, Decrement, Exchange,
CompareExchange±out Succeeded), `Single` (bits exchanged), `Pointer`,
`TObject`, and a generic `Exchange<T>/CompareExchange<T>` for any
pointer-sized type. 64-bit operations: deferred (no 32-bit SoC guarantee).

### `espatomics.pas` — `TInterlockedEsp` (class helper on `TInterlocked`) + `TAtomicFlag`

```pascal
uses espatomics, freertosinterlocked;
```

`uses espatomics` gives `TInterlocked` the extended API below. The unit
picks its backend at compile time: Xtensa (`s32c1i` compare-and-swap — this
repo's S2/S3 target), RV32A (C-series, e.g. C3 — `CPURV_HAS_ATOMIC`),
ARM32 (`LDREX/STREX` + `DMB`), and falls back to the stock RTL
`System.Interlocked*` elsewhere. The dedicated hardware backends pair
`memw` barriers with explicit acquire/release semantics.

```pascal
{ TInterlockedEsp class helper }
class function FetchAdd(var Target: UInt32; Value: UInt32): UInt32;
class function FetchSub / FetchAnd / FetchOr / FetchXor ...          (same shape)
  { all return the PREVIOUS value, like C's atomic_fetch_* }
class function ReadAcquire(var Target: UInt32): UInt32;              (+ LongInt, Pointer)
class procedure WriteRelease(var Target: UInt32; Value: UInt32);     (+ LongInt, Pointer)
class function CompareExchangeWeak(var Target: UInt32; Value, Comparand: UInt32;
  out Observed: UInt32): Boolean;                                    (+ LongInt, Pointer)
class function BitTestAndSet(var Target: LongInt; BitOffset: TBitOffset): Boolean;
class function BitTestAndClear(var Target: LongInt; BitOffset: TBitOffset): Boolean;
```

Example — publish a result once with a release store, observe it with an
acquire load (crossing between two freeRTOS tasks, no locks involved;
`var Published` must be typed exactly `Pointer` — a typed-pointer variable
cannot be passed to a `var Pointer` parameter, the casts happen at the
call sites). Externals per the threading notes in AGENTS.md:

```pascal
type
  TResult = record
    Sum: LongInt;
  end;
  PResult = ^TResult;

var
  Published: Pointer = nil;        { the handoff slot }

procedure Producer(arg: pointer); cdecl;
var
  R: PResult;
begin
  New(R);
  R^.Sum := 42;                                  { (1) payload writes }
  TInterlocked.WriteRelease(Published, Pointer(R));  { (2) publish: (1) visible }
  vTaskDelete(xTaskGetCurrentTaskHandle());      { self-delete when done }
end.

procedure Consumer(arg: pointer); cdecl;         { other core or same core }
var
  Seen: PResult;
begin
  repeat
    Seen := PResult(TInterlocked.ReadAcquire(Published)); { acquire reads (2) }
    if Seen = nil then vTaskDelay(10);           { idle between polls }
  until Seen <> nil;
  writeln('sum = ', Seen^.Sum);                  { guaranteed to see 42 }
end.
```

### `TAtomicFlag` — a one-word spin lock

```pascal
var F: TAtomicFlag;
begin
  F.Init;                            { or rely on a zero-initialized global }
  while not F.TestAndSet do ;        { True = acquired; spin until acquired }
  { ... short critical section ... }
  F.Clear;                           { release — wakes nobody; pollers spin }
end.
```

Problem it resolves: protecting a *short* window between two freeRTOS
tasks (pinned on the two cores) without linking any FreeRTOS primitive —
`TCriticalSection` in this RTL is a no-op, and taking an `xSemaphore*`
external is often overkill. Keep the section short; pollers burn their
own core. For long waits use `xQueueReceive`-style blocking or FreeRTOS
semaphore externals instead (see `tests/thread-stubs/` and the AGENTS.md
threading section).

### `idfheap` — reference programs

`../examples/idfheap-smoke.pas` is the worked demonstration
(GetMem/sorted TStringList/50 000-slot dynarray through the IDF pool; output
documented in `../examples/README.md`). Inside the suite, *every* runtime
program exercises it implicitly (it is first in `uses` everywhere), and
`tests/probe-idfheap.pas` reports the raw `heap_caps_*` capabilities.
Per-test details: `tests/README.md`.

`espatomics` deliberately ships **without tests in this repo** — it is
maintained-and-verified as-is (compiled + hardware-verified in the sibling
prototype from which it was copied verbatim); changes and tests for it
belong to the upstream prototype, not this tree (repo `AGENTS.md` §1).

---

## `esp-atomics.pas` root

The repo ships `units/` in reusable form; automation lives in `scripts/`
(`build.sh`, `run-qemu.sh`), the regression body in `tests/`.
Where to look for what:

| Directory | Content |
|---|---|
| `units/` | the bridge to the IDF memory manager (`idfheap`) and the atomic operations library (`espatomics`) |
| `units/espatomics/DESIGN.md` | backend-selection rationale (why `$I` include, why not facade units) |
| `tests/` | compiler verification + demonstration programs (`tests/README.md` per test) |
| `scripts/` | build / QEMU / flash automation, SoC-parameterized |
