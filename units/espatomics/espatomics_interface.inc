{ Leaf layer: C11 atomic_load_explicit(memory_order_acquire) /
  atomic_store_explicit(memory_order_release). Exactly one call on the
  dedicated backends (RV32A: "lw; fence r,rw" / "fence rw,w; sw"); on
  targets without a dedicated backend these degrade to the full-barrier
  System.Interlocked* RTL routines. }
function ReadAcquire(var Target: UInt32): UInt32; overload;
function ReadAcquire(var Target: LongInt): LongInt; overload;
function ReadAcquire(var Target: Pointer): Pointer; overload;
procedure WriteRelease(var Target: UInt32; Value: UInt32); overload;
procedure WriteRelease(var Target: LongInt; Value: LongInt); overload;
procedure WriteRelease(var Target: Pointer; Value: Pointer); overload;

{ RMW leaves: C11 atomic_exchange_explicit(memory_order_acq_rel) and
  atomic_exchange_explicit(memory_order_seq_cst). Named and shaped after
  the compiler intrinsic System.AtomicExchange: stores Source into Target
  and returns the PRIOR content of Target — with the memory order
  promoted from relaxed to acq_rel / seq_cst (parameter type UInt32 vs
  the intrinsic's LongInt; same 32-bit machine shape). On RV32A both
  emit the SAME amoswap.w.aqrl encoding — the distinction is model-level
  only (participation in the SC total order, e.g. IRIW classification).
  Note the boundary: the SB/Dekker and IRIW forbiddens are expressed in
  C11 with atomic_thread_fence(memory_order_seq_cst) between the access
  pairs; these RMW primitives do not provide that fence. }
function AtomicExchangeAcqRel(var Target: UInt32; Source: UInt32): UInt32;
function AtomicExchangeSeqCst(var Target: UInt32; Source: UInt32): UInt32;

{ RMW fetch leaves: C11 atomic_fetch_<op>_explicit(memory_order_acq_rel)
  (the RV32A leaves emit amo*.w.aqrl — full acq_rel ordering, stronger
  than the relaxed default; the aqrl premium is ~17 ns/access here).
  CompareExchangeWeak = C11 atomic_compare_exchange_weak_explicit
  (acq_rel, acquire) — lr.w.aq + sc.w.rl, may fail spuriously per the
  weak contract. UInt32 only for now; Pointer/LongInt overloads follow
  on demand. }
function FetchAdd(var Target: UInt32; Source: UInt32): UInt32;
function FetchSub(var Target: UInt32; Source: UInt32): UInt32;
function FetchAnd(var Target: UInt32; Source: UInt32): UInt32;
function FetchOr(var Target: UInt32; Source: UInt32): UInt32;
function FetchXor(var Target: UInt32; Source: UInt32): UInt32;
function CompareExchangeWeak(var Target: UInt32; Value, Comparand: UInt32;
  out Observed: UInt32): Boolean;
