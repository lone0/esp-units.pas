# ESP.Atomics architecture-split prototype

This directory is isolated from `src/`; it changes neither the existing unit nor
its build. `TInterlockedEsp` provides `UInt32` fetch operations, acquire loads,
release stores, weak compare-and-exchange, and `TAtomicFlag`. FreeRTOS builds
also use `freertosinterlocked.pas` for a 32-bit `TInterlocked` baseline that
otherwise would come from `SyncObjs`; 64-bit operations remain deferred.

## Selected design: conditional implementation includes

`espatomics_interface.inc` defines `TInterlockedEsp` and `TAtomicFlag`.
`espatomics_impl.inc` contains their architecture-independent method bodies.
The FreeRTOS-only `BitTestAndSet` and `BitTestAndClear` helper methods use
`FetchOr` and `FetchAnd`, respectively, to return the previous bit value
atomically. `espatomics.pas` textually includes one backend, selected at compile
time:

| Backend | Selection |
| --- | --- |
| `espatomics_backend_xtensa.inc` | FreeRTOS Xtensa |
| `espatomics_backend_rv32a.inc` | FreeRTOS RV32 with `CPURV_HAS_ATOMIC` |
| `espatomics_backend_arm32.inc` | FreeRTOS ARM with `CPUARM_HAS_LDREX` and `CPUARM_HAS_DMB` |
| `espatomics_backend_stock.inc` | all other builds; direct RTL `System.Interlocked*` fallback |

This is zero abstraction overhead: `$I` is textual inclusion, so the selected
backend primitives and public helper methods belong to the same compilation
unit. There is no backend-unit call boundary and no virtual dispatch.

The ARM32 backend is for ARM targets that expose word exclusive operations and
`DMB`; it uses `LDREX`/`STREX` retry loops and `DMB ISH` to implement
acquire-release read-modify-write operations, acquire loads, and release
stores. It excludes ARM targets without those compiler capability symbols
rather than silently producing a non-atomic path.

The stock fallback calls the global `System.Interlocked*` primitives directly;
it does not require `SyncObjs` or a bridge unit. Its ordering is the stock RTL
ordering supplied for the target, not the explicit acquire/release contract of
the dedicated hardware backends.

## Rejected layouts

| Layout | Result |
| --- | --- |
| Backend unit implements `TInterlockedEsp` methods | Not possible: Free Pascal requires a type's method implementations to be in the declaring unit. |
| Facade calls ordinary routines in backend units marked `inline` | Not a no-overhead guarantee. The FPC compiler source explicitly documents that assembler routines cannot be inlined (`compiler/ncgflw.pas`), so the ISA primitives retain call boundaries. |
| Conditional implementation includes | Selected: direct code in one unit, preserving existing helper declarations and guaranteeing no abstraction calls. |

The ARM RTL supplied with the adjacent FPC checkout establishes the compatible
`LDREX`/`STREX` syntax and guards those instructions with
`CPUARM_HAS_LDREX` (`rtl/arm/arm.inc`, `rtl/arm/thumb2.inc`).
