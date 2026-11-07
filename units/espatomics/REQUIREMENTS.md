# Requirements — ESP.Atomics (`espatomics`)

This sub-project supplies a Free Pascal atomics suite for ESP-family SoCs
(and portable fallbacks). Requirements are normative for design,
implementation, and any future tests.

## Design constraints (hard)

1. **New-API gains only.** Performance from acquire/release loads/stores,
   weak CAS, and `TAtomicFlag` applies only to code written against those
   new entry points.
2. **Unmodified old code stays correct.** After `uses espatomics`, any
   unchanged call sites (including third-party units) must keep their
   previous concurrent behaviour and correctness.
3. **Zero adaptation burden.** Enabling this unit must not require edits
   to existing callers for the unit to compile or run correctly.

## Problem examples (acceptance themes)

All solutions and tests must show both **correctness** (no tearing /
races on the described contracts) and **efficiency** (no unnecessary
full barriers or bit-shift tax on the hot path) for:

1. **MPMC counter / slot allocation** — unique indices under concurrent
   increment; prefer `FetchAdd` returning the previous value.
2. **SPSC / MPMC ring buffer** — consumer never observes a partially
   published element; prefer the unit-level `ReadAcquire` /
   `WriteRelease` primitives over full barriers.
3. **ISR → task one-shot notify** — no blocking locks in the ISR;
   `TAtomicFlag` for a one-byte latch without 32-bit shift/mask tax.
4. **RCU-style config publish** — readers see only complete old or
   complete new state; prefer `ReadAcquire` / `WriteRelease` on
   `Pointer` (unit-level procedures with pointer overloads — not a
   separate `ReadAcquirePtr` API).

## Hardware / memory constraints

- **PSRAM is not atomics-safe on ESP32-S3.** Control words, counters, and
  `TAtomicFlag` storage must live in **internal DRAM** (static/global or
  `MALLOC_CAP_INTERNAL`). Atomic ops on PSRAM → `StoreProhibited`.
- Xtensa (ESP32 / S3): weak memory; acquire ≈ `L32I`+`MEMW`, release ≈
  `MEMW`+`S32I`, CAS/exchange via `S32C1I`. Measured on S3 silicon
  (2026-10-31, see DESIGN.md "Empirical memory ordering"): plain
  store→load passes the Dekker/SB litmus with no observable reordering
  on both SRAM and PSRAM — MEMW stays mandatory because the Xtensa
  architecture guarantees nothing without it, and other silicon differs.
- RISC-V with A extension (C3 / C6 / S31 when `CPURV_HAS_ATOMIC`): RVWMO;
  `fence` + `amo*.w.aqrl` / `lr.w`/`sc.w` as applicable.
- Unit-level leaf primitives (2026-11-06): `ReadAcquire` /
  `WriteRelease` (UInt32 / LongInt / Pointer overloads) are unit-level
  procedures with C11 `atomic_load_explicit(memory_order_acquire)` /
  `atomic_store_explicit(memory_order_release)` semantics and **at most
  one call level** on dedicated backends. The `TInterlockedEsp` helper
  no longer carries acquire/release — it is FreeRTOS-only anyway.
- Host / other targets (no dedicated backend): `ReadAcquire` /
  `WriteRelease` degrade to the full-barrier RTL routines
  (`System.Interlocked*`; `lock cmpxchg` / `lock xchg` on x86). The
  degraded path is stronger than the acquire/release contract, never
  weaker. (C11 acquire/release ≠ seq_cst: on weak silicon it closes
  message passing, not the SB litmus — see DESIGN.md.)

## Non-goals

- Implementing `atomic_init` / `is_lock_free` runtime helpers.
- Replacing FreeRTOS mutexes/queues for general synchronization.
- Changing FPC RTL `SyncObjs` itself (this unit shadows via a class
  helper only).
