# Test programs — compiler verification and demonstration on ESP32

This directory verifies and demonstrates what the FreePascal freertos target
can do on ESP32-family MCUs. Two groups:

- **t_/u_ programs** — a curated subset of the FPC trunk regression suite
  (`tests/webtbs`), renamed to descriptive names; each is a compiler-bug
  regression or an important-capability demonstration.
- **probe-*/programs** — this project's own capability probes (encoding
  services, IDF-heap routing) and the thread-contract demos in
  `thread-stubs/` (designed loud failures, kept out of the PASS/CRASH stats).
  Unit-API demonstrations live in `../examples/`, not in the suite.

Run: `./run-tests.sh` (all) or `./run-tests.sh 't_math*.pas'` (glob), from
`tests/`. Each program is cross-compiled with `../scripts/build.sh` and booted
under QEMU (15 s cap, `../scripts/run-qemu.sh`); the verdict is the *absence*
of `Guru|panic|Backtrace|Runtime error|SIGILL|LoadProhibited|StoreProhibited`
in the serial log, and the detail column shows the last program line (or
`exit: N` for the closing `_haltproc` line). Per-test logs: `<name>.clog`
(compile) and `<name>.qemu.log` (serial).

**Naming & provenance.** Webtbs regressions are renamed from their upstream
`tw<bugnr>` names to descriptive `t_<topic>_<what>.pas` (compile-only unit:
`u_`). Provenance is kept twice: a `{ webtbs provenance: trunk
tests/webtbs/tw<bugnr>.pas }` comment on line 1 of every renamed file, and the
mapping table below. `probe-*` / `idfheap-smoke` are this project's own,
named meaningfully from the start.

**Memory manager.** Every runtime-tested program (and the `thread-stubs/`
demos) has `idfheap` FIRST in its `uses` — the whole suite runs on the
IDF-pool manager and no program carries a static `-Ch` block (the toolchain's
`fpc.cfg` no longer contains `-Ch`). The compile-only files never reach QEMU.
The static heapmgr remains reachable with an explicit `-Ch65536` — see
`static-heap-repro/` for the only probe that needs it.

---

## Per-test catalog

Expected outcome for **silent** tests: no program output; clean boot and
(`exit: 0` from) a clean QEMU termination — that *is* the result these
regressions are for: they crash on the bug they guard.

