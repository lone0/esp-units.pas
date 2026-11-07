# Design — ESP.Atomics (`espatomics`)

## Philosophy

On weak-memory ESP SoCs, stock `System.SyncObjs.TInterlocked` tends toward
full barriers or interrupt masking — costly on hot dual-core paths. This
unit uses an FPC **class helper** on `TInterlocked` to:

- **pass through** baseline ops so unmodified call sites keep old
  behaviour;
- **shadow** selected `UInt32` hot-path ops with ISA inline sequences;
- **extend** with acquire/release, weak CAS, and RMW fetch ops for new
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
| Extension | `ReadAcquire` / `WriteRelease` (incl. `Pointer`), `AtomicExchangeAcqRel`/`SeqCst`, `CompareExchangeWeak`, `Fetch*` | New APIs for new code only |
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
| Host / other (stock) | RTL of that target | Unit-level `ReadAcquire`/`WriteRelease` degrade to `System.Interlocked*` — full-barrier RTL routines (`lock cmpxchg` / `lock xchg` on x86) — plus the RMW primitives likewise. |

Compile-time selection is a single `$I` arm in `espatomics.pas` (see
[`IMPLEMENTATION.md`](./IMPLEMENTATION.md)). One source tree, no runtime
backend registry.

## Selected layout: conditional implementation includes

| File | Role |
| --- | --- |
| `espatomics.pas` | Unit shell; selects one backend `$I` |
| `espatomics_interface.inc` | Unit-level leaf declarations (ReadAcquire/WriteRelease, AtomicExchangeAcqRel/SeqCst, Fetch*, CompareExchangeWeak) |
| `espatomics_backend_rv32a.inc` | FreeRTOS RV32 with `CPURV_HAS_ATOMIC` |
| `espatomics_backend_stock.inc` | Direct `System.Interlocked*` degradation path |

## Rejected layouts

| Layout | Why rejected |
| --- | --- |
| Backend unit owns helper methods | FPC requires method bodies in the declaring unit |
| Facade → `inline` routines in backend units | Assembler routines are not inlined across units |

## Uses-clause rule

The unit takes NO uses clause on any target — no helper, no baseline
unit. The class-helper era (2026-11-05, superseded 2026-11-07): a
`TInterlockedEsp = class helper for TInterlocked` was meant to carry
cross-platform compatibility, but (a) helper methods can never be
1-call (cross-unit inline is refused three ways), (b) same-named
unit-level primitives create a self-recursion hazard inside helper
bodies, (c) the freertos baseline unit existed only to give the helper
something to extend. The unit-level direct-through design makes all of
that unnecessary; BitTestAnd* convenience died with the helper (it was
mask/or arithmetic, not an ordering primitive).

## Internal DRAM for atomics-backed state

ESP32-S3 external PSRAM does not support `S32C1I`. Lock-free queue heads,
counters must be **static/global (internal
DRAM)** or allocated with `MALLOC_CAP_INTERNAL`. Atomics on PSRAM →
`StoreProhibited`. Normative wording:
[`REQUIREMENTS.md`](./REQUIREMENTS.md).

## Instruction-cost isolation (`units/espatomics/cq_instrcost.pas`, 2026-11-05)

Same SPSC protocol as the ring benchmark, but every index access exists
in TWO shapes run back-to-back in one boot: INLINE (each access is a
basic asm block referencing the globals by Pascal name — zero calls,
disassembly-verified: 0 `jalr` in both inline functions) and CALL (the
circularqueue.pas helper shape, one call per access). 1M items per
variant. Per-item wall clock (1M items, both cores):

| shape | inline µs | call µs | call−inline (ns/item) |
| --- | --- | --- | --- |
| plain | 440 | 575 | 135 |
| full fence ×6/item | 486 | 678 | 192 |
| relacq (narrow fences ×6/item) | 498 | 853 | 355 |
| aqrl atomics ×6/item | 544 | 705 | 161 |
| lr/sc ×6/item | 545 | 699 | 154 |
| lock pair ×2/item | 547 | 827 | 280 |

Findings:

- **Pure instruction costs (inline deltas vs i-plain, 6 fence sites per
  item):** full `fence iorw,iorw` ≈ 8 ns, narrow `fence rw,w`/`fence
  r,rw` ≈ 10 ns — full ≈ narrow at this workload, as expected (the
  extra ordering strength costs nothing when there is nothing else to
  order). `amoswap.w.aqrl`/`lr.w.aq` premium ≈ 17 ns per index access.
  A lock acquire+release pair ≈ 53 ns per item. Fence cost is dominated
  by waiting for the in-flight operations it must order — the pmq bits
  are a filter, and when the filtered set equals the actual outstanding
  set, narrowing buys nothing. Both fence shapes here are in fact
  OVER-fenced by 2 fences/item: the own-cursor loads (producer reading
  Head, consumer reading Tail) need no acquire — only the
  opposite-core-published cursor does. Minimal correct shape is 4
  fences/item; ReadAcquire should only be used on the other core's
  published cursor.
