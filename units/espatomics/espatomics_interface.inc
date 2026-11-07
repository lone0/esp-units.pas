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

type
  TAtomicFlag = record
  private
    FValue: UInt32;
  public
    procedure Init; inline;
    function TestAndSet: Boolean; inline;
    procedure Clear; inline;
  end;

{$IFDEF FREERTOS}
  { FreeRTOS-only: wraps the freertosinterlocked TInterlocked baseline }
  TInterlockedEsp = class helper for TInterlocked
  public
{$IFDEF FREERTOS}
    class function BitTestAndSet(var Target: LongInt; BitOffset: TBitOffset): Boolean; static; inline;
    class function BitTestAndClear(var Target: LongInt; BitOffset: TBitOffset): Boolean; static; inline;
{$ENDIF}
    class function FetchAdd(var Target: UInt32; Value: UInt32): UInt32; overload; static; inline;
    class function FetchSub(var Target: UInt32; Value: UInt32): UInt32; overload; static; inline;
    class function FetchAnd(var Target: UInt32; Value: UInt32): UInt32; overload; static; inline;
    class function FetchOr(var Target: UInt32; Value: UInt32): UInt32; overload; static; inline;
    class function FetchXor(var Target: UInt32; Value: UInt32): UInt32; overload; static; inline;
    class function CompareExchangeWeak(var Target: LongInt; Value, Comparand: LongInt;
      out Observed: LongInt): Boolean; overload; static; inline;
    class function CompareExchangeWeak(var Target: UInt32; Value, Comparand: UInt32;
      out Observed: UInt32): Boolean; overload; static; inline;
    class function CompareExchangeWeak(var Target: Pointer; Value, Comparand: Pointer;
      out Observed: Pointer): Boolean; overload; static; inline;
  end;
{$ENDIF}
