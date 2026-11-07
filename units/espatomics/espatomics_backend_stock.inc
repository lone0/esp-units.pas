function ReadAcquire(var Target: UInt32): UInt32; inline;
begin
  Result := UInt32(InterlockedCompareExchange(PLongInt(@Target)^, 0, 0));
end;

function ReadAcquire(var Target: LongInt): LongInt; inline;
begin
  Result := InterlockedCompareExchange(Target, 0, 0);
end;

function ReadAcquire(var Target: Pointer): Pointer; inline;
begin
  Result := InterlockedCompareExchange(Target, nil, nil);
end;

procedure WriteRelease(var Target: UInt32; Value: UInt32); inline;
begin
  InterlockedExchange(PLongInt(@Target)^, LongInt(Value));
end;

procedure WriteRelease(var Target: LongInt; Value: LongInt); inline;
begin
  InterlockedExchange(Target, Value);
end;

procedure WriteRelease(var Target: Pointer; Value: Pointer); inline;
begin
  InterlockedExchange(Target, Value);
end;

{ acq_rel and seq_cst RMW degrade to the same full-barrier RTL exchange }
function AtomicExchangeAcqRel(var Target: UInt32; Source: UInt32): UInt32; inline;
begin
  Result := UInt32(InterlockedExchange(PLongInt(@Target)^, LongInt(Source)));
end;

function AtomicExchangeSeqCst(var Target: UInt32; Source: UInt32): UInt32; inline;
begin
  Result := UInt32(InterlockedExchange(PLongInt(@Target)^, LongInt(Source)));
end;

function FetchAdd(var Target: UInt32; Source: UInt32): UInt32; inline;
begin
  Result := UInt32(InterlockedExchangeAdd(PLongInt(@Target)^, LongInt(Source)));
end;

function FetchSub(var Target: UInt32; Source: UInt32): UInt32; inline;
begin
  Result := UInt32(InterlockedExchangeAdd(PLongInt(@Target)^, LongInt(-Source)));
end;

function FetchAnd(var Target: UInt32; Source: UInt32): UInt32; inline;
var
  Old, Seen: LongInt;
begin
  repeat
    Old := LongInt(Target);
    Seen := InterlockedCompareExchange(PLongInt(@Target)^, Old and LongInt(Source), Old);
  until Seen = Old;
  Result := UInt32(Old);
end;

function FetchOr(var Target: UInt32; Source: UInt32): UInt32; inline;
var
  Old, Seen: LongInt;
begin
  repeat
    Old := LongInt(Target);
    Seen := InterlockedCompareExchange(PLongInt(@Target)^, Old or LongInt(Source), Old);
  until Seen = Old;
  Result := UInt32(Old);
end;

function FetchXor(var Target: UInt32; Source: UInt32): UInt32; inline;
var
  Old, Seen: LongInt;
begin
  repeat
    Old := LongInt(Target);
    Seen := InterlockedCompareExchange(PLongInt(@Target)^, Old xor LongInt(Source), Old);
  until Seen = Old;
  Result := UInt32(Old);
end;

function CompareExchangeWeak(var Target: UInt32; Value, Comparand: UInt32; out Observed: UInt32): Boolean; inline;
begin
  Observed := UInt32(InterlockedCompareExchange(PLongInt(@Target)^, LongInt(Value), LongInt(Comparand)));
  Result := Observed = Comparand;
end;