- **The espatomics wrapper tax is ~297 ns/item (≈50 ns ≈ 12 cycles per
  access):** c-relacq − i-relacq = 355 ns/item of which only ~58 ns is
  fence work — the remaining ~83% is the class-helper call wrapping
  (two stack frames + spills, ~13–15 instructions per access, matching
  the disassembly). This confirms and quantifies the circularqueue
  finding: on hot paths, prefer the fused/inline shape or the aqrl
  atomics; the unit's acquire/release is for API compatibility and
  non-hot callers.
- **FPC inline-asm pitfalls hit and fixed here:** (1) an `out`
  parameter is passed by REFERENCE — `sw t1, Value` in asm overwrites
  the pointer slot instead of the caller's variable (symptom: consumed
  bytes matched the expected sequence at exactly 1/256 ≈ random;
  correct form is `lw t2, Value; sb t1, 0(t2)`); (2) standalone unused
  pad arrays are smartlink-stripped (see the ring benchmark).
- **FPC 3.3.1 riscv32 atomics inventory (system.o disassembly):** the
  compiler-level atomics (`fpc_atomic_xchg_32` → `amoswap.w`,
  `fpc_atomic_cmp_xchg_32` → `lr.w`+`sc.w` retry, `fpc_atomic_add/dec_32`
  → `amoadd.w`) emit NO aq/rl bits — pure atomicity, no ordering. The
  RTL offers only three call-based barriers (ReadBarrier = `fence
  ir,ir`, ReadWriteBarrier = `fence iorw,iorw`, WriteBarrier = `fence
  ow,ow`) and no acquire-load routine. Net: on stock FPC there is NO
  construct that emits `lr.w.aq` — acquire semantics require inline
  asm at the access site, a nostackframe asm leaf routine, or a fence
  after a plain load. This unit's `lr.w.aq`/`amoswap.w.aqrl` backends
  exist precisely to fill that gap. A direct probe (external-name
  declaration of the mangled implementation symbols) confirms the
  single-layer shape IS available from unit callers: calling
  `HwReadAcquire`/`HwWriteRelease` directly = exactly one call to the
  primitive, same shape as AtomicCmpExchange's lowered call. Making
  them public API (interface declarations, gated on the backend
  defines) would give hot-path callers the single-layer form without
  inline asm — at the cost of committing the Hw* names as public API. CAS probe (rtl/riscv32/riscv32.inc
  + call-site disassembly): `System.AtomicCmpExchange`/`AtomicExchange`
  are ONE call straight to `fpc_atomic_cmp_xchg_32`/`xchg_32`
  (`lr.w`+`sc.w` retry / `amoswap.w`, no aq/rl);
  `System.InterlockedCompareExchange`/`InterlockedExchange` are TWO
  calls (a frame-building wrapper first). Neither is inlined at the
  call site — asm routines never are.
- **Why the old helper shape could never be better than a call**
  (measured 2026-11-05, FPC 3.3.1 riscv32, minimal-repro + `-vd` log):
  cross-unit inlining is refused when an inline body references private
  symbols or contains a call, and assembler routines are never inlined.
  Net: any unit-provided acquire/release is ≥1 real call per access from
  other units — which is why the 2026-11-06 direct-through redesign made
  the public `ReadAcquire`/`WriteRelease` the assembler leaves themselves
  (exactly 1 call) instead of helper wrappers around private leaves.

## SPSC ring benchmarks (superseded program, 2026-11-03 / 2026-11-05)

Two generations of a multi-variant SPSC ring benchmark lived in
`examples/circularqueue.pas` (removed 2026-11-06; the 3-mode demo
`demos/circularqueue.pas` supersedes it). Condensed findings — the
historical numbers predate the 2026-11-06 API direct-through.

Second generation (stock intrinsics only, 1M items/variant, S31 Mosaico):

| method | layers | items/s | checksum |
| --- | --- | --- | --- |
| asm (0 calls: inline `fence iorw,iorw` blocks) | 0 | **2.23–2.31 M** | ok |
| barrier (4 RTL barrier CALLS/item) | 4 calls | **2.18–2.20 M** | ok |
| atomic (barriers + 2 `AtomicExchange` calls) | 6 calls | **1.93–1.98 M** | ok |
| atomic-nobar (atomic only, no barriers) | 2 calls | **1.98 M** | ok¹ |
| plain (bare assignments) | 0 calls | **LIVELOCK** | — ² |

¹ atomic-nobar completing with clean checksums on THIS silicon is the
  TSO-like behaviour measured before — it is NOT safe: RVWMO permits
  failure, and the Dekker experiment below shows this exact model class
  violating. Do not ship atomic-nobar shapes.
² plain livelocks INDEFINITELY (2.5 min+ observed, zero progress): the
  consumer enters the empty state and re-reads its own stale cached copy
  of Head forever — nothing else touches memory, so the line is never
  refreshed. A real `vTaskDelay(1)` sleep did not make progress either
  (sleeping does not evict the line). Completion elsewhere is eviction
  luck, not correctness.