| test (suitename) | purpose — what it exercises | expected outcome | pitfall |
|---|---|---|---|
| t_math_power | trunk tw1792 regression: `power(2,31)` overflow | `2.1474836480000000E+009`, exit 0 | — |
| t_math_infinity_qr_checks | `Writeln(Math.Infinity)` under `{$Q+}{$R+}` | `+Inf`, exit 0 | needs real Infinity constant, not folded (see removed tw16315b) |
| t_math_infinity_assign | plain `D := Infinity` assignment | silent, exit 0 | tw16315b sibling (const-fold range check) was removed, not fixed |
| t_math_isnan_bool | short-circuit fold `IsNan(d) or (d = 0)` | `TRUE`, exit 0 | — |
| t_math_min_mixed_types | `Min(Double, Extended)` overload resolution | silent, exit 0 | — |
| t_math_min_rangecheck | `0-Min(bytes)` under `{$Q+}` must not spuriously range-check | silent, exit 0 | — |
| t_math_roundto_currency | `currency` `RoundTo` (fixed-point rounding) | silent, exit 0 | — |
| t_math_tanh_bigargs | `tanh(-354/-355)` saturation (-1) | silent, exit 0 | — |
| t_range_div_subrange | negative `div` on a `1..MaxInt` subrange (no spurious range error) | silent, exit 0 | — |
| t_formatfloat_neg_zeropad | `FormatFloat('000.000',-1)` zero-padding of negatives | silent, exit 0 | was a crash on the old 3584-byte main-task stack — fixed by `CONFIG_ESP_MAIN_TASK_STACK_SIZE=8192`; don't shrink blink-s3 below that |
| t_formatfloat_thousands_sep | custom `ThousandSeparator` in `FormatFloat('#,0.00')` | `1000.00`, exit 0 | — |
| t_formatfloat_exponent | `FormatFloat('0e',-1)` exponent without digit count | silent, exit 0 | — |
| t_formatfloat_nan | `FormatFloat` of NaN | silent, exit 0 | — |
| t_format_funcresult | `Format('%s', [funcresult])` (array-of-const with function result) | silent, exit 0 | — |
| t_defaultformatsettings_copy | copy `DefaultFormatSettings` (record with strings) with `-Seh` | silent, exit 0 | compiled with `-Seh` in its own source-directive; don't drop that when editing |
| t_trim_variant | `Trim(empty variant)` (USysUtils variant hooks) | silent, exit 0 | — |
| t_sysutils_trim_static_char | `Trim(static char array)` — SysUtils on a non-AnsiString buffer | silent, exit 0 (single blank line of output possible) | — |
| t_stringhelper_join | `string.Join('&', ['ab','cd'])` (strutils/rtlconsts paths) | `ab&cd`, exit 0 | NORUN-style compile-only in trunk; here it also runs |
| t_types_case_longbool | `case longbool of true/false` with `-Sew` | `False`, exit 0 | also compiled `-Sew`; both flags intentional |
| t_datetime_to_timestamp | `DateTimeToTimeStamp(Now)` (whole SysUtils datetime stack) | silent, exit 0 | — |
| t_typinfo_enumcount | `GetEnumNameCount` (typinfo on enum RTTI) | silent, exit 0 | — |
| t_typinfo_getenumname | `GetEnumName` | silent, exit 0 | — |
| t_classes_minimal | minimal `uses classes` program — unit init/teardown sentinel | silent, exit 0 | **canary**: tears down Classes+SysUtils through the compiler-generated finalize table; first thing to break if init/finalize order regresses |
| t_classes_ifdeclared | `{$if declared(TObject)}` in objfpc mode | silent, exit 0 | uses `classes` → same teardown canary duty as t_classes_minimal |
| t_fgl_nested_specialize | `TFPGList<T>` specialization inside a class type | silent, exit 0 | — |
| t_generics_queue_capacity | `TQueue<Integer>` enqueue/dequeue churn w/ capacity bound | `19`, exit 0 | biggest per-test classic-heap churn of the pure tests; exercises `TList.Grow`'s ReAllocMem path |
| t_generics_implicit_specialization | implicit + explicit generic call | silent (compile-checked), exit 0 | — |
| t_generics_enum_list_decl | `TList<enum>` declaration | silent, exit 0 | — |
| t_generics_dictionary_recordkey | `TObjectDictionary<record,TObject>.ContainsKey` | silent, exit 0 | heaviest heap demand in the suite (≈2.6 KiB at init/teardown on the classic manager) — natural first suspect for OOM experiments |
| t_generics_comparer_enum | `TEqualityComparer<enum>.Default` interface plumbing | `Done`, exit 0 | — |
| t_generics_collections_tstack | ** moved demonstration** (from the toolchain workspace's fpc-hello): `Generics.Collections.TStack<record>` push/pop/extract/peek, record-with-strings `ToString` via `Format`, enumerator support | boot banner + `Ate a pancake (Pop): Pancake with meat`, `Ate a pancake (Extract): Pancake with curds`, `Last pancake: Pancake with cherry`, `Total pancakes: 3` + 3 enumerated lines + `Enumerated pancakes: 3`, exit 0 | terminal `Readln` of the desktop original removed (QEMU serial has no stdin — use `$MODE DELPHI`; no C-style `+=`) |
| u_generics_pubsub_events | generics Pub/Sub **unit** — compile-only capability proof | compile-only PASS ("no output") | deliberately has no `idfheap` in uses and never runs — do not "fix" that |
| t_nan_default_param_forward | NaN as default param + forward declaration | compile-only NORUN in trunk; here silent, exit 0 | — |
| t_execprocess_funcresult | `ExecuteProcess` with function-result arguments | silent, exit 0 | freertos `ExecuteProcess` is a stub no-op: expect no side effects, the test guards compilation + teardown only |
| probe-enc | TEncoding singleton memory + `IsStandardEncoding` guard (regression for the teardown UAF) | `TEncoding.Default @<3FCxxxxx> :` + hex dumps + `is standard : TRUE` + `SYSUTILS+CLASSES init ok, now exiting`, exit 0 | — |
| probe-idfheap | IDF capability probe: free sizes, largest block, 64 KiB `heap_caps_malloc` + free | `idf internal free=~369KB largest=~304KB`, `idf SPIRAM free=0B` (`0` = `CONFIG_SPIRAM` off), `idf alloc ok @<addr> (64KB)`, `idf free ok`, exit 0 | SPIRAM line prints `0` until PSRAM is enabled in the SDK project — that is a *fact to observe*, not a failure |

(The `idfheap` unit *demonstration* moved to `../examples/idfheap-smoke.pas`
— see `../examples/README.md`; it is not part of the suite runner.)

### `thread-stubs/` — designed-loud failures (outside the stats)

| program | purpose | expected outcome (intentional!) | pitfall |
|---|---|---|---|
| t_cs_noop.pas | critical-section stub is a correct no-op for one task | `cs ok ...`, no error | a PASS-looking program: it must NOT fail |
| t_event_waitfor.pas | `TEvent.Create` with a nil basic-event handle | `...as designed: ESyncObjectException` | do not "fix" its failure — it proves loudness |
| t_thread_create.pas | `TThread.Create` must not pretend to thread | `...as designed: Exception (TThread stub)` | same: loudness is the contract |

Run them manually (`../scripts/build.sh`, then `../scripts/run-qemu.sh` with a
shorter timeout); details in `thread-stubs/README.md`.

### `static-heap-repro/` — the mid-run manager hot-swap probe

`probe-idfmm.pas` installs an IDF-pool manager **mid-run** over an
initialized static heap — the one program structurally requiring `-Ch65536`
(its own README has the exact commands and expected output). Not part of the
default suite (the runner has no per-test flags).

### `trace-repro/` — heap-trace-ledger diagnostics

Compile-time incompatible with the normal RTL (needs a `-dfpc_HEAPTRACE`
RTL build; recipe in the toolchain workspace AGENTS.md §9 step 5 variant d).
See `trace-repro/README.md`.

---

## Removed as not applicable (do NOT re-add when syncing from trunk)

These two were the suite's only historical COMPFAILs; both fail at
*compile time* in code the target RTL never sees — a compiler/feature gap, not
an RTL problem, and therefore out of scope for this repo:

- `tw16315b` — `D := Infinity` under `{$ieeeerrors+}`: the trunk compiler's
  constant folding trips its own range check during folding. Compiler-internal
  (shared with i386/x86_64 folding paths); report upstream rather than patch.
- `tw3721` — `newstr/disposestr` + `HaltOnNotReleased` (`-gh` debug heap):
  heaptrc is not built for the xtensa-freertos target (missing-unit feature
  gap).

---

## Current state

Last full run: **36 PASS / 0 CRASH / 0 COMPFAIL** (2026-10-23, verified from
this repo path: 33 webtbs programs + `probe-enc` + `probe-idfheap` + the
moved `t_generics_collections_tstack` demo; `u_generics_pubsub_events`
compile-only; the `idfheap` unit demo runs as `../examples/idfheap-smoke.pas`
outside the runner). Historical root-cause notes below are kept as the
debugging record:

| Group | Tests | Status / root cause |
|---|---|---|
| math, SysUtils, TypInfo, Types, fgl (pure) | converged to PASS | `_haltproc exit code: 0` on every one |
| **Classes exit-teardown bug — SOLVED** | t_classes_minimal, t_classes_ifdeclared, t_generics_enum_list_decl, t_generics_queue_capacity, t_generics_implicit_specialization, t_generics_dictionary_recordkey, t_generics_comparer_enum | **Root cause in the compiler, not the RTL**: `ncpuutil.pas` generated `FPC_FINALIZE_FUNC_TABLE` iterating init/finalize entries *forward*, so finalization ran in the *same* order as initialization. SysUtils' `TEncoding` class destructor freed+unregistered the standard-encoding singletons *before* Classes' teardown; `TStrings.Destroy`'s `IsStandardEncoding(FDefaultEncoding)` guard then returned FALSE against the emptied list and **freed the already-dead `TEncoding.Default` singleton** (use-after-free, proven by the heapmgr trace ledger in `trace-repro/`: the singleton's chunk freed early, merge rewrites zeroing its VMT slot, `EXCVADDR 0x30`). Fix: emit the finalize list in reverse init order (`compiler/xtensa/ncpuutil.pas`, toolchain patch `xtensa-04-finalize-order.patch`). All seven PASS. |
| main-task stack too small | t_formatfloat_neg_zeropad | **FIXED** — IDF `CONFIG_ESP_MAIN_TASK_STACK_SIZE` raised 3584 → 8192 in the SDK project (`blink-s3/sdkconfig.defaults`, rebuilt); runs clean. |
| missing widestringmanager init — SOLVED | probe-idfmm surfaced it (see `static-heap-repro/`) | freertos sysutils never called `InitInternational`, so the `widestringmanager` compare/text procs stayed nil; `AnsiCompareStr/Text`, `AnsiStrComp`, and — via `TStringList.DoCompareText` — every `TStringList.Sort`/case-insensitive `Find` did `callx8` through a nil pointer (`InstrFetchProhibited`, PC=0). Fix in `rtl/freertos/sysutils.pp` (initialization calls `InitInternational`, same as unix/os2/amicommon), toolchain patch `freertos-03-sysutils-initinternational.patch`. The suite had no coverage of those paths — the memory-manager probe was the discoverer. |
| not applicable, removed (see above) | tw16315b / tw3721 | compile-level trunk limits, removed rather than carried as permanent COMPFAILs. |

