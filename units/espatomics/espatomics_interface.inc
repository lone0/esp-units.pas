type
  TAtomicFlag = record
  private
    FValue: UInt32;
  public
    procedure Init; inline;
    function TestAndSet: Boolean; inline;
    procedure Clear; inline;
  end;

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
    class function ReadAcquire(var Target: LongInt): LongInt; overload; static; inline;
    class function ReadAcquire(var Target: UInt32): UInt32; overload; static; inline;
    class function ReadAcquire(var Target: Pointer): Pointer; overload; static; inline;
    class procedure WriteRelease(var Target: LongInt; Value: LongInt); overload; static; inline;
    class procedure WriteRelease(var Target: UInt32; Value: UInt32); overload; static; inline;
    class procedure WriteRelease(var Target: Pointer; Value: Pointer); overload; static; inline;
    class function CompareExchangeWeak(var Target: LongInt; Value, Comparand: LongInt;
      out Observed: LongInt): Boolean; overload; static; inline;
    class function CompareExchangeWeak(var Target: UInt32; Value, Comparand: UInt32;
      out Observed: UInt32): Boolean; overload; static; inline;
    class function CompareExchangeWeak(var Target: Pointer; Value, Comparand: Pointer;
      out Observed: Pointer): Boolean; overload; static; inline;
  end;
