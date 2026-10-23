unit freertosinterlocked;

{$mode objfpc}
{$H+}

interface

type
  TBitOffset = 0..31;

{$IFDEF CPU16}
{$DEFINE NOPOINTER}
{$ENDIF}

  TInterlocked = class sealed
    class function Add(var Target: LongInt; AIncrement: LongInt): LongInt; overload; static; inline;
    class function Exchange(var Target: LongInt; Value: LongInt): LongInt; overload; static; inline;
    class function CompareExchange(var Target: LongInt; Value, Comparand: LongInt): LongInt; overload; static; inline;
    class function CompareExchange(var Target: LongInt; Value, Comparand: LongInt;
      out Succeeded: Boolean): LongInt; overload; static;
    class function Decrement(var Target: LongInt): LongInt; overload; static; inline;
    class function Increment(var Target: LongInt): LongInt; overload; static; inline;
{$IFDEF FPC_HAS_TYPE_SINGLE}
    class function Exchange(var Target: Single; Value: Single): Single; overload; static; inline;
    class function CompareExchange(var Target: Single; Value, Comparand: Single): Single; overload; static; inline;
{$ENDIF}
{$IFNDEF NOPOINTER}
    class function Exchange(var Target: Pointer; Value: Pointer): Pointer; overload; static; inline;
    class function Exchange(var Target: TObject; Value: TObject): TObject; overload; static; inline;
    class function CompareExchange(var Target: Pointer; Value, Comparand: Pointer): Pointer; overload; static; inline;
    class function CompareExchange(var Target: TObject; Value, Comparand: TObject): TObject; overload; static; inline;
    generic class function Exchange<T>(var Target: T; Value: T): T; overload; static; inline;
    generic class function CompareExchange<T>(var Target: T; Value, Comparand: T): T; overload; static; inline;
{$ENDIF}
  end;

implementation

class function TInterlocked.Add(var Target: LongInt; AIncrement: LongInt): LongInt; inline;
var
  PreviousValue: LongInt;
begin
  PreviousValue := System.InterlockedExchangeAdd(Target, AIncrement);
  Result := PreviousValue + AIncrement;
end;

class function TInterlocked.Exchange(var Target: LongInt; Value: LongInt): LongInt; inline;
begin
  Result := System.InterlockedExchange(Target, Value);
end;

class function TInterlocked.CompareExchange(var Target: LongInt; Value, Comparand: LongInt): LongInt; inline;
begin
  Result := System.InterlockedCompareExchange(Target, Value, Comparand);
end;

class function TInterlocked.CompareExchange(var Target: LongInt; Value, Comparand: LongInt;
  out Succeeded: Boolean): LongInt;
begin
  Result := System.InterlockedCompareExchange(Target, Value, Comparand);
  Succeeded := Result = Comparand;
end;

class function TInterlocked.Decrement(var Target: LongInt): LongInt; inline;
begin
  Result := System.InterlockedDecrement(Target);
end;

class function TInterlocked.Increment(var Target: LongInt): LongInt; inline;
begin
  Result := System.InterlockedIncrement(Target);
end;

{$IFDEF FPC_HAS_TYPE_SINGLE}
class function TInterlocked.Exchange(var Target: Single; Value: Single): Single; inline;
var
  ValueBits, PreviousBits: LongInt;
begin
  Move(Value, ValueBits, SizeOf(ValueBits));
  PreviousBits := TInterlocked.Exchange(PLongInt(@Target)^, ValueBits);
  Move(PreviousBits, Result, SizeOf(Result));
end;

class function TInterlocked.CompareExchange(var Target: Single; Value, Comparand: Single): Single; inline;
var
  ValueBits, ComparandBits, PreviousBits: LongInt;
begin
  Move(Value, ValueBits, SizeOf(ValueBits));
  Move(Comparand, ComparandBits, SizeOf(ComparandBits));
  PreviousBits := TInterlocked.CompareExchange(PLongInt(@Target)^, ValueBits, ComparandBits);
  Move(PreviousBits, Result, SizeOf(Result));
end;
{$ENDIF}

{$IFNDEF NOPOINTER}
class function TInterlocked.Exchange(var Target: Pointer; Value: Pointer): Pointer; inline;
begin
  Result := System.InterlockedExchange(Target, Value);
end;

class function TInterlocked.Exchange(var Target: TObject; Value: TObject): TObject; inline;
begin
  Result := TObject(System.InterlockedExchange(Pointer(Target), Pointer(Value)));
end;

class function TInterlocked.CompareExchange(var Target: Pointer; Value, Comparand: Pointer): Pointer; inline;
begin
  Result := System.InterlockedCompareExchange(Target, Value, Comparand);
end;

class function TInterlocked.CompareExchange(var Target: TObject; Value, Comparand: TObject): TObject; inline;
begin
  Result := TObject(System.InterlockedCompareExchange(Pointer(Target), Pointer(Value), Pointer(Comparand)));
end;

generic class function TInterlocked.Exchange<T>(var Target: T; Value: T): T; inline;
begin
  Result := T(System.InterlockedExchange(Pointer(Target), Pointer(Value)));
end;

generic class function TInterlocked.CompareExchange<T>(var Target: T; Value, Comparand: T): T; inline;
begin
  Result := T(System.InterlockedCompareExchange(Pointer(Target), Pointer(Value), Pointer(Comparand)));
end;
{$ENDIF}

end.
