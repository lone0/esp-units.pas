{ cq_instrcost.pas — instruction-cost isolation benchmark for the SPSC
  ring's head/tail synchronization (companion to circularqueue.pas).

  Motivation: the circularqueue run showed the call-based espatomics
  acquire/release pair 18% slower than the call-based full-fence shape.
  Disassembly attributed ALL of that to the class-helper call wrapping
  (~15 extra instructions per access: two stack frames, parameter and
  result spills), not to fence semantics. This benchmark removes the
  variable: every index access is an INLINE asm block that references
  the globals by Pascal name — zero calls, zero frames — and the same
  twelve shapes are then re-run through the call-based helpers in the
  same boot, so per-instruction costs and the wrapper tax fall out of
  one measurement.

  Shapes (each in an inline variant 1-6 and a call variant 7-12):

    plain  : bare lw/sw
    fence  : full `fence iorw,iorw` after each index load / before each
             index store
    relacq : `fence r,rw` after each index load, `fence rw,w` before each
             index store (call variant calls espatomics'
             unit-level ReadAcquire/WriteRelease leaves directly)
    aqrl   : index loads via `lr.w.aq`, index stores via
             `amoswap.w.aqrl`
    lrsc   : index loads via `lr.w.aq`, index stores via
             `lr.w/sc.w.rl` retry loops
    lock   : spinlock (`amoswap.w.aq` acquire loop, `fence+sw x0`
             release) around the whole enqueue/dequeue

  Protocol identical to circularqueue.pas: producer on core 1, consumer
  (app_main) on core 0, 1M bytes per variant through a 1024-slot ring,
  esp_timer timing on the consumer side, per-variant checksum and
  corrupt-byte validation, producer retries until accepted.

  FPC note (verified against compiler sources): a basic asm block in
  objfpc mode may reference globals and locals by their Pascal names
  (rautils.pas SetupVar handles the mangling); the compiler assumes all
  caller-saved registers are clobbered across a basic asm block, so only
  t0-t3 are used here and no callee-saved register is touched.

  Console: usb_hs_console on S31 (auto-linked by build.sh). Capture: reboot
  the app (DTR/RTS dance or esptool) and open with pyserial — DTR
  asserted — within usb_hs_console's 10 s attach window.

  Build:  ESP32_SDK_PROJECT=.../hello-s31 \
          scripts/build.sh --soc esp32s31 \
              units/espatomics/cq_instrcost.pas
}

program cq_instrcost;

{$mode objfpc}
{$H+}

{$LINKLIB usb_hs_console}
{$LINKLIB espressif__esp_tinyusb}
{$LINKLIB espressif__tinyusb}
{$LINKLIB esp_hal_usb}

uses
  espatomics;

const
  RingSize = 1024;
  RingMask = RingSize - 1;
  ItemsPerVariant = 1000000;
  VariantCount = 12;

  VIPlain = 1;
  VIFence = 2;
  VIRelAcq = 3;
  VIAqRl = 4;
  VILrSc = 5;
  VILock = 6;
  VCPlain = 7;
  VCFence = 8;
  VCRelAcq = 9;
  VCAqRl = 10;
  VCLrSc = 11;
  VCLock = 12;

var
  Buffer: array[0..RingMask] of Byte;
  Head: UInt32;      { producer cursor }
  Tail: UInt32;      { consumer cursor }
  QLock: UInt32;     { spinlock state }
  CurVariant: UInt32;
  VariantDone: UInt32;
  ProdSum: UInt32;
  ConsSum: UInt32;
  ConsCount: UInt32;
  Corrupt: UInt32;

{ ---- call-based helpers (shapes 7-12): one call per access ---- }

function LoadPlain(var V: UInt32): UInt32; assembler; nostackframe;
asm
  lw a0, 0(a0)
end;

procedure StorePlain(var V: UInt32; X: UInt32); assembler; nostackframe;
asm
  sw a1, 0(a0)
end;

procedure FenceFull; assembler; nostackframe;
asm
  fence iorw, iorw
end;

function LoadAq(var V: UInt32): UInt32; assembler; nostackframe;
asm
  lr.w.aq a0, 0(a0)
end;

procedure StoreAqRl(var V: UInt32; X: UInt32); assembler; nostackframe;
asm
  amoswap.w.aqrl a2, a1, 0(a0)
