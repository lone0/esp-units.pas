function HwReadAcquire(var Target: UInt32): UInt32; inline;
begin
  Result := UInt32(InterlockedCompareExchange(PLongInt(@Target)^, 0, 0));
end;

procedure HwWriteRelease(var Target: UInt32; Value: UInt32); inline;
begin
  InterlockedExchange(PLongInt(@Target)^, LongInt(Value));
end;

function HwExchange(var Target: UInt32; Value: UInt32): UInt32; inline;
begin
  Result := UInt32(InterlockedExchange(PLongInt(@Target)^, LongInt(Value)));
end;

function HwFetchAdd(var Target: UInt32; Value: UInt32): UInt32; inline;
begin
  Result := UInt32(InterlockedExchangeAdd(PLongInt(@Target)^, LongInt(Value)));
end;

function HwFetchAnd(var Target: UInt32; Value: UInt32): UInt32; inline;
var
  Old, Seen: LongInt;
begin
  repeat
    Old := LongInt(Target);
    Seen := InterlockedCompareExchange(PLongInt(@Target)^, Old and LongInt(Value), Old);
  until Seen = Old;
  Result := UInt32(Old);
end;

function HwFetchOr(var Target: UInt32; Value: UInt32): UInt32; inline;
var
  Old, Seen: LongInt;
begin
  repeat
    Old := LongInt(Target);
    Seen := InterlockedCompareExchange(PLongInt(@Target)^, Old or LongInt(Value), Old);
  until Seen = Old;
  Result := UInt32(Old);
end;

function HwFetchXor(var Target: UInt32; Value: UInt32): UInt32; inline;
var
  Old, Seen: LongInt;
begin
  repeat
    Old := LongInt(Target);
    Seen := InterlockedCompareExchange(PLongInt(@Target)^, Old xor LongInt(Value), Old);
  until Seen = Old;
  Result := UInt32(Old);
end;

function HwWeak(var Target: UInt32; Value, Comparand: UInt32; out Observed: UInt32): Boolean; inline;
begin
  Observed := UInt32(InterlockedCompareExchange(PLongInt(@Target)^, LongInt(Value), LongInt(Comparand)));
  Result := Observed = Comparand;
end;

function HwReadAcquirePointer(var Target: Pointer): Pointer; inline;
begin
  Result := InterlockedCompareExchange(Target, nil, nil);
end;

procedure HwWriteReleasePointer(var Target: Pointer; Value: Pointer); inline;
begin
  InterlockedExchange(Target, Value);
end;

function HwWeakPointer(var Target: Pointer; Value, Comparand: Pointer;
  out Observed: Pointer): Boolean; inline;
begin
  Observed := InterlockedCompareExchange(Target, Value, Comparand);
  Result := Observed = Comparand;
end;
