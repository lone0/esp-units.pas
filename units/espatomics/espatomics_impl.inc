class function TInterlockedEsp.FetchAdd(var Target: UInt32; Value: UInt32): UInt32; inline;
begin
  Result := HwFetchAdd(Target, Value);
end;

class function TInterlockedEsp.FetchSub(var Target: UInt32; Value: UInt32): UInt32; inline;
begin
  Result := HwFetchAdd(Target, UInt32(-Value));
end;

class function TInterlockedEsp.FetchAnd(var Target: UInt32; Value: UInt32): UInt32; inline;
begin
  Result := HwFetchAnd(Target, Value);
end;

class function TInterlockedEsp.FetchOr(var Target: UInt32; Value: UInt32): UInt32; inline;
begin
  Result := HwFetchOr(Target, Value);
end;

class function TInterlockedEsp.FetchXor(var Target: UInt32; Value: UInt32): UInt32; inline;
begin
  Result := HwFetchXor(Target, Value);
end;

{$IFDEF FREERTOS}
class function TInterlockedEsp.BitTestAndSet(var Target: LongInt; BitOffset: TBitOffset): Boolean; inline;
var
  Mask, PreviousValue: UInt32;
begin
  Mask := UInt32(1) shl BitOffset;
  PreviousValue := FetchOr(PUInt32(@Target)^, Mask);
  Result := (PreviousValue and Mask) <> 0;
end;

class function TInterlockedEsp.BitTestAndClear(var Target: LongInt; BitOffset: TBitOffset): Boolean; inline;
var
  Mask, PreviousValue: UInt32;
begin
  Mask := UInt32(1) shl BitOffset;
  PreviousValue := FetchAnd(PUInt32(@Target)^, not Mask);
  Result := (PreviousValue and Mask) <> 0;
end;
{$ENDIF}

class function TInterlockedEsp.ReadAcquire(var Target: UInt32): UInt32; inline;
begin
  Result := HwReadAcquire(Target);
end;

class function TInterlockedEsp.ReadAcquire(var Target: LongInt): LongInt; inline;
begin
  Result := LongInt(ReadAcquire(PUInt32(@Target)^));
end;

class function TInterlockedEsp.ReadAcquire(var Target: Pointer): Pointer; inline;
begin
  Result := HwReadAcquirePointer(Target);
end;

class procedure TInterlockedEsp.WriteRelease(var Target: UInt32; Value: UInt32); inline;
begin
  HwWriteRelease(Target, Value);
end;

class procedure TInterlockedEsp.WriteRelease(var Target: LongInt; Value: LongInt); inline;
begin
  WriteRelease(PUInt32(@Target)^, UInt32(Value));
end;

class procedure TInterlockedEsp.WriteRelease(var Target: Pointer; Value: Pointer); inline;
begin
  HwWriteReleasePointer(Target, Value);
end;

class function TInterlockedEsp.CompareExchangeWeak(var Target: UInt32; Value, Comparand: UInt32;
  out Observed: UInt32): Boolean; inline;
begin
  Result := HwWeak(Target, Value, Comparand, Observed);
end;

class function TInterlockedEsp.CompareExchangeWeak(var Target: LongInt; Value, Comparand: LongInt;
  out Observed: LongInt): Boolean; inline;
var
  Seen: UInt32;
begin
  Result := CompareExchangeWeak(PUInt32(@Target)^, UInt32(Value), UInt32(Comparand), Seen);
  Observed := LongInt(Seen);
end;

class function TInterlockedEsp.CompareExchangeWeak(var Target: Pointer; Value, Comparand: Pointer;
  out Observed: Pointer): Boolean; inline;
begin
  Result := HwWeakPointer(Target, Value, Comparand, Observed);
end;

procedure TAtomicFlag.Init; inline;
begin
  FValue := 0;
end;

function TAtomicFlag.TestAndSet: Boolean; inline;
begin
  Result := HwExchange(FValue, 1) <> 0;
end;

procedure TAtomicFlag.Clear; inline;
begin
  HwWriteRelease(FValue, 0);
end;