end;

procedure StoreLrSc(var V: UInt32; X: UInt32); assembler; nostackframe;
asm
.Lx:
  lr.w a2, 0(a0)
  sc.w.rl a3, a1, 0(a0)
  bnez a3, .Lx
end;

procedure LockEnter(var L: UInt32); assembler; nostackframe;
asm
.Ll:
  li a2, 1
  amoswap.w.aq a1, a2, 0(a0)
  bnez a1, .Ll
end;

procedure LockLeave(var L: UInt32); assembler; nostackframe;
asm
  fence iorw, iorw
  sw x0, 0(a0)
end;

function VariantName(V: UInt32): PChar;
begin
  case V of
    VIPlain: Result := 'i-plain';
    VIFence: Result := 'i-fence';
    VIRelAcq: Result := 'i-relacq';
    VIAqRl: Result := 'i-aqrl';
    VILrSc: Result := 'i-lrsc';
    VILock: Result := 'i-lock';
    VCPlain: Result := 'c-plain';
    VCFence: Result := 'c-fence';
    VCRelAcq: Result := 'c-relacq';
    VCAqRl: Result := 'c-aqrl';
    VCLrSc: Result := 'c-lrsc';
    VCLock: Result := 'c-lock';
  else
    Result := '?';
  end;
end;

{ ---- inline shapes: every global access is an asm block ---- }

function TryEnqueueInline(Value: Byte): Boolean;
var
  CH, CT, NH: UInt32;
begin
  case CurVariant of
    VIPlain:
      begin
        asm
          la   t0, Head
          lw   t1, 0(t0)
          sw   t1, CH
        end;
        asm
          la   t0, Tail
          lw   t1, 0(t0)
          sw   t1, CT
        end;
        NH := (CH + 1) and RingMask;
        if NH = CT then
          Exit(False);
        asm
          la   t0, Buffer
          lw   t2, CH
          add  t0, t0, t2
          lw   t1, Value
          sb   t1, 0(t0)
        end;
        asm
          la   t0, Head
          lw   t1, NH
          sw   t1, 0(t0)
        end;
      end;
    VIFence:
      begin
        asm
          la   t0, Head
          lw   t1, 0(t0)
          sw   t1, CH
          fence iorw, iorw
        end;
        asm
          la   t0, Tail
          lw   t1, 0(t0)
          sw   t1, CT
          fence iorw, iorw
        end;
        NH := (CH + 1) and RingMask;
        if NH = CT then
          Exit(False);
        asm
          la   t0, Buffer
          lw   t2, CH
          add  t0, t0, t2
          lw   t1, Value
          sb   t1, 0(t0)
        end;
        asm
          fence iorw, iorw
          la   t0, Head
          lw   t1, NH
          sw   t1, 0(t0)
        end;
      end;
    VIRelAcq:
      begin
        asm
          la   t0, Head
          lw   t1, 0(t0)
          sw   t1, CH
          fence r, rw
        end;
        asm
          la   t0, Tail
          lw   t1, 0(t0)
          sw   t1, CT
          fence r, rw
        end;
        NH := (CH + 1) and RingMask;
        if NH = CT then
          Exit(False);
        asm
          la   t0, Buffer
          lw   t2, CH
          add  t0, t0, t2
          lw   t1, Value
          sb   t1, 0(t0)
        end;
        asm
          fence rw, w
          la   t0, Head
          lw   t1, NH
          sw   t1, 0(t0)
        end;
      end;
    VIAqRl:
      begin
        asm
          la   t0, Head
          lr.w.aq t1, 0(t0)
          sw   t1, CH
        end;
        asm
          la   t0, Tail
          lr.w.aq t1, 0(t0)
          sw   t1, CT
        end;
        NH := (CH + 1) and RingMask;
        if NH = CT then
          Exit(False);
        asm
          la   t0, Buffer
          lw   t2, CH
          add  t0, t0, t2
          lw   t1, Value
          sb   t1, 0(t0)
        end;
        asm
          la   t0, Head
          lw   t1, NH
          amoswap.w.aqrl t2, t1, 0(t0)
        end;
      end;
    VILrSc:
      begin
        asm
          la   t0, Head
          lr.w.aq t1, 0(t0)
          sw   t1, CH
        end;
        asm
          la   t0, Tail
          lr.w.aq t1, 0(t0)
          sw   t1, CT
        end;
        NH := (CH + 1) and RingMask;
        if NH = CT then
          Exit(False);
        asm
          la   t0, Buffer
          lw   t2, CH
          add  t0, t0, t2
          lw   t1, Value
          sb   t1, 0(t0)
        end;
        asm
          la   t0, Head
          lw   t1, NH
