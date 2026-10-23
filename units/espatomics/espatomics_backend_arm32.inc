function HwReadAcquire(var Target: UInt32): UInt32; assembler; nostackframe;
asm
  ldr r0, [r0]
  dmb ish
end;

procedure HwWriteRelease(var Target: UInt32; Value: UInt32); assembler; nostackframe;
asm
  dmb ish
  str r1, [r0]
end;

function HwExchange(var Target: UInt32; Value: UInt32): UInt32; assembler; nostackframe;
asm
  dmb ish
.LExchangeRetry:
  ldrex r2, [r0]
  strex r3, r1, [r0]
  cmp r3, #0
  bne .LExchangeRetry
  dmb ish
  mov r0, r2
end;

function HwFetchAdd(var Target: UInt32; Value: UInt32): UInt32; assembler; nostackframe;
asm
  dmb ish
.LFetchAddRetry:
  ldrex r2, [r0]
  add r3, r2, r1
  strex r12, r3, [r0]
  cmp r12, #0
  bne .LFetchAddRetry
  dmb ish
  mov r0, r2
end;

function HwFetchAnd(var Target: UInt32; Value: UInt32): UInt32; assembler; nostackframe;
asm
  dmb ish
.LFetchAndRetry:
  ldrex r2, [r0]
  and r3, r2, r1
  strex r12, r3, [r0]
  cmp r12, #0
  bne .LFetchAndRetry
  dmb ish
  mov r0, r2
end;

function HwFetchOr(var Target: UInt32; Value: UInt32): UInt32; assembler; nostackframe;
asm
  dmb ish
.LFetchOrRetry:
  ldrex r2, [r0]
  orr r3, r2, r1
  strex r12, r3, [r0]
  cmp r12, #0
  bne .LFetchOrRetry
  dmb ish
  mov r0, r2
end;

function HwFetchXor(var Target: UInt32; Value: UInt32): UInt32; assembler; nostackframe;
asm
  dmb ish
.LFetchXorRetry:
  ldrex r2, [r0]
  eor r3, r2, r1
  strex r12, r3, [r0]
  cmp r12, #0
  bne .LFetchXorRetry
  dmb ish
  mov r0, r2
end;

function HwWeak(var Target: UInt32; Value, Comparand: UInt32; out Observed: UInt32): Boolean; assembler; nostackframe;
asm
  dmb ish
  ldrex r12, [r0]
  str r12, [r3]
  cmp r12, r2
  bne .LWeakClear
  strex r12, r1, [r0]
  cmp r12, #0
  bne .LWeakFail
  mov r0, #1
  b .LWeakDone
.LWeakClear:
  clrex
.LWeakFail:
  mov r0, #0
.LWeakDone:
  dmb ish
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