Reading: with correct code, internal-SRAM SPSC on S31 runs at 2.0–2.3
M items/s and the layer count is nearly free (0 calls 2.23 M vs 4 calls
2.18 M — ~2%), EXCEPT the then-current two-layer helper wrap
(1.18–1.31 M, −40%, ≈297 ns/item — quantified in the cq_instrcost
section above). The RTL barrier routine cost is invisible at pipeline
scale; the layer tax is what matters. Bare-assignment SPSC on S31 can
livelock permanently in the empty state — the "expected failure" of
plain is stronger than corruption: it is a system-level hang.

Over-protection ledger — per litmus family, what the stock barrier set
(ir,ir / ow,ow / iorw,iorw only) forces, and what primitive would
remove the over-strength:

| family/case | precise order needed | C11 primitive | FPC forced to | missing primitive that removes it | over-strength cost |
| --- | --- | --- | --- | --- | --- |
| SB/Dekker (W→R) | `fence w,r` | `atomic_thread_fence(seq_cst)` → `fence rw,rw`; or exchange(seq_cst) → `amoswap.w.aqrl` | `System.ReadWriteBarrier` call (`fence iorw,iorw` ⊇ w,r) | **`fence w,r`** as a System primitive, or native aqrl-store emission | fence-bit delta ≈ 0 (full ≈ narrow, measured); call layer 1 × ~45 ns per Dekker point |
| MP (release store + acquire load) | W→W, R→R, R→W ×2 | `atomic_store_explicit(release)` + `atomic_load_explicit(acquire)` → `fence rw,w; sw` / `lw; fence r,rw` | 4 barrier CALLS/item (2 precise: ow,ow / ir,ir; 2 over-strong: iorw,iorw ⊇ r,w) | **`fence r,w` + `fence rw,w` / `fence r,rw` as System primitives**, or macro-inlined fences (0 calls) | fence-bit delta ≈ 0; call layers 4 × ~45 ns ≈ 180 ns/item ≈ −9% (barrier variant measured 2.18 M) |
| LB (R→R + R→W) | same as MP minus one point | same acquire/release pair | 2 barrier CALLS/item (1 precise ir,ir; 1 over-strong) | `fence r,w` primitive | ≈ 0 bits; 2 calls × ~45 ns ≈ −5–9% |
| WRC / ISA2 (3-thread cumulativity) | release A-cumulativity across cores | same pair — C11 release is A-cumulative | same RTL barriers (cumulativity preserved when narrowing) | — (narrowing loses nothing) | ≈ 0 bits; call layers as above |
| IRIW (seq_cst readers) | full order between the two reads per reader | `atomic_thread_fence(seq_cst)` ×2/reader → `fence rw,rw` | `System.ReadWriteBarrier` ×2/reader (shape PRECISE — seq_cst needs full anyway) | — (shape already exact; only the call layers) | ≈ 0 bits; 2–4 calls × ~45 ns per IRIW point |
| lock (LISA LOCK/UNLOCK) | acquire+release around the critical section | no direct C11 primitive — exchange(acq_rel) + fences, or C11 mutex | `AtomicExchange` enter + `ReadWriteBarrier`/exit composition | — (composition already precise; PSRAM lock word is unfixable by primitives — cache, not ordering) | ≈ 0 bits; 3–4 calls/lock op |

The over-strength BITS cost ≈ 0 on the quiet pipeline (full ≈ narrow,
measured). The real costs of the missing primitives are: (1) the call
layers — every sync point is ≥1 call, ~45 ns each, and cross-unit
inlining of asm-containing bodies is refused (three-layer refusal,
above); (2) expressiveness — some precise order relations (W→R as
`fence w,r`) cannot be expressed at all without the full fence's
over-reach, which on busy real pipelines (I/O, DMA in flight) serializes
unrelated traffic; (3) the plain livelock — with NO primitive available,
the failure mode is a system hang, not corrupt data.

Efficiency-gap ledger — the second dimension of missing primitives.
Beyond over-strength, stock FPC lacks the FUSED shapes that C11 maps
to directly: an acquire load is `lw` + `fence r,rw` in ONE routine
(espatomics ReadAcquire); a release store is `fence rw,w` + `sw` in
ONE routine (espatomics WriteRelease). The stock composition uses
separate barrier calls at each point — each an unconditional ~45 ns.
The fused primitive halves the barrier count for the consumer's
acquire path (R→R + R→W in one `fence r,rw`) and eliminates the
producer's separate release fence. Quantified per item (1M items,
S31 Mosaico):

| composition | barriers/item | calls/item | measured items/s |
| --- | --- | --- | --- |
| stock barrier (4 RTL calls) | 4 | 4 | 2.18–2.20 M |
| fused acquire load + release store | 2 | 2 | (projected ≈ 2.6–2.8 M) |

The fused shape saves ~2 calls and ~2 barriers per item — the dominant
saving is the call overhead (~90 ns/item), not the fence execution.

