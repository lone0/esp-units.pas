procedure XtMemw; assembler;
asm
  memw
end;

function XtLoad(var Target: UInt32): UInt32; assembler;
asm
  l32i a2, a2, 0
end;

procedure XtStore(var Target: UInt32; Value: UInt32); assembler;
asm
  s32i a3, a2, 0
end;

function XtCasOnce(var Target: UInt32; NewValue, Comparand: UInt32): UInt32; assembler;
asm
  wsr.scompare1 a4
  mov a5, a3
  s32c1i a5, a2, 0
  mov a2, a5
end;

function XtExchange(var Target: UInt32; Value: UInt32): UInt32; inline;
var
  Seen, Old: UInt32;
begin
  Seen := XtLoad(Target);
  repeat
    Old := Seen;
    Seen := XtCasOnce(Target, Value, Old);
  until Seen = Old;
  Result := Old;
end;

function XtFetchOp(var Target: UInt32; Value: UInt32; Kind: LongInt): UInt32; inline;
var
  Seen, Old, NewValue: UInt32;
begin
  Seen := XtLoad(Target);
  repeat
    Old := Seen;
    case Kind of
      0: NewValue := Old + Value;
      1: NewValue := Old and Value;
      2: NewValue := Old or Value;
    else
      NewValue := Old xor Value;
    end;
    Seen := XtCasOnce(Target, NewValue, Old);
  until Seen = Old;
  Result := Old;
end;

function HwReadAcquire(var Target: UInt32): UInt32; inline;
begin
  Result := XtLoad(Target);
  XtMemw;
end;

procedure HwWriteRelease(var Target: UInt32; Value: UInt32); inline;
begin
  XtMemw;
  XtStore(Target, Value);
end;

function HwExchange(var Target: UInt32; Value: UInt32): UInt32; inline;
begin
  XtMemw;
  Result := XtExchange(Target, Value);
  XtMemw;
end;

function HwFetchAdd(var Target: UInt32; Value: UInt32): UInt32; inline;
begin
  XtMemw;
  Result := XtFetchOp(Target, Value, 0);
  XtMemw;
end;

function HwFetchAnd(var Target: UInt32; Value: UInt32): UInt32; inline;
begin
  XtMemw;
  Result := XtFetchOp(Target, Value, 1);
  XtMemw;
end;

function HwFetchOr(var Target: UInt32; Value: UInt32): UInt32; inline;
begin
  XtMemw;
  Result := XtFetchOp(Target, Value, 2);
  XtMemw;
end;

function HwFetchXor(var Target: UInt32; Value: UInt32): UInt32; inline;
begin
  XtMemw;
  Result := XtFetchOp(Target, Value, 3);
  XtMemw;
end;

function HwWeak(var Target: UInt32; Value, Comparand: UInt32; out Observed: UInt32): Boolean; inline;
begin
  XtMemw;
  Observed := XtCasOnce(Target, Value, Comparand);
  XtMemw;
  Result := Observed = Comparand;
end;

function HwReadAcquirePointer(var Target: Pointer): Pointer; inline;
begin
  Result := Pointer(HwReadAcquire(PUInt32(@Target)^));
end;

procedure HwWriteReleasePointer(var Target: Pointer; Value: Pointer); inline;
begin
  HwWriteRelease(PUInt32(@Target)^, UInt32(Value));
end;

function HwWeakPointer(var Target: Pointer; Value, Comparand: Pointer;
  out Observed: Pointer): Boolean; inline;
var
  Seen: UInt32;
begin
  Result := HwWeak(PUInt32(@Target)^, UInt32(Value), UInt32(Comparand), Seen);
  Observed := Pointer(Seen);
end;
