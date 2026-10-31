# Design — ESP.Atomics (`espatomics`)

## Philosophy

On weak-memory ESP SoCs, stock `System.SyncObjs.TInterlocked` tends toward
full barriers or interrupt masking — costly on hot dual-core paths. This
unit uses an FPC **class helper** on `TInterlocked` to:

- **pass through** baseline ops so unmodified call sites keep old
  behaviour;
- **shadow** selected `UInt32` hot-path ops with ISA inline sequences;
- **extend** with acquire/release, weak CAS, and `TAtomicFlag` for new
  code.

Zero call overhead on the dedicated backends: backends are `$I` textual
includes into one compilation unit (no backend-unit call boundary, no
virtual dispatch). Assembler primitives cannot be inlined across units in
FPC (`compiler/ncgflw.pas`); keeping them in-unit is mandatory for the
zero-overhead claim.

## Routing matrix

| Class | Examples | Strategy |
| --- | --- | --- |
| Pass-through | `Increment` / `Decrement` / `Add` / `And` / `Or` / `Xor`, Int64 read/write | Unchanged RTL behaviour for old call sites |
| Shadow | `Exchange` / strong `CompareExchange` on `UInt32` | Hardware inline where the backend supports it (e.g. Xtensa `S32C1I`) |
| Extension | `ReadAcquire` / `WriteRelease` (incl. `Pointer`), `CompareExchangeWeak`, `Fetch*`, `TAtomicFlag` | New APIs for new code only |
| Not provided | `atomic_init` / `is_lock_free` | Embedded defaults; no runtime tax |

Pass-through exists so enabling this unit never retargets unmodified call
sites onto a different ordering contract. Shadowing is limited to
`UInt32` (and related) helpers that new/rewritten hot paths can opt into
by type; extension APIs are never selected by old call sites.

## ISA backends and host fallback

| Target | Memory model | Representative primitives |
| --- | --- | --- |
| Xtensa (ESP32 / S3) | Weak | Acquire: `L32I` then `MEMW`; release: `MEMW` then `S32I`; CAS / exchange via `S32C1I` (`SCOMPARE1`) |
| RV32A (C3 / C6 / S31 when `CPURV_HAS_ATOMIC`) | RVWMO | Acquire/release `fence`; `amoswap.w.aqrl` / `amo*.w.aqrl`; weak CAS via `lr.w` / `sc.w` |
| ARM32 (`LDREX` + `DMB`) | Weak | `LDREX`/`STREX` retry loops; `DMB` for acquire/release RMW |
| Host / other (stock) | RTL of that target | Route through qualified `System.Interlocked*` (full-barrier RTL semantics — not the dedicated acquire/release contract). Qualification avoids helper recursion on host. |

Compile-time selection is a single `$I` arm in `espatomics.pas` (see
[`IMPLEMENTATION.md`](./IMPLEMENTATION.md)). One source tree, no runtime
backend registry.

## Selected layout: conditional implementation includes

| File | Role |
| --- | --- |
| `espatomics.pas` | Unit shell; selects one backend `$I` |
| `espatomics_interface.inc` | `TInterlockedEsp`, `TAtomicFlag` declarations |
| `espatomics_impl.inc` | Architecture-independent method bodies |
| `espatomics_backend_xtensa.inc` | FreeRTOS Xtensa |
| `espatomics_backend_rv32a.inc` | FreeRTOS RV32 with `CPURV_HAS_ATOMIC` |
| `espatomics_backend_arm32.inc` | FreeRTOS ARM with `LDREX`/`DMB` |
| `espatomics_backend_stock.inc` | Direct `System.Interlocked*` fallback |
| `freertosinterlocked.pas` | FreeRTOS-only 32-bit `TInterlocked` baseline (RTL `SyncObjs` gap) |

## Rejected layouts

| Layout | Why rejected |
| --- | --- |
| Backend unit owns `TInterlockedEsp` methods | FPC requires method bodies in the declaring unit |
| Facade → `inline` routines in backend units | Assembler routines are not inlined across units |

## Uses-clause rule

Put `espatomics` **after** `SyncObjs` (or rely on FreeRTOS
`freertosinterlocked` as the baseline). Helper shadowing depends on
declaration order.

## Internal DRAM for atomics-backed state

ESP32-S3 external PSRAM does not support `S32C1I`. Lock-free queue heads,
counters, and `TAtomicFlag` storage must be **static/global (internal
DRAM)** or allocated with `MALLOC_CAP_INTERNAL`. Atomics on PSRAM →
`StoreProhibited`. Normative wording:
[`REQUIREMENTS.md`](./REQUIREMENTS.md).

## Relation to parent repo

This directory is a **self-contained sub-project** under
`esp-units.pas/units/espatomics/`. Parent docs point here; they do not
duplicate the API. Sources and docs for atomics evolve in this directory.
Requirements: [`REQUIREMENTS.md`](./REQUIREMENTS.md). File-level map:
[`IMPLEMENTATION.md`](./IMPLEMENTATION.md). Agent entry:
[`AGENTS.md`](./AGENTS.md).