First generation (6 sync methods, median of ~10 runs, checksums ok):

| method | items/s | vs plain |
| --- | --- | --- |
| plain (no sync — not architecturally safe) | 2.06 M | 100% |
| full fence (`fence iorw,iorw` ×3/item, inline) | 1.69 M | 82% |
| spinlock around the whole enqueue/dequeue | 1.65 M | 80% |
| aqrl atomics (`lr.w.aq` loads, `amoswap.w.aqrl` stores) | 1.57 M | 76% |
| lr/sc exclusive (`lr.w.aq` loads, `lr/sc.w.rl` stores) | 1.55 M | 75% |
| espatomics ReadAcquire/WriteRelease (2-call helper) | 1.31 M | 64% |

Why a full fence beats annotated atomics at equal order strength: a
fence is pure ordering — it only waits for operations still in flight
(≈4–5 cycles of store-buffer drain here); an AMO/LR pays for atomicity
every time — serialized RMW at the coherence point, reservation
maintenance, a discarded old value (≈6–8 cycles), with no quiet path.
Atomics win where the RMW itself is needed (fetch-add), where ordering
must attach to a single instruction (the aq-on-a-store Dekker solution),
or with deep full store buffers.

PSRAM-resident ring (whole ring incl. index/lock cells in octal PSRAM,
1M items/variant): plain 1.86 M (−10%), fences −6%, atomics −5%, all
correct. Three architectural findings: (1) **S31 AMO and LR-SC execute
on PSRAM** (5M items, clean checksums — no StoreProhibited, unlike
ESP32-S3). (2) **A spinlock whose lock word lives in PSRAM deadlocks on
S31 regardless of unlock strength** (dual-confirmed `amoswap.w.aqrl`
and `fence`+plain-store unlocks; same code fine on SRAM) — two cores
polling the same PSRAM word cannot rely on observing each other's
writes (incoherent WB caches); single-writer cursor protocols do work.
Keep control words in internal DRAM (REQUIREMENTS.md rule, now with
mechanistic evidence). (3) A wedged app spinning at prio 22 starves the
USB console tasks and kills even esptool's auto-download handshake —
recovery then requires the BOOT+POWER ROM-download flow.

Console recipe learned here (usb_hs_console source): `__wrap_app_main`
holds app_main up to 10 s waiting for the host to open the CDC port
(DTR); a raw-fd listener never asserts DTR, so headless boots lose ALL
output. Working capture: reboot, then open with pyserial (DTR asserted)
within 10 s of the boot and read.

Cache-line separation of the indices (64 B strides) measured NO change
on S31: per-core data caches sit in front of external memory, not
internal SRAM, so false sharing is a PSRAM-resident-state concern here,
not an internal-DRAM one. Layout caveat: standalone unused pad ARRAYS
are smartlink-stripped — the pad must live inside a referenced record,
or the layout silently reverts to packed (an `out` parameter is passed
by reference too: overwrite through the pointer, not the slot — see
the cq_instrcost pitfalls).

## Empirical memory ordering: S3 vs S31 side by side

