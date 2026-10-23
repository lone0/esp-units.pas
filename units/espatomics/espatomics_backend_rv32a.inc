function HwReadAcquire(var Target: UInt32): UInt32; assembler; nostackframe;
asm
  lw a0, 0(a0)
  fence r, rw
end;

procedure HwWriteRelease(var Target: UInt32; Value: UInt32); assembler; nostackframe;
asm
  fence rw, w
  sw a1, 0(a0)
end;

function HwExchange(var Target: UInt32; Value: UInt32): UInt32; assembler; nostackframe;
asm
  amoswap.w.aqrl a0, a1, 0(a0)
end;

function HwFetchAdd(var Target: UInt32; Value: UInt32): UInt32; assembler; nostackframe;
asm
  amoadd.w.aqrl a0, a1, 0(a0)
end;

function HwFetchAnd(var Target: UInt32; Value: UInt32): UInt32; assembler; nostackframe;
asm
  amoand.w.aqrl a0, a1, 0(a0)
end;

function HwFetchOr(var Target: UInt32; Value: UInt32): UInt32; assembler; nostackframe;
asm
  amoor.w.aqrl a0, a1, 0(a0)
end;

function HwFetchXor(var Target: UInt32; Value: UInt32): UInt32; assembler; nostackframe;
asm
  amoxor.w.aqrl a0, a1, 0(a0)
end;

function HwWeak(var Target: UInt32; Value, Comparand: UInt32; out Observed: UInt32): Boolean; assembler; nostackframe;
asm
  lr.w.aq a4, 0(a0)
  sw a4, 0(a3)
  addi a6, x0, 0
  bne a4, a2, .LWeakFail
  sc.w.rl a5, a1, 0(a0)
  bne a5, x0, .LWeakFail
  addi a6, x0, 1
.LWeakFail:
  addi a0, a6, 0
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
