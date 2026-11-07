{ litmus.pas — six-family litmus suite on the ESP32-S31 dual-core RV32
  (Mosaico), one binary, runtime-sequenced variants. Companion of
  demos/dekker.pas (SB in depth) — this suite sweeps the classic families
  with the espatomics primitives and maps each family's MINIMAL ordering
  requirement onto the C11 construct that expresses it.

  Families, forbidden outcomes (SC), core mappings (2 cores — the
  mapping is chosen so the forbidden outcome is CONSTRUCTIBLE; a wrong
  pairing makes the same-core read trivially fresh and the family
  vacuous):

    SB   r0=0 ∧ r1=0                  P0/c0, P1/c1        (demos/dekker.pas in depth)
    MP   flag=new ∧ data=stale        producer/c1, consumer/c0
    LB   r0=1 ∧ r1=1                  P0/c0, P1/c1        (NOT (0,0) — (0,0) is SC-legal)
    WRC  r2=1 ∧ r3=0                  P0+P1 fused/c0, P2/c1
         (fusing P0+P1 is the only 2-core mapping where r3 can be stale:
          y is published on c0 and read cross-core; P0's x-store and
          P1's y-store are program-ordered on c0, so the family probes
          whether y's propagation to c1 can overtake x's)
    ISA2 r2=1 ∧ r3=0 (r4=x re-read)   same as WRC
    IRIW r1=1 ∧ r2=0 ∧ r3=1 ∧ r4=0    P0(wx)+P2/c0, P1(wy)+P3/c1
         (each reader's "sees-new" read is same-core, "may-be-stale" read
          cross-core; the readers run concurrently on the two cores)

  Shapes per family (C11 construct → espatomics primitive):

    bare     : fused asm bodies (both sides) — the codegen-gap-proof
               baseline; every family MUST violate here or the suite is
               not exercising its window
    acqrel   : MP/LB/WRC/ISA2 — atomic_store_explicit(release) +
               atomic_load_explicit(acquire) → WriteRelease + ReadAcquire
               (fence-based = A-cumulative: closes MP/LB/WRC/ISA2 per
               RVWMO theory; SB stays open — acquire/release cannot make
               the store→same-thread-load edge, and the leaf-call gap
               masks it anyway; IRIW is the MODEL-DIVERGENCE probe: C11
               acquire allows it, RVWMO cumulative-fence cycle argument
               forbids it — silicon decides)
    exchstore: SB only — atomic_exchange_explicit(acq_rel / seq_cst)
               flag-store → ExchangeAcqRel / ExchangeSeqCst (same
               amoswap.w.aqrl encoding, run under both names): the C11
               model does NOT close SB with an acq_rel exchange store
               (relaxed loads never enter S), RVWMO silicon measured it
               CLOSED (2026-11-02) — divergence probe 1
    scfence  : atomic_thread_fence(seq_cst) between the access pairs —
               the C11-correct answer for SB and IRIW →
               System.ReadWriteBarrier (fence iorw,iorw)

  Protocol: control words behind opaque accessors (Load32/Store32/
  FenceFull — FPC has no volatile); litmus accesses use the shape's
  style; LCG padding both sides; chunked vTaskDelay anti-starvation;
  per-variant forbidden counts printed at variant end.

  Build:
    S31:  ESP32_SDK_PROJECT=.../hello-s31 \
            scripts/build.sh --soc esp32s31 units/espatomics/litmus/litmus.pas
    S3:   ESP32_SDK_PROJECT=.../waveshare-s3 \
            scripts/build.sh --soc esp32s3 units/espatomics/litmus/litmus.pas
    x86:  fpc -Fu../../.. -Fu<units/espatomics> litmus.pas   (no FREERTOS:
          stock backend, TSO — every shape's forbidden outcome is
          unreachable; run validates the suite logic end to end)
}

program litmus;

{$mode objfpc}
{$H+}

uses
  espatomics
  {$IFNDEF FREERTOS}, cthreads, SysUtils{$ENDIF};

