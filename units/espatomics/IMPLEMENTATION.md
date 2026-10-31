# Implementation — ESP.Atomics (`espatomics`)

## Build / uses

```pascal
uses
  {$IFDEF FREERTOS} freertosinterlocked {$ELSE} SyncObjs {$ENDIF},
  espatomics;
```

Compile as part of any FreeRTOS / host FPC program. Parent
`esp-units.pas/scripts/build.sh` already `-Fu`s every `units/*/`
subdirectory, so no special flag is required beyond a normal SoC build.

## File map

```
units/espatomics/
  AGENTS.md                      agent knowledge for this sub-project
  REQUIREMENTS.md                normative constraints + problem examples
  DESIGN.md                      architecture and routing matrix
  IMPLEMENTATION.md              this file
  espatomics.pas                 unit entry; backend $I selection
  freertosinterlocked.pas        FreeRTOS TInterlocked 32-bit baseline
  espatomics_interface.inc       public types / method decls
  espatomics_impl.inc            shared method bodies (Fetch*, BitTest*, …)
  espatomics_backend_xtensa.inc  S32C1I / MEMW paths
  espatomics_backend_rv32a.inc   AMO / LR-SC / FENCE paths
  espatomics_backend_arm32.inc   LDREX / STREX / DMB paths
  espatomics_backend_stock.inc   System.Interlocked* fallback
```

## Backend selection (`espatomics.pas`)

| Condition | Backend | Hot primitives (see also DESIGN.md) |
| --- | --- | --- |
| `FREERTOS` + `CPUXTENSA` | xtensa | `S32C1I`, `MEMW`, `L32I`/`S32I` |
| `FREERTOS` + `CPURV_HAS_ATOMIC` | rv32a | `amo*.w.aqrl`, `lr.w`/`sc.w`, `fence` |
| `FREERTOS` + `CPUARM_HAS_LDREX` + `CPUARM_HAS_DMB` | arm32 | `LDREX`/`STREX`, `DMB` |
| else | stock | qualified `System.Interlocked*` |

## Public surface (summary)

See `espatomics_interface.inc` for the authoritative list. Highlights:

- `TAtomicFlag`: `Init`, `TestAndSet`, `Clear` (record storage is
  `UInt32`; the API is a latch, not a packed 1-byte C `atomic_flag`)
- `TInterlockedEsp` helper: `FetchAdd/Sub/And/Or/Xor`, `ReadAcquire`,
  `WriteRelease`, `CompareExchangeWeak` (LongInt / UInt32 / Pointer),
  FreeRTOS-only `BitTestAndSet` / `BitTestAndClear`

## Extending

1. Keep requirements in `REQUIREMENTS.md` true (especially old-code
   pass-through).
2. Prefer new methods on the helper or on `TAtomicFlag` over changing
   pass-through behaviour.
3. New ISA: add `espatomics_backend_<name>.inc` and one `{$ELSEIF}` arm in
   `espatomics.pas`; do not introduce a separate backend unit.
4. Storage for atomics remains **internal RAM** on ESP32-S3 (see
   requirements).

## Verification status

Copied and checksum-verified from the prototype at import time. Suite
tests for this unit are **not** in the parent `tests/` runner yet; add
them under this sub-project or as parent examples when requested.
