# AGENTS.md — `units/espatomics` (ESP.Atomics)

Self-contained atomics sub-project inside `esp-units.pas`. Read this before
changing anything here.

## Identity

- **Purpose:** high-performance atomics for ESP-family dual-core SoCs via a
  `TInterlocked` class helper + `TAtomicFlag`, with portable stock fallback.
- **Parent:** `esp-units.pas` (build/run scripts, `idfheap`, compiler suite).
  fpc / esp-idf remain external tools of the parent.
- **Docs (authoritative in this directory):**
  - [`REQUIREMENTS.md`](./REQUIREMENTS.md) — constraints and problem examples
  - [`DESIGN.md`](./DESIGN.md) — architecture / routing / rejected layouts
  - [`IMPLEMENTATION.md`](./IMPLEMENTATION.md) — file map and how to extend

## Ground rules

1. Honour the three hard constraints in `REQUIREMENTS.md` (new-API gains,
   old-code correctness, zero adaptation).
2. Do **not** move method bodies into separate backend units — `$I` includes
   only (zero-overhead contract).
3. Do **not** put atomics-backed state in PSRAM on ESP32-S3.
4. `uses` order: baseline (`freertosinterlocked` / `SyncObjs`) then
   `espatomics`.
5. Prefer extending the helper / `TAtomicFlag` over changing pass-through
   semantics of existing `TInterlocked` methods.
6. Parent repo scripts already `-Fu` this directory; do not hardcode SoC
   paths here.
7. Do not commit without an explicit user request (parent rule).

## Quick triage

| Symptom | Check |
| --- | --- |
| `StoreProhibited` on CAS / flag | Target in PSRAM → move to internal DRAM |
| Old code behaviour changed after `uses espatomics` | Pass-through broken — revert shadowing of that path |
| Infinite recursion on host | Stock backend must call `System.Interlocked*` with unit qualification |
| Missing `TInterlocked` on FreeRTOS | Need `freertosinterlocked` in the uses list |
| No acquire/release gain | Caller still on pass-through APIs — switch to `ReadAcquire` / `WriteRelease` |

## Out of scope here

- FPC RTL / freertos threading stubs (parent toolchain / FPC tree).
- `idfheap` and IDF link closures (parent `units/idfheap.pp` + scripts).
- Broad FreeRTOS task/queue design (escape hatch remains raw FreeRTOS
  externals at the application layer).