.LesL:
          lr.w t2, 0(t0)
          sc.w.rl t3, t1, 0(t0)
          bnez t3, .LesL
        end;
      end;
    VILock:
      begin
        asm
          la   t0, QLock
.LeLk:
          li   t1, 1
          amoswap.w.aq t2, t1, 0(t0)
          bnez t2, .LeLk
        end;
        asm
          la   t0, Head
          lw   t1, 0(t0)
          sw   t1, CH
        end;
        asm
          la   t0, Tail
          lw   t1, 0(t0)
          sw   t1, CT
        end;
        NH := (CH + 1) and RingMask;
        if NH = CT then
        begin
          asm
            la   t0, QLock
            fence iorw, iorw
            sw   x0, 0(t0)
          end;
          Exit(False);
        end;
        asm
          la   t0, Buffer
          lw   t2, CH
          add  t0, t0, t2
          lw   t1, Value
          sb   t1, 0(t0)
        end;
        asm
          la   t0, Head
          lw   t1, NH
          sw   t1, 0(t0)
        end;
        asm
          la   t0, QLock
          fence iorw, iorw
          sw   x0, 0(t0)
        end;
      end;
  end;
  Result := True;
end;

function TryDequeueInline(out Value: Byte): Boolean;
var
  CT, CH: UInt32;
begin
  case CurVariant of
    VIPlain:
      begin
        asm
          la   t0, Tail
          lw   t1, 0(t0)
          sw   t1, CT
        end;
        asm
          la   t0, Head
          lw   t1, 0(t0)
          sw   t1, CH
        end;
        if CH = CT then
          Exit(False);
        asm
          la   t0, Buffer
          lw   t2, CT
          add  t0, t0, t2
          lbu  t1, 0(t0)
          lw   t2, Value
          sb   t1, 0(t2)
        end;
        asm
          la   t0, Tail
          lw   t1, CT
          addi t1, t1, 1
          andi t1, t1, 1023
          sw   t1, 0(t0)
        end;
      end;
    VIFence:
      begin
        asm
          la   t0, Tail
          lw   t1, 0(t0)
          sw   t1, CT
          fence iorw, iorw
        end;
        asm
          la   t0, Head
          lw   t1, 0(t0)
          sw   t1, CH
          fence iorw, iorw
        end;
        if CH = CT then
          Exit(False);
        asm
          la   t0, Buffer
          lw   t2, CT
          add  t0, t0, t2
          lbu  t1, 0(t0)
          lw   t2, Value
          sb   t1, 0(t2)
        end;
        asm
          fence iorw, iorw
          la   t0, Tail
          lw   t1, CT
          addi t1, t1, 1
          andi t1, t1, 1023
          sw   t1, 0(t0)
        end;
      end;
    VIRelAcq:
      begin
        asm
          la   t0, Tail
          lw   t1, 0(t0)
          sw   t1, CT
          fence r, rw
        end;
        asm
          la   t0, Head
          lw   t1, 0(t0)
          sw   t1, CH
          fence r, rw
        end;
        if CH = CT then
          Exit(False);
        asm
          la   t0, Buffer
          lw   t2, CT
          add  t0, t0, t2
          lbu  t1, 0(t0)
          lw   t2, Value
          sb   t1, 0(t2)
        end;
        asm
          fence rw, w
          la   t0, Tail
          lw   t1, CT
          addi t1, t1, 1
          andi t1, t1, 1023
          sw   t1, 0(t0)
        end;
      end;
    VIAqRl:
      begin
        asm
          la   t0, Tail
          lr.w.aq t1, 0(t0)
          sw   t1, CT
        end;
        asm
          la   t0, Head
          lr.w.aq t1, 0(t0)
          sw   t1, CH
        end;
        if CH = CT then
          Exit(False);
        asm
          la   t0, Buffer
          lw   t2, CT
          add  t0, t0, t2
          lbu  t1, 0(t0)
          lw   t2, Value
          sb   t1, 0(t2)
        end;
        asm
          la   t0, Tail
          lw   t1, CT
          addi t1, t1, 1
          andi t1, t1, 1023
          amoswap.w.aqrl t2, t1, 0(t0)
        end;
      end;
    VILrSc:
      begin
        asm
          la   t0, Tail
          lr.w.aq t1, 0(t0)
          sw   t1, CT
        end;
        asm
          la   t0, Head
          lr.w.aq t1, 0(t0)
          sw   t1, CH
        end;
        if CH = CT then
          Exit(False);
        asm
          la   t0, Buffer
          lw   t2, CT
          add  t0, t0, t2
          lbu  t1, 0(t0)
          lw   t2, Value
          sb   t1, 0(t2)
        end;
        asm
          la   t0, Tail
          lw   t1, CT
          addi t1, t1, 1
          andi t1, t1, 1023
