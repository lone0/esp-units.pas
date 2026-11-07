function ReadAcquire(var Target: UInt32): UInt32; assembler; nostackframe;
asm
  lw a0, 0(a0)
  fence r, rw
end;

function ReadAcquire(var Target: LongInt): LongInt; assembler; nostackframe;
asm
  lw a0, 0(a0)
  fence r, rw
end;

function ReadAcquire(var Target: Pointer): Pointer; assembler; nostackframe;
asm
  lw a0, 0(a0)
  fence r, rw
end;

procedure WriteRelease(var Target: UInt32; Value: UInt32); assembler; nostackframe;
asm
  fence rw, w
  sw a1, 0(a0)
end;

procedure WriteRelease(var Target: LongInt; Value: LongInt); assembler; nostackframe;
asm
  fence rw, w
  sw a1, 0(a0)
end;

procedure WriteRelease(var Target: Pointer; Value: Pointer); assembler; nostackframe;
asm
  fence rw, w
  sw a1, 0(a0)
end;

function AtomicExchangeAcqRel(var Target: UInt32; Source: UInt32): UInt32; assembler; nostackframe;
asm
  amoswap.w.aqrl a0, a1, 0(a0)
end;

function AtomicExchangeSeqCst(var Target: UInt32; Source: UInt32): UInt32; assembler; nostackframe;
asm
  amoswap.w.aqrl a0, a1, 0(a0)
end;

function FetchAdd(var Target: UInt32; Source: UInt32): UInt32; assembler; nostackframe;
asm
  amoadd.w.aqrl a0, a1, 0(a0)
end;

function FetchSub(var Target: UInt32; Source: UInt32): UInt32; assembler; nostackframe;
asm
  neg a1, a1
  amoadd.w.aqrl a0, a1, 0(a0)
end;

function FetchAnd(var Target: UInt32; Source: UInt32): UInt32; assembler; nostackframe;
asm
  amoand.w.aqrl a0, a1, 0(a0)
end;

function FetchOr(var Target: UInt32; Source: UInt32): UInt32; assembler; nostackframe;
asm
  amoor.w.aqrl a0, a1, 0(a0)
end;

function FetchXor(var Target: UInt32; Source: UInt32): UInt32; assembler; nostackframe;
asm
  amoxor.w.aqrl a0, a1, 0(a0)
end;

function CompareExchangeWeak(var Target: UInt32; Value, Comparand: UInt32; out Observed: UInt32): Boolean; assembler; nostackframe;
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