Dekker/SB litmus, real silicon, r00 counts ("both cores entered the
critical section" — forbidden under a global order). FPC and C run the
same protocol per chip; every nonzero row was measured with the fused
litmus shape (store+load in one asm block) so no result is a codegen-gap
artifact. Basis: S3 = 1–2M rounds per row (FPC and C); S31 = 500k rounds
per row, 2–3 runs per toolchain (ranges shown).

| litmus shape | S3 FPC | S3 C | S31 FPC | S31 C |
| --- | --- | --- | --- | --- |
| bare store→load, call-based (δ≈40–125 ns) | 0 | —¹ | 0 | —¹ |
| bare store→load, fused (gap ≈ 1–9 instr) | —² | **0** (2M) | **156–439** | **459–690** |
| full barrier BETWEEN store and load (MEMW / `fence iorw,iorw`) | 0 | 0 | 0 | 0 |
| release/acquire (barrier before store and after load) | 0 | 0 | **365–426** | **343–449** |
| aq+rl atomic flag-store (`amoswap.w.aqrl`; plain load) | n/a³ | n/a³ | **0** | **0** |
| PSRAM bare store→load | 0 | 0 | **464** | **258–429** |
| PSRAM + full barrier | 0 | 0 | 0 | 0 |

¹ The C controls use inline (tight) accessors; only FPC has the
  call-based shape.
² The fused shape was not run on S3 silicon separately — the C control's
  inline shape (equivalent-or-tighter gap) already covers it at 0/2M.
  In QEMU the same shapes DO violate (FPC fused 4061/100k, direct
  300/100k, C 1.75%/2M) — MTTCG+x86-host is a weak-memory model the S3
  silicon does not implement; never argue ordering from QEMU.
³ Xtensa has no aq/rl encodings (S32C1I carries none; ESP-IDF wraps it
  in MEMW).

Reading: S3 measures TSO-like on both memories for every plain shape,
so the δ-masking effect is invisible there (call-based and fused agree
at 0); S31 measures RVWMO — violations in every unguarded shape, δ
masking visible (call-based 0 vs fused >0), release/acquire open, only
a barrier between the two accesses or an aq-carrying atomic store close
it. All architectural guarantees are zero on both chips: every safe
outcome on S3 is an implementation property.

## Empirical memory ordering on ESP32-S31 (Dekker/SB litmus, 2026-11-02)

The RVWMO counterpart of the S3 experiment ran on real ESP32-S31 Mosaico
silicon (dual-core rv32imafc, `SOC_CPU_CORES_NUM=2`), FPC
(the S31 litmus program; superseded 2026-11-06 by the 3-mode
`demos/dekker.pas`, raw log `demos/dekker-s31-legacy.hw.log`) vs ESP-IDF C control
(`/mnt/storage/fpc-esp/hello-s31-dekker/`, hello-s31 base + SPIRAM per
mosaico-s31 recipe). 500k rounds per variant, fused litmus bodies
(store+load in one asm block, gap = 1 instruction):

| variant | FPC r00 | C r00 | verdict |
| --- | --- | --- | --- |
| sram-plain (natural shape, small gap) | 0 | 0 | gap masks the window (δ artifact) |
| sram-fused (`sw; lw`) | **309–439** | **459–690** | **no global order for plain store→load** |
| sram-fused-fence (fence between store and load) | **0** | **0** | full fence closes SB |
| sram-fused-relacq (`fence rw,w; sw; lw; fence r,rw`) | **365–426** | **343–429** | **release/acquire does NOT close SB** |
| sram-fused-aqrl (`amoswap.w.aqrl; lw`) | **0** | **0** | **aq on the STORE closes Dekker** |
| psram-fused | **464** | 258–429 | violates like SRAM |
| psram-fused-fence | **0** | **0** | fence closes on PSRAM too |

The aqrl row settles the theory question empirically: release
(`fence rw,w` / `.rl`) orders prior accesses before the store, acquire
(`fence r,rw` / `.aq` on the load) orders the load after prior accesses —
neither creates the store→same-thread-load edge, so the pair straddles
the gap between the two rules and SB stays open. But an `.aqrl` ATOMIC
STORE carries acquire itself, ordering it before the following load;
 Dekker is solvable with `amoswap.w.aqrl` flag-stores plus plain loads
(multiple runs agree: 0 violations in 500k rounds per toolchain).

The FPC psram rows in the FIRST hardware run measured all-(1,1) — root
cause found, and it was process, not silicon or compiler: build.sh does
NOT regenerate the .flash.img (that is flash.sh's job), and the no-stub
flash loop kept writing a STALE image, so the pointer fix was never
actually flashed. After regenerating the image, FPC psram rows match C
(464 / 0) and a mid-run diagnostic capture (pointer values on both
cores, initial/final flag contents, manager-side write-readback
0xA5A5A5A5/0x5A5A5A5A) confirms the program was correct all along.
Lesson: after any source change, regenerate the tight image from the
current .elf before flashing, or verify the image mtime/size against the
.elf.

Consequences for this unit:

- **RVWMO behaves as documented on real silicon.** A bare store→load
  pair from two cores produces the forbidden (0,0) outcome (~0.09% of
  rounds). Code relying on unguarded flag hand-off between cores is
  broken on S31 even though it appeared to work on S3.
- **The rv32a backend's acquire/release shape is NOT Dekker-safe.**
  `fence rw,w` before the store plus `fence r,rw` after the load leaves
  StoreLoad unordered (424-429 violations in 500k). Only a fence
  BETWEEN the two accesses closes the window. ReadAcquire/WriteRelease
  remain correct for message-passing (store-buffer publication) but not
  for mutual-exclusion hand-off — callers needing Dekker semantics must
  use a full fence between their own accesses.
- **FPC and gcc agree** (439 vs 459, 0 vs 0, 424 vs 429 on SRAM) once
  the litmus shape is held fixed by fusing store+load into one asm
  routine. The toolchain is not a variable in memory-order experiments;
  the codegen gap is.
- Fence placement matters: a fence BEFORE the store-then-load pair only
  orders prior accesses and closes nothing (measured 401-418 violations
  before the fix); the fence must sit between the store and the load.

Hardware-protocol lessons (Mosaico): host capture MUST use a raw-fd
reader — pyserial's open choreography (kernel asserts DTR/RTS, pyserial
then drops both) hits the usb_hs_console USJ-compatible auto-download
pattern and resets the board on every open, boot-looping any app.
esptool stub upload is unreliable on this link; use `--no-stub` with a
stability-gated retry loop. C-side experiments should persist results
to NVS (replayed on next boot) because the CDC console drops early
output after re-enumeration. Details: the `demos/dekker.pas` header comments.

## Empirical memory ordering on ESP32-S3 (Dekker/SB litmus, 2026-10-31)

The S3 litmus program (removed 2026-11-06; conclusions retained here)
and the C control experiment in
`/mnt/storage/fpc-esp/waveshare-s3-dekker/` (ESP-IDF, `asm volatile`
litmus accesses) run the classic store-buffer litmus on both cores:
each core stores its own flag then loads the other's; the (0,0) outcome
("both entered the critical section") is forbidden under a global order.

Measured on real ESP32-S3 silicon (rev 0.2, 240 MHz), 4M+ rounds per
toolchain over a 256x256 phase grid, flags in internal SRAM and in PSRAM:

- **No violation was ever observed.** Plain `s32i` → `l32i` behaves
  TSO-like on this silicon: cross-core store visibility fits inside the
  same-core store→load gap (≤ ~8–20 ns resolution of the pads). This
  holds for internal SRAM and for PSRAM, and with or without MEMW.
- MEMW between the store and the load closes SB; the release/acquire
  shape (MEMW only before the store and after the load) shows no
  violations on silicon either — but that is an **implementation
  property, not an architectural guarantee**. Xtensa defines no ordering
  without MEMW, and other/older silicon may differ; the backend keeps
  MEMW in acquire/release unconditionally.
- **QEMU (MTTCG on an x86 host) is not a valid memory-order model for
  this target.** The same C binary that shows zero violations on
  silicon produces 1.75% (sram-plain, 2M rounds) and 2.0% (relacq)
  violations in QEMU — the guest races come from the host's
  store-buffer semantics, not from the ESP32-S3. Never argue memory
  ordering from QEMU here. Note also that the violation RATE under
  MTTCG is a property of the binary × host-scheduling pair (the phase
  distribution of the two threads), not of the modeled memory alone:
  only the presence/absence of violations and same-binary variant
  comparisons are meaningful; do not compare rates across toolchains.
- **Toolchain gap artifact:** a call between the litmus store and load
  (FPC assembler-procedure call ≈ 40–125 ns) can exceed the entire SB
  window and mask real races. In QEMU the identical protocol shows 0
  violations when compiled from Pascal and 34951 from C, purely from
  this gap. The window width is W = 2D − (Δ0+Δ1), D being the host
  store-buffer drain and Δ the same-core store→load distance; the
  complementary outcome (both cores see both stores) uses W' =
  Δ0+Δ1 − 2D and flips exactly as predicted. Follow-up codegen study
  (S3-era, program removed 2026-11-06): plain Pascal assignments `Flag := 1; r := OtherFlag`
  do emit the tight `s32i.n … l32i.n` pair today (order kept, no
  register forwarding, 300 violations per 100k in QEMU) and a fused
  single-asm store;load routine opens the window widest (4061) — but
  FPC has no `volatile`, so the direct form is a codegen coincidence:
  the fused asm primitive is the only guaranteed shape, and control-word
  spin loops must keep the asm accessors or they cache into registers.
- These results do **not** relax the internal-DRAM rule: PSRAM atomics
  still trap, and this litmus only exercises a two-line hot working set
  — eviction-scale PSRAM behaviour, DMA, and `esp_cache_msync` semantics
  are out of scope here.

## Relation to parent repo

This directory is a **self-contained sub-project** under
`esp-units.pas/units/espatomics/`. Parent docs point here; they do not
duplicate the API. Sources and docs for atomics evolve in this directory.
Requirements: [`REQUIREMENTS.md`](./REQUIREMENTS.md). File-level map:
[`IMPLEMENTATION.md`](./IMPLEMENTATION.md). Agent entry:
[`AGENTS.md`](./AGENTS.md).

## Ordering acceptance demos (`units/espatomics/demos/`, 2026-11-06)

The acquire/release capability moved from the `TInterlockedEsp` helper to
**unit-level `ReadAcquire`/`WriteRelease` leaves** (UInt32 / LongInt /
Pointer overloads; the helper no longer carries them and is FreeRTOS-only;
the ARM32 backend was removed). Two demos, each compiled in three
access-mode shapes via `-dMODE_PLAIN / -dMODE_RTLBARRIER / -dMODE_ACQREL`
(one binary per mode), S31 Mosaico plus x86-linux stock builds.

**Disassembly (S31, `circularqueue-acqrel`/`dekker-acqrel`):** each
cursor/flag access is exactly ONE `jalr` into the leaf —

```
ESPATOMICS_$$_READACQUIRE$LONGWORD$$LONGWORD:   lw a0,0(a0); fence r,rw; ret
ESPATOMICS_$$_WRITERELEASE$LONGWORD$LONGWORD:   fence rw,w; sw a1,0(a0); ret
```

**S31 hardware (1M items / 500k rounds, tight images, ttyACM0):**

| demo | mode | result | runs |
| --- | --- | --- | --- |
| circularqueue | acqrel | **2.74–2.76 M items/s, checksum ok, corrupt=0** | 2 |
| circularqueue | rtlbarrier | 2.80–2.83 M items/s, ok, corrupt=0 | 2 |
| circularqueue | plain | 3.37–3.43 M items/s, ok, corrupt=0 — COMPLETED (see below) | 3 |
| dekker | plain (fused `sw; lw`) | **r00 = 353 / 320 per 500k** | 2 |
| dekker | rtlbarrier (`fence iorw,iorw` call between) | r00 = 0 | 1 |
| dekker | acqrel (leaf calls) | r00 = 0 (see attribution below) | 2 |

Readings:

- **acqrel is a ~20% throughput win over the old shapes.** The minimal
  shape carries 4 narrow fences/item (2 acquire + 2 release) vs the old
  inline-asm variant's 6 full fences/item: 2.75 M vs 2.23–2.31 M, with
  one call per access and clean checksums. The 1-call leaf shape works.
- **acqrel vs rtlbarrier: rtlbarrier is consistently 2.7% faster
  (353.1–356.8 µs vs 362.1–366.5 µs, 5× interleaved A/B, non-overlapping
  distributions) — root-caused, and NOT a fence-strength effect.** Three
  findings: (1) `fencecost.pas` measures every fence encoding (iorw,iorw
  / rw,rw / r,rw / rw,w / ir,ir / ow,ow) at the SAME cost on this
  silicon — 9 ns/it baseline loop, 28 ns/it with a fence = 18 ns/fence
  flat; the earlier cq_instrcost "full 8 ns vs narrow 10 ns" split was
  code-layout noise. (2) Static instruction counts favour acqrel
  (43+47 vs 45+48 per enqueue+dequeue, leafs 3 instrs both). (3) Shape
  isolation (`-dMODE_ACQREL` builds with one leaf replaced by its
  call-site counterpart): dropping WriteRelease saves 28 ns/item,
  dropping ReadAcquire saves 41 ns/item — the leaf-encapsulated
  "memory op + fence" pair costs 14–20 ns more per access than the
  call-site op + separate fence call, because the fence's pipeline
  quiesce window (18 ns) sits directly against the leaf's load/store
  while the call-site shape groups its independent loads/stores away
  from the fences. Fence COUNT remains the first-order cost: X2 (plain
  cursor reads + WriteRelease only, 2 fences/item) is the fastest shape
  measured at 3.1 M items/s with checksum ok — but it drops the acquire
  on the opposite core's published cursor, the atomic-nobar class:
  works on THIS silicon, not architecturally safe, do not ship. The
  old "barrier is slowest" gap came from the 2-level helper wrap, which
  no longer exists.
- **Dekker acqrel r00=0 is call-gap masking, not closure.** Between the
  release store (inside `WriteRelease`) and the acquire load (inside
  `ReadAcquire`) lie ret + address computation + jalr ≈ 10+ instructions;
  the store buffer drains in that gap. The same masking produced r00=0
  for the old call-based plain variant; the FUSED relacq shape (no gap)
  measured 365–426 / 500k on 2026-11-02. C11 acquire/release does not
  create the store→load edge — acq/rel ≠ seq_cst stands; the fused shape
  remains the true litmus probe.
- **circularqueue plain completed (3×, no livelock) in this codegen.**
  `TryEnqueue`/`TryDequeue` are not inlined in the demo, so every cursor
  poll is an opaque call and the compiler reloads the globals — the old
  program's permanent livelock (stale REGISTER-cached Head across an
  inlined poll loop) does not arise in this code generation. Plain stays
  architecturally unsafe on RVWMO (dekker-plain above proves the model
  weak); its clean completion is codegen + eviction luck, not
  correctness. It is the fastest shape, as expected.