.LdsL:
          lr.w t2, 0(t0)
          sc.w.rl t3, t1, 0(t0)
          bnez t3, .LdsL
        end;
      end;
    VILock:
      begin
        asm
          la   t0, QLock
.LdLk:
          li   t1, 1
          amoswap.w.aq t2, t1, 0(t0)
          bnez t2, .LdLk
        end;
        asm
          la   t0, Tail
          lw   t1, 0(t0)
          sw   t1, CT
        end;
        asm
          la   t0, Head
          lw   t1, 0(t0)
          sw   t1, CH
        end;
        if CH = CT then
        begin
          asm
            la   t0, QLock
            fence iorw, iorw
            sw   x0, 0(t0)
          end;
          Exit(False);
        end;
        asm
          la   t0, Buffer
          lw   t2, CT
          add  t0, t0, t2
          lbu  t1, 0(t0)
          lw   t2, Value
          sb   t1, 0(t2)
        end;
        asm
          la   t0, Tail
          lw   t1, CT
          addi t1, t1, 1
          andi t1, t1, 1023
          sw   t1, 0(t0)
        end;
        asm
          la   t0, QLock
          fence iorw, iorw
          sw   x0, 0(t0)
        end;
      end;
  end;
  Result := True;
end;

{ ---- call shapes: identical bodies to circularqueue.pas ---- }

function TryEnqueueCall(Value: Byte): Boolean;
var
  CH, CT, NH: UInt32;
  Space: Boolean;
begin
  Space := False;
  if CurVariant = VCLock then
    LockEnter(QLock);
  case CurVariant of
    VCPlain:
      begin
        CH := LoadPlain(Head);
        CT := LoadPlain(Tail);
      end;
    VCFence:
      begin
        CH := LoadPlain(Head);
        FenceFull;
        CT := LoadPlain(Tail);
        FenceFull;
      end;
    VCRelAcq:
      begin
        CH := ReadAcquire(Head);
        CT := ReadAcquire(Tail);
      end;
    VCAqRl, VCLrSc:
      begin
        CH := LoadAq(Head);
        CT := LoadAq(Tail);
      end;
    VCLock:
      begin
        CH := LoadPlain(Head);
        CT := LoadPlain(Tail);
      end;
  end;
  NH := (CH + 1) and RingMask;
  Space := NH <> CT;
  if Space then
  begin
    Buffer[CH] := Value;
    case CurVariant of
      VCPlain, VCLock: StorePlain(Head, NH);
      VCFence:
        begin
          FenceFull;
          StorePlain(Head, NH);
        end;
      VCRelAcq: WriteRelease(Head, NH);
      VCAqRl: StoreAqRl(Head, NH);
      VCLrSc: StoreLrSc(Head, NH);
    end;
  end;
  if CurVariant = VCLock then
    LockLeave(QLock);
  Result := Space;
end;

function TryDequeueCall(out Value: Byte): Boolean;
var
  CT, CH: UInt32;
  Has: Boolean;