**Heap demand of the suite** (measured with a `-dfpc_HEAPTRACE` RTL build in
the toolchain workspace: the heapmgr instrumentation prints `PEAK <bytes>
LIVE <bytes>` at exit): worst concurrent usage across all runnable tests is
**2648 bytes** (`t_generics_dictionary_recordkey`), runners-up 2404
(`t_generics_queue_capacity`), 2284 (`t_generics_implicit_specialization`,
`t_generics_enum_list_decl`), 1804 (`t_generics_comparer_enum`), 1188
(`t_trim_variant`), 704 (`t_classes_minimal`/`t_classes_ifdeclared`/
`probe-enc` — the Classes baseline). Pure math/fgl tests peak at 112–136
bytes (`consoleio`'s console write buffer). `LIVE` is 0 on every test at
exit, i.e. teardown frees everything. These numbers are from the static-heap
era; allocation volumes are manager-independent and the suite now allocates
the same sizes from the IDF pool, which has ~340 KiB free at program start.

**Stub-threading**: no test in the top-level suite reaches RTL thread stubs
(zero matches for `TThread|BeginThread|Synchronize|TEvent|WaitFor|Critical`
in the sources; no `NoThreadError` in any log). The threading-RTL contract
("unit init passes, explicit thread use fails loud") is demonstrated by
`thread-stubs/`, which intentionally shows *designed* failures and is
therefore kept out of the PASS/CRASH stats.

**`idfheap` (now `../units/idfheap.pp`) — production IDF-heap manager**
(compiles suite-wide, demonstrated by `../../examples/idfheap-smoke.pas`):
installs a `heap_caps_*`-backed `TMemoryManager` at unit init; every suite program opts
in with exactly one line (`uses idfheap` FIRST), so every allocation from the
first unit init onward (sysutils/classes: ~27 KB by init time) plus the
program's own data lives in IDF's `MALLOC_CAP_8BIT|DEFAULT` pool; `-Ch` is
irrelevant on this path. API docs: `../units/README.md`. Key details baked
into the unit, all hit during bring-up:

- `uses heapmgr` inside idfheap is load-bearing: FPC initializes used units
  before their users, so without it heapmgr would be reached via sysutils'
  own uses AFTER idfheap's init and its `SetMemoryManager(static)` would
  overwrite the IDF manager (order pinned: heapmgr → idfheap → sysutils →
  typinfo → classes);
- FPC's manager `ReAllocMem(var p; Size)` must WRITE `p` in place (the global
  `ReAllocMem` wrapper only forwards the var); `TFPList.SetCapacity` depends
  on it (`ReallocMem(FList, n)` with FList=nil must allocate AND update
  FList) — the naive `result := realloc(p, …)` without `p := result` crashes
  `TList.Insert` with `FItems=nil` (`StoreProhibited`);
- ownership order: static-block pointers must route to the static manager
  even for `Size = 0` (a pre-swap-owned `FList` reaches teardown's
  `SetCapacity(0)` → `ReAllocMem(ptr,0)` → free) — else IDF aborts with
  `assert failed: <cached disabled>`;
- failure policy mirrors heapmgr: `nil` if `ReturnNilIfGrowHeapFails` was set,
  else `RunError(203)`;
- `GetFPCHeapStatus`/`GetHeapStatus` return real pool numbers
  (from `heap_caps_get_info`).

Copied programs are trunk bug-regressions whose `uses` only reference units
available for freertos (system, math, sysutils, classes, fgl, typinfo, types,
generics.*); about 429 further webtbs candidates exist in trunk if the suite
is to be expanded.