const
  RoundsPerVariant = 200000;
  Chunk = 50000;
  LcgMul: UInt32 = 1103515245;
  LcgAdd: UInt32 = 12345;

  VSB_Bare = 0;
  VSB_AcqRel = 1;
  VSB_ExchAcqRel = 2;
  VSB_ExchSeqCst = 3;
  VSB_ScFence = 4;
  VMP_Bare = 5;
  VMP_AcqRel = 6;
  VMP_ScFence = 7;
  VLB_Bare = 8;
  VLB_AcqRel = 9;
  VLB_ScFence = 10;
  VWRC_Bare = 11;
  VWRC_AcqRel = 12;
  VWRC_ScFence = 13;
  VISA2_Bare = 14;
  VISA2_AcqRel = 15;
  VISA2_ScFence = 16;
  VIRIW_Bare = 17;
  VIRIW_AcqRel = 18;
  VIRIW_ScFence = 19;
  VCount = 20;

var
  VStart: array[0..VCount] of UInt32;
  CurRound: UInt32;    { 1..total, published by main each round }
  Ready1: UInt32;      { worker at the line (writer store issued, if any) }
  Go: UInt32;          { main's litmus prefix done (WRC/ISA2/IRIW handoff) }
  Obs1: UInt32;        { worker's primary litmus load result }
  Obs2: UInt32;        { worker's secondary load result }
  Obs3: UInt32;        { ISA2 third read }
  Done1: UInt32;       { worker finished round Done1 }
  TotalRounds: UInt32;
  Counts: array[0..VCount - 1] of UInt32;

  { SB }
  SBFlag0: UInt32;
  SBFlag1: UInt32;
  { MP }
  MPData: UInt32;
  MPFlag: UInt32;
  { LB }
  LBX: UInt32;
  LBY: UInt32;
  { WRC / ISA2 }
  WRCX: UInt32;
  WRCY: UInt32;
  { IRIW }
  IRWX: UInt32;
  IRWY: UInt32;

{ ---- architecture: protocol accessors + fused bare bodies -------------- }
{ bare bodies are adjacent single-purpose sequences per architecture so
  the litmus window is codegen-gap-proof on every target }

{$IFDEF FREERTOS}{$IFDEF CPUXTENSA}
{ ---- Xtensa (ESP32-S3): stock backend fallback (Interlocked*) — plain
  Pascal accessors, no hand-written asm (the windowed ABI interaction
  with nostackframe asm is unresolved on this target) -------------------- }

function Load32(var V: UInt32): UInt32;
begin
  Result := V;
end;

procedure Store32(var V: UInt32; X: UInt32);
begin
  V := X;
end;

procedure FenceFull;
begin
  System.ReadWriteBarrier;
end;

function RvStoreLoad(var FSelf, FOther: UInt32): UInt32;
begin
  FSelf := 1;
  Result := FOther;
end;

procedure MpProdBare(var D, F: UInt32; V, R: UInt32);
begin
  D := V;
  F := R;
end;

procedure MpBareCons(var F, D: UInt32; out RF, RD: UInt32);
begin
  RF := F;
  RD := D;
end;

function LbBareP0(var X, Y: UInt32): UInt32;
begin
  Result := X;
  Y := 1;
end;

function LbBareP1(var Y, X: UInt32): UInt32;
begin
  Result := Y;
  X := 1;
end;

function WrcBareMain(var X, Y: UInt32): UInt32;
begin
  Result := X;
  Y := Result;
end;

procedure WrcBareP2(var Y, X: UInt32; out R2, R3: UInt32);
begin
  R2 := Y;
  R3 := X;
end;

procedure Isa2BareP2(var Y, X: UInt32; out R2, R3, R4: UInt32);
begin
  R2 := Y;
  R3 := X;
  R4 := X;
end;

procedure IrwBareMain(var X, Y: UInt32; out R1, R2: UInt32);
begin
  R1 := X;
  R2 := Y;
end;

procedure IrwBareWorker(var Y, X: UInt32; out R3, R4: UInt32);
begin
  R3 := Y;
  R4 := X;
end;

{$ELSE}
{ ---- RV32 (ESP32-S31) --------------------------------------------------- }

function Load32(var V: UInt32): UInt32; assembler; nostackframe;
asm
  lw a0, 0(a0)
end;

procedure Store32(var V: UInt32; X: UInt32); assembler; nostackframe;
asm
  sw a1, 0(a0)
end;

procedure FenceFull; assembler; nostackframe;
asm
  fence iorw, iorw
end;

function RvStoreLoad(var FSelf, FOther: UInt32): UInt32; assembler; nostackframe;
asm
  li a2, 1
  sw a2, 0(a0)
  lw a0, 0(a1)
end;

procedure MpProdBare(var D, F: UInt32; V, R: UInt32); assembler; nostackframe;
asm
  sw a2, 0(a0)
  sw a3, 0(a1)
end;

procedure MpBareCons(var F, D: UInt32; out RF, RD: UInt32); assembler; nostackframe;
asm
  lw a4, 0(a0)
  sw a4, 0(a2)
  lw a5, 0(a1)
  sw a5, 0(a3)
end;

function LbBareP0(var X, Y: UInt32): UInt32; assembler; nostackframe;
asm
  lw a2, 0(a0)
  li a3, 1
  sw a3, 0(a1)
  mv a0, a2
end;

function LbBareP1(var Y, X: UInt32): UInt32; assembler; nostackframe;
asm
  lw a2, 0(a0)
  li a3, 1
  sw a3, 0(a1)
  mv a0, a2
end;

function WrcBareMain(var X, Y: UInt32): UInt32; assembler; nostackframe;
asm
  lw a2, 0(a0)
  sw a2, 0(a1)
  mv a0, a2
end;

procedure WrcBareP2(var Y, X: UInt32; out R2, R3: UInt32); assembler; nostackframe;
asm
  lw a4, 0(a0)
  sw a4, 0(a2)
  lw a5, 0(a1)
  sw a5, 0(a3)
end;

procedure Isa2BareP2(var Y, X: UInt32; out R2, R3, R4: UInt32); assembler; nostackframe;
asm
  lw a5, 0(a0)
  sw a5, 0(a2)
  lw a6, 0(a1)
  sw a6, 0(a3)
  lw a6, 0(a1)
  sw a6, 0(a4)
end;

procedure IrwBareMain(var X, Y: UInt32; out R1, R2: UInt32); assembler; nostackframe;
asm
  lw a4, 0(a0)
  sw a4, 0(a2)
  lw a5, 0(a1)
  sw a5, 0(a3)
end;

procedure IrwBareWorker(var Y, X: UInt32; out R3, R4: UInt32); assembler; nostackframe;
asm
  lw a4, 0(a0)
  sw a4, 0(a2)
  lw a5, 0(a1)
  sw a5, 0(a3)
end;

{$ENDIF}
{$ELSE}
{ ---- host (x86-linux): plain-call bodies — TSO hardware makes every
  shape's forbidden outcome unreachable; this run validates the suite
  LOGIC end to end, not weak memory -------------------------------------- }

function Load32(var V: UInt32): UInt32;
begin
  Result := V;
end;

procedure Store32(var V: UInt32; X: UInt32);
begin
  V := X;
end;

procedure FenceFull;
begin
  System.ReadWriteBarrier;
end;

function RvStoreLoad(var FSelf, FOther: UInt32): UInt32;
begin
  FSelf := 1;
  Result := FOther;
end;

procedure MpProdBare(var D, F: UInt32; V, R: UInt32);
begin
  D := V;
  F := R;
end;

procedure MpBareCons(var F, D: UInt32; out RF, RD: UInt32);
begin
  RF := F;
  RD := D;
end;

function LbBareP0(var X, Y: UInt32): UInt32;
begin
  Result := X;
  Y := 1;
end;

function LbBareP1(var Y, X: UInt32): UInt32;
begin
  Result := Y;
  X := 1;
end;

function WrcBareMain(var X, Y: UInt32): UInt32;
begin
  Result := X;
  Y := Result;
end;

procedure WrcBareP2(var Y, X: UInt32; out R2, R3: UInt32);
begin
  R2 := Y;
  R3 := X;
end;

procedure Isa2BareP2(var Y, X: UInt32; out R2, R3, R4: UInt32);
begin
  R2 := Y;
  R3 := X;
  R4 := X;
end;

procedure IrwBareMain(var X, Y: UInt32; out R1, R2: UInt32);
begin
  R1 := X;
  R2 := Y;
end;

procedure IrwBareWorker(var Y, X: UInt32; out R3, R4: UInt32);
begin
  R3 := Y;
  R4 := X;
end;

{$ENDIF}

{ ---- padding ----------------------------------------------------------- }

procedure Pad(N: UInt32); inline;
var
  I: UInt32;
begin
  for I := 1 to N do
  begin
    asm
      nop
    end;
  end;
end;

function NextPad(var Seed: UInt32): UInt32; inline;
begin
  Seed := Seed * LcgMul + LcgAdd;
  Result := (Seed shr 16) and 255;
end;

function VariantOf(R: UInt32): UInt32; inline;
var
  I: UInt32;
begin
  Result := VCount - 1;
  for I := VCount - 1 downto 1 do
    if R < VStart[I] then
      Result := I - 1;
end;

{ ---- task layer --------------------------------------------------------- }

{$IFDEF FREERTOS}
procedure vTaskDelay(Ticks: UInt32); cdecl; external;
procedure vTaskDelete(Handle: Pointer); cdecl; external;
function xTaskCreatePinnedToCore(Entry: Pointer; Name: PChar; Stack: UInt32;
  Arg: Pointer; Prio: UInt32; Created: PPointer; Core: LongInt): LongInt; cdecl; external;
{$ELSE}
type
  TCdeclTask = procedure(Arg: Pointer); cdecl;
var
  HostTaskEntry: Pointer;

function HostTaskMain(Arg: Pointer): PtrInt;
begin
  TCdeclTask(HostTaskEntry)(Arg);
  Result := 0;
end;

procedure vTaskDelay(Ticks: UInt32);
var
  Until_: QWord;
begin
  Until_ := GetTickCount64 + QWord(Ticks) * 10;   { 100 Hz tick semantics }
  while GetTickCount64 < Until_ do ;
end;

procedure vTaskDelete(Handle: Pointer);
begin
end;
{$ENDIF}

{ ---- core-1 worker: second participant of every family ----------------- }

procedure Worker(Arg: Pointer); cdecl;
var
  R, V, R1, Seed, TR: UInt32;
begin
  TR := Load32(TotalRounds);
  Seed := UInt32($13579BDF);
  R := 0;
  while R < TR do
  begin
    while Load32(CurRound) <= R do ;
    R := Load32(CurRound);
    FenceFull;
    V := VariantOf(R);
    if V >= VIRIW_Bare then
    begin
      IRWY := 1;            { IRIW P3's writer store — unflushed, issued
                              BEFORE Ready1 so both writer stores are in
                              flight before either reader fires }
      FenceFull;
    end;
    Store32(Ready1, R);     { at the line — main now fires its half }
    FenceFull;
    if (V >= VWRC_Bare) and (V <= VISA2_ScFence) then
    begin
      while Load32(Go) < R do ;   { WRC/ISA2: P2 reads only after the
                                    P0+P1 prefix (x=1, y published) }
      FenceFull;
    end
    else if V >= VIRIW_Bare then
    begin
      while Load32(Go) < R do ;   { IRIW: readers fire only after BOTH
                                    writer stores are issued }
      FenceFull;
    end;
    Pad(NextPad(Seed));
    case V of
      VSB_Bare:
        begin
          R1 := RvStoreLoad(SBFlag1, SBFlag0);
          Store32(Obs1, R1);
        end;
      VSB_AcqRel:
        begin
          WriteRelease(SBFlag1, 1);
          R1 := ReadAcquire(SBFlag0);
          Store32(Obs1, R1);
        end;
      VSB_ExchAcqRel:
        begin
          AtomicExchangeAcqRel(SBFlag1, 1);
          R1 := SBFlag0;
          Store32(Obs1, R1);
        end;
      VSB_ExchSeqCst:
        begin
          AtomicExchangeSeqCst(SBFlag1, 1);
          R1 := SBFlag0;
          Store32(Obs1, R1);
        end;
      VSB_ScFence:
        begin
          SBFlag1 := 1;
          System.ReadWriteBarrier;
          R1 := SBFlag0;
          Store32(Obs1, R1);
        end;
      VMP_Bare:
        MpProdBare(MPData, MPFlag, R and $FF, R);
      VMP_AcqRel:
        begin
          MPData := R and $FF;
          WriteRelease(MPFlag, R);
        end;
      VMP_ScFence:
        begin
          MPData := R and $FF;
          System.ReadWriteBarrier;
          MPFlag := R;
        end;
      VLB_Bare:
        begin
          R1 := LbBareP1(LBY, LBX);
          Store32(Obs1, R1);
        end;
      VLB_AcqRel:
        begin
          R1 := ReadAcquire(LBY);
          LBX := 1;
          Store32(Obs1, R1);
        end;
      VLB_ScFence:
        begin
          R1 := LBY;
          System.ReadWriteBarrier;
          LBX := 1;
          Store32(Obs1, R1);
        end;
      VWRC_Bare:
        begin
          while Load32(Go) < R do ;
          FenceFull;
          WrcBareP2(WRCY, WRCX, Obs1, Obs2);
        end;
      VWRC_AcqRel:
        begin
          while Load32(Go) < R do ;
          FenceFull;
          Store32(Obs1, ReadAcquire(WRCY));
          Store32(Obs2, WRCX);
        end;
      VWRC_ScFence:
        begin
          while Load32(Go) < R do ;
          FenceFull;
          Store32(Obs1, WRCY);
          System.ReadWriteBarrier;
          Store32(Obs2, WRCX);
        end;
      VISA2_Bare:
        begin
          while Load32(Go) < R do ;
          FenceFull;
          Isa2BareP2(WRCY, WRCX, Obs1, Obs2, Obs3);
        end;
      VISA2_AcqRel:
        begin
          while Load32(Go) < R do ;
          FenceFull;
          Store32(Obs1, ReadAcquire(WRCY));
          Store32(Obs2, WRCX);
          Store32(Obs3, WRCX);
        end;
      VISA2_ScFence:
        begin
          while Load32(Go) < R do ;
          FenceFull;
          Store32(Obs1, WRCY);
          System.ReadWriteBarrier;
          Store32(Obs2, WRCX);
          Store32(Obs3, WRCX);
        end;
      VIRIW_Bare:
        IrwBareWorker(IRWY, IRWX, Obs1, Obs2);
      VIRIW_AcqRel:
        begin
          Store32(Obs1, ReadAcquire(IRWY));
          Store32(Obs2, IRWX);
        end;
      VIRIW_ScFence:
        begin
          Store32(Obs1, IRWY);
          System.ReadWriteBarrier;
          Store32(Obs2, IRWX);
        end;
    end;
    if (V <= VSB_ScFence) or ((V >= VLB_Bare) and (V <= VLB_ScFence)) then
      Store32(Obs1, R1);    { SB/LB: publish the worker's litmus load —
                              without this the main-side check classifies
                              against a stale constant }
    FenceFull;
    Store32(Done1, R);
    if (R mod Chunk) = 0 then
      vTaskDelay(2);
  end;
  vTaskDelete(nil);
end;

const
  Names: array[0..VCount - 1] of PChar =
    ('sb-bare', 'sb-acqrel', 'sb-exch-acqrel', 'sb-exch-seqcst', 'sb-scfence',
     'mp-bare', 'mp-acqrel', 'mp-scfence',
     'lb-bare', 'lb-acqrel', 'lb-scfence',
     'wrc-bare', 'wrc-acqrel', 'wrc-scfence',
     'isa2-bare', 'isa2-acqrel', 'isa2-scfence',
     'iriw-bare', 'iriw-acqrel', 'iriw-scfence');

procedure PrintCounts(V: UInt32);
begin
  WriteLn('variant=', Names[V], ' forbidden=', Counts[V]);
  if Counts[V] > 0 then
    WriteLn('  ^ VIOLATION');
end;

{ ---- main: first participant of every family + classification ---------- }

var
  Seed, R, V, R0, R1, R2, R3, R4, RF, RD, I: UInt32;
begin
  Store32(CurRound, 0);
  Store32(Go, 0);
  Store32(Obs1, 0);
  Store32(Obs2, 0);
  Store32(Obs3, 0);
  Store32(Done1, 0);
  for V := 0 to VCount - 1 do
    Counts[V] := 0;

  WriteLn('litmus: six-family suite (S31 weak / S3+x86 TSO-like)');
  WriteLn('cores=2 rounds-per-variant=', RoundsPerVariant, ' variants=', VCount);

  VStart[0] := 1;
  for V := 1 to VCount do
    VStart[V] := VStart[V - 1] + RoundsPerVariant;
  Store32(TotalRounds, VStart[VCount] - 1);

  { usb_hs_console owns stdout once the CDC is up; its auto-download DTR
    window covers the first ~10 s and any open/reopen in that window can
    bounce the board to download mode. Hold the run until the window has
    closed so a capture opened at t>10 s sees the whole run. }
  WriteLn('holding 12s for the DTR window');
  vTaskDelay(1200);
  WriteLn('=== go ===');

{$IFDEF FREERTOS}
  if xTaskCreatePinnedToCore(@Worker, 'lit-c1', 4096, nil, 22, nil, 1) <> 1 then
  begin
    WriteLn('ERROR: cannot create core-1 task');
    Halt(1);
  end;
{$ELSE}
  HostTaskEntry := @Worker;
  BeginThread(@HostTaskMain, nil);
{$ENDIF}

  Seed := UInt32($2468ACE1);
  R := 0;
  while R < VStart[VCount] - 1 do
  begin
    Inc(R);
    V := VariantOf(R);
    Pad(NextPad(Seed));
    case V of
      VSB_Bare, VSB_AcqRel, VSB_ExchAcqRel, VSB_ExchSeqCst, VSB_ScFence:
        begin
          Store32(SBFlag0, 0);
          Store32(SBFlag1, 0);
          FenceFull;
          Store32(CurRound, R);
          FenceFull;
          while Load32(Ready1) < R do ;
          FenceFull;
          Pad(NextPad(Seed));
          case V of
            VSB_Bare:
              R0 := RvStoreLoad(SBFlag0, SBFlag1);
            VSB_AcqRel:
              begin
                WriteRelease(SBFlag0, 1);
                R0 := ReadAcquire(SBFlag1);
              end;
            VSB_ExchAcqRel:
              begin
                AtomicExchangeAcqRel(SBFlag0, 1);
                R0 := SBFlag1;
              end;
            VSB_ExchSeqCst:
              begin
                AtomicExchangeSeqCst(SBFlag0, 1);
                R0 := SBFlag1;
              end;
            VSB_ScFence:
              begin
                SBFlag0 := 1;
                System.ReadWriteBarrier;
                R0 := SBFlag1;
              end;
          end;
          while Load32(Done1) < R do ;
          FenceFull;
          R1 := Load32(Obs1);
          if (R0 = 0) and (R1 = 0) then
            Inc(Counts[V]);
          if R = VStart[V + 1] - 1 then
          begin
            PrintCounts(V);
            vTaskDelay(50);
          end
          else if (R mod Chunk) = 0 then
            vTaskDelay(2);
        end;
      VMP_Bare, VMP_AcqRel, VMP_ScFence:
        begin
          FenceFull;
          Store32(CurRound, R);
          FenceFull;
          while Load32(Ready1) < R do ;
          FenceFull;
          I := 0;
          case V of
            VMP_Bare:
              begin
                while MPFlag < R do
                begin
                  Inc(I);
                  if (I and 1023) = 0 then
                    vTaskDelay(0);
                end;
                MpBareCons(MPFlag, MPData, RF, RD);
                if (RF >= R) and (RD <> (R and $FF)) then
                  Inc(Counts[V]);
              end;
            VMP_AcqRel:
              begin
                while ReadAcquire(MPFlag) < R do
                  vTaskDelay(0);
                RD := MPData;
                if RD <> (R and $FF) then
                  Inc(Counts[V]);
              end;
            VMP_ScFence:
              begin
                while MPFlag < R do
                begin
                  Inc(I);
                  if (I and 1023) = 0 then
                    vTaskDelay(0);
                end;
                System.ReadWriteBarrier;
                RD := MPData;
                if RD <> (R and $FF) then
                  Inc(Counts[V]);
              end;
          end;
          if R = VStart[V + 1] - 1 then
          begin
            PrintCounts(V);
            vTaskDelay(50);
          end
          else if (R mod Chunk) = 0 then
            vTaskDelay(2);
        end;
      VLB_Bare, VLB_AcqRel, VLB_ScFence:
        begin
          Store32(LBX, 0);
          Store32(LBY, 0);
          FenceFull;
          Store32(CurRound, R);
          FenceFull;
          while Load32(Ready1) < R do ;
          FenceFull;
          Pad(NextPad(Seed));
          case V of
            VLB_Bare:
              R0 := LbBareP0(LBX, LBY);
            VLB_AcqRel:
              begin
                R0 := ReadAcquire(LBX);
                LBY := 1;
              end;
            VLB_ScFence:
              begin
                R0 := LBX;
                System.ReadWriteBarrier;
                LBY := 1;
              end;
          end;
          while Load32(Done1) < R do ;
          FenceFull;
          R1 := Load32(Obs1);
          if (R0 = 1) and (R1 = 1) then
            Inc(Counts[V]);
          if R = VStart[V + 1] - 1 then
          begin
            PrintCounts(V);
            vTaskDelay(50);
          end
          else if (R mod Chunk) = 0 then
            vTaskDelay(2);
        end;
      VWRC_Bare, VWRC_AcqRel, VWRC_ScFence:
        begin
          Store32(WRCX, 0);
          Store32(WRCY, 0);
          FenceFull;
          Store32(CurRound, R);
          FenceFull;
          while Load32(Ready1) < R do ;
          FenceFull;
          Pad(NextPad(Seed));
          WRCX := 1;          { P0's data store — deliberately UNFLUSHED: its
                                 late propagation to core 1 is the WRC window }
          case V of
            VWRC_Bare:
              R1 := WrcBareMain(WRCX, WRCY);
            VWRC_AcqRel:
              begin
                R1 := WRCX;
                WriteRelease(WRCY, R1);
              end;
            VWRC_ScFence:
              begin
                R1 := WRCX;
                System.ReadWriteBarrier;
                WRCY := R1;
              end;
          end;
          FenceFull;
          Store32(Go, R);
          while Load32(Done1) < R do ;
          FenceFull;
          R2 := Load32(Obs1);
          R3 := Load32(Obs2);
          if (R2 = 1) and (R3 = 0) then
            Inc(Counts[V]);
          if R = VStart[V + 1] - 1 then
          begin
            PrintCounts(V);
            vTaskDelay(50);
          end
          else if (R mod Chunk) = 0 then
            vTaskDelay(2);
        end;
      VISA2_Bare, VISA2_AcqRel, VISA2_ScFence:
        begin
          Store32(WRCX, 0);
          Store32(WRCY, 0);
          FenceFull;
          Store32(CurRound, R);
          FenceFull;
          while Load32(Ready1) < R do ;
          FenceFull;
          Pad(NextPad(Seed));
          WRCX := 1;          { P0's data store — deliberately UNFLUSHED }
          case V of
            VISA2_Bare:
              R1 := WrcBareMain(WRCX, WRCY);
            VISA2_AcqRel:
              begin
                R1 := WRCX;
                WriteRelease(WRCY, R1);
              end;
            VISA2_ScFence:
              begin
                R1 := WRCX;
                System.ReadWriteBarrier;
                WRCY := R1;
              end;
          end;
          FenceFull;
          Store32(Go, R);
          while Load32(Done1) < R do ;
          FenceFull;
          R2 := Load32(Obs1);
          R3 := Load32(Obs2);
          R4 := Load32(Obs3);
          if (R2 = 1) and (R3 = 0) then
            Inc(Counts[V]);
          if R = VStart[V + 1] - 1 then
          begin
            PrintCounts(V);
            vTaskDelay(50);
          end
          else if (R mod Chunk) = 0 then
            vTaskDelay(2);
        end;
      VIRIW_Bare, VIRIW_AcqRel, VIRIW_ScFence:
        begin
          Store32(IRWX, 0);
          Store32(IRWY, 0);
          FenceFull;
          Store32(CurRound, R);
          FenceFull;
          while Load32(Ready1) < R do ;   { worker's writer store issued }
          FenceFull;
          IRWX := 1;          { P0's store — deliberately UNFLUSHED: its late
                                 propagation to core 1 is the IRIW window }
          FenceFull;
          Store32(Go, R);     { both writer stores issued — readers fire }
          Pad(NextPad(Seed));
          case V of
            VIRIW_Bare:
              IrwBareMain(IRWX, IRWY, R1, R2);
            VIRIW_AcqRel:
              begin
                R1 := ReadAcquire(IRWX);
                R2 := IRWY;
              end;
            VIRIW_ScFence:
              begin
                R1 := IRWX;
                System.ReadWriteBarrier;
                R2 := IRWY;
              end;
          end;
          while Load32(Done1) < R do ;
          FenceFull;
          R3 := Load32(Obs1);
          R4 := Load32(Obs2);
          if (R1 = 1) and (R2 = 0) and (R3 = 1) and (R4 = 0) then
            Inc(Counts[V]);
          if R = VStart[V + 1] - 1 then
          begin
            PrintCounts(V);
            vTaskDelay(50);
          end
          else if (R mod Chunk) = 0 then
            vTaskDelay(2);
        end;
    end;
  end;

  WriteLn('litmus done');
end.