begin
  Has := False;
  if CurVariant = VCLock then
    LockEnter(QLock);
  case CurVariant of
    VCPlain:
      begin
        CT := LoadPlain(Tail);
        CH := LoadPlain(Head);
      end;
    VCFence:
      begin
        CT := LoadPlain(Tail);
        FenceFull;
        CH := LoadPlain(Head);
        FenceFull;
      end;
    VCRelAcq:
      begin
        CT := ReadAcquire(Tail);
        CH := ReadAcquire(Head);
      end;
    VCAqRl, VCLrSc:
      begin
        CT := LoadAq(Tail);
        CH := LoadAq(Head);
      end;
    VCLock:
      begin
        CT := LoadPlain(Tail);
        CH := LoadPlain(Head);
      end;
  end;
  Has := CH <> CT;
  if Has then
  begin
    Value := Buffer[CT];
    case CurVariant of
      VCPlain, VCLock: StorePlain(Tail, (CT + 1) and RingMask);
      VCFence:
        begin
          FenceFull;
          StorePlain(Tail, (CT + 1) and RingMask);
        end;
      VCRelAcq: WriteRelease(Tail, (CT + 1) and RingMask);
      VCAqRl: StoreAqRl(Tail, (CT + 1) and RingMask);
      VCLrSc: StoreLrSc(Tail, (CT + 1) and RingMask);
    end;
  end;
  if CurVariant = VCLock then
    LockLeave(QLock);
  Result := Has;
end;

function TryEnqueue(Value: Byte): Boolean;
begin
  if CurVariant <= VILock then
    Result := TryEnqueueInline(Value)
  else
    Result := TryEnqueueCall(Value);
end;

function TryDequeue(out Value: Byte): Boolean;
begin
  if CurVariant <= VILock then
    Result := TryDequeueInline(Value)
  else
    Result := TryDequeueCall(Value);
end;

function xTaskCreatePinnedToCore(Entry: Pointer; Name: PChar; Stack: UInt32;
  Arg: Pointer; Prio: UInt32; Created: PPointer; Core: LongInt): LongInt; cdecl; external;
procedure vTaskDelay(Ticks: UInt32); cdecl; external;
procedure vTaskDelete(Handle: Pointer); cdecl; external;
function esp_timer_get_time: Int64; cdecl; external;

procedure ProducerWorker(Arg: Pointer); cdecl;
var
  PV, I: UInt32;
  Value: Byte;
begin
  PV := 0;
  repeat
    while LoadPlain(CurVariant) <= PV do
      vTaskDelay(1);
    PV := LoadPlain(CurVariant);
    FenceFull;
    I := 0;
    while I < ItemsPerVariant do
    begin
      Value := Byte(I and $FF);
      if TryEnqueue(Value) then
      begin
        Inc(I);
        Inc(ProdSum, Value);
      end;
    end;
    FenceFull;
    StorePlain(VariantDone, PV);
    FenceFull;
  until PV = VariantCount;
  vTaskDelete(nil);
end;

var
  V: UInt32;
  T0, T1, UseC: Int64;
  Value: Byte;
  Check: string;
begin
  WriteLn('cq_instrcost: inline vs call instruction-cost benchmark');
  WriteLn('cores=2 items-per-variant=', ItemsPerVariant,
    ' variants=', VariantCount);
  WriteLn('starting in 3s');
  vTaskDelay(300);

  if xTaskCreatePinnedToCore(@ProducerWorker, 'cqi-prod', 4096, nil, 22, nil, 1) <> 1 then
  begin
    WriteLn('ERROR: cannot create producer task');
    Halt(1);
  end;

  for V := 1 to VariantCount do
  begin
    ProdSum := 0;
    ConsSum := 0;
    ConsCount := 0;
    Corrupt := 0;
    Head := 0;
    Tail := 0;
    FenceFull;
    StorePlain(CurVariant, V);
    FenceFull;
    T0 := esp_timer_get_time;
    while ConsCount < ItemsPerVariant do
      if TryDequeue(Value) then
      begin
        if Value <> Byte(ConsCount and $FF) then
          Inc(Corrupt);
        Inc(ConsSum, Value);
        Inc(ConsCount);
      end;
    T1 := esp_timer_get_time;
    while LoadPlain(VariantDone) < V do
      vTaskDelay(1);
    UseC := T1 - T0;
    if (ProdSum = ConsSum) and (Corrupt = 0) then
      Check := 'ok'
    else
      Check := 'FAIL';
    WriteLn('variant=', VariantName(V), ' items=', ItemsPerVariant,
      ' usec=', UseC, ' items/s=', Int64(ItemsPerVariant) * 1000000 div UseC,
      ' checksum=', Check, ' corrupt=', Corrupt);
    vTaskDelay(20);
  end;

  WriteLn('cq_instrcost done');
end.