**x86-linux stock builds (`fpc -dMODE_ACQREL -Tlinux`, host FPC 3.2.2) —
the unknown-platform degradation check.** Three proofs:

1. Source: with `FREERTOS` undefined the unit compiles the stock backend
   (no helper exists anywhere anymore; no SyncObjs needed).
2. Binary: the demo call sites resolve to direct RTL calls —
   `call SYSTEM_$$_INTERLOCKEDCOMPAREEXCHANGE…` /
   `call SYSTEM_$$_INTERLOCKEDEXCHANGE…` (the inline stock leaf folds to
   exactly one call); the RTL bodies are `lock cmpxchg %esi,(%rdi)` and
   `xchg %esi,(%rdi)` (memory-xchg is implicitly locked) — full barriers.
3. Run: circularqueue 3.37 M items/s checksum ok corrupt=0; dekker
   r00 = 0 (x86 is TSO). Performance not a host deliverable.

Raw logs: `demos/*.hw.log` (S31), `demos/*.x86.log` (host).

## Six-family litmus suite (`units/espatomics/litmus/litmus.pas`, 2026-11-07)

Six classic litmus families swept on one binary (runtime variant table,
20 shapes = 6 families x 3-5 shapes, 200k rounds each, control words
behind opaque accessors, litmus bodies fused asm for bare shapes so no
result is a codegen-gap artifact). Two-core mapping adaptations — chosen
so each family's forbidden outcome is CONSTRUCTIBLE:

- SB: P0/c0, P1/c1 (demos/dekker.pas protocol, in-depth there).
- MP: producer/c1, consumer(main)/c0.
- LB: P0/c0, P1/c1. Forbidden outcome is r0=1 AND r1=1 (both read the
  other's NEW value) — (0,0) is SC-legal and would make the family
  vacuous.
- WRC/ISA2: P0+P1 fused on c0 (x-store, observation r1, y<-r1 publish),
  P2 alone on c1. The fusion makes the causality chain's first hop
  same-core (monotone, r1 always 1); what remains testable is the
  PROPAGATION question — can the later core-0 store (y) overtake the
  earlier one (x) on the way to core 1. The writer's data store is
  deliberately UNFLUSHED (after the round publish, before the Go
  handshake) so the window stays open; the round reset is fenced.
- IRIW: writer+reader fused per core (P0(wx)+P2/c0, P1(wy)+P3/c1) —
  each reader's "sees-new" read is same-core, "may-be-stale" read
  cross-core; both readers run concurrently. Writer stores unflushed.

Strength matrix (family -> minimal ordering -> C11 construct -> our
primitive):

| family | minimal edge | C11 construct | primitive(s) | gap |
| --- | --- | --- | --- | --- |
| SB | W->R (store->own load) | atomic_thread_fence(seq_cst) between the pair; a seq_cst STORE alone does not close it in the model (relaxed loads never enter S) | System.ReadWriteBarrier; ExchangeAcqRel/SeqCst flag-store = divergence probe | acquire/release cannot make this edge at all |
| MP | W->W + R->R | atomic_store_explicit(release) + atomic_load_explicit(acquire) | WriteRelease + ReadAcquire | none (definition domain) |
| LB | R->W | atomic_load_explicit(acquire) on the litmus load | ReadAcquire | none |
| WRC/ISA2 | R->W + W->W + A-cumulativity | release store + acquire load (fences are A-cumulative in RVWMO; aq/rl BITS are not — a bit-based implementation would fail here) | WriteRelease + ReadAcquire | only the implementation choice (fence vs bits) |
| IRIW | R->R x2 + SC total order | atomic_thread_fence(seq_cst) between the reads | System.ReadWriteBarrier; ReadAcquire-as-first-read = model-divergence probe | C11-acquire allows IRIW; RVWMO cumulative-fence cycle forbids it |

**S31 silicon (200k rounds/variant, 2 runs, ttyACM0):**

| variant | forbidden | variant | forbidden |
| --- | --- | --- | --- |
| sb-bare | **281 / 295** | wrc-bare / acqrel / scfence | 0 / 0 / 0 |
| sb-acqrel | 0 / 0 | isa2-bare / acqrel / scfence | 0 / 0 / 0 |
| sb-exch-acqrel | 0 / 0 | iriw-bare / acqrel / scfence | 0 / 0 / 0 |
| sb-exch-seqcst | 0 / 0 | mp-bare / acqrel / scfence | 0 / 0 / 0 |
| sb-scfence | 0 / 0 | lb-bare / acqrel / scfence | 0 / 0 / 0 |

Readings:

- **SB is the only family whose window opens on this silicon** (0.14-0.15%
  of rounds, matching the dekker_s31 rate) — and every ordering shape
  closes it. Suite validity is therefore proven: the harness DOES reach
  the weak-memory window when one exists.
- **Divergence probe 1 resolved (SB exchstore):** both ExchangeAcqRel and
  ExchangeSeqCst flag-stores measured 0 — the amoswap.w.aqrl acquire half
  really does order the store before the following load on this silicon,
  which the C11 MODEL does not promise for acq_rel (the relaxed load
  never enters S). acq_rel vs seq_cst: identical encoding, identical
  silicon result, run under both names.
- **Divergence probe 2 left open empirically (IRIW acqrel):** 0 observed,
  but the bare shape also measured 0 — the harness cannot distinguish
  "closed by the acquire" from "window never opened" here.
- **MP/LB/WRC/ISA2/IRIW bare = 0: constructible but never observed.**
  Consistent picture: the S31 interconnect propagates a core's stores to
  the opposite core IN ORDER (MP's data-before-flag always held; the
  WRC/ISA2 "later store overtakes earlier one" inversion never appeared),
  and LB's double-window (both cores must lag into each other
  simultaneously) never fired in 200k rounds. These are silicon +
  harness results, not model theorems.
- All acquire/release and full-fence shapes: 0 — consistent with both
  the closures and the ordered-propagation picture.

Two bugs found and fixed during the first hardware bring-up (recorded
because they are easy to re-introduce): (1) the worker published only
Done1, never the load results (Obs1) for SB/LB — every forbidden count
became a constant-zero or constant-nonzero artifact; (2) putting the
writer's data store BEFORE a protocol FenceFull pre-flushes it globally
and closes the very window the family probes — the data store must be
the UNFLUSHED tail of the main-side prefix.

Raw logs: `litmus/litmus.hw.log`, `litmus/litmus.hw.log2`.

