{ dekker.pas — Dekker / store-buffer (SB) litmus on the ESP32-S31 dual-core
  RV32 (Mosaico), one access-mode shape per binary, split by compile-time
  macro. Companion of circularqueue.pas (message passing): this program
  probes the StoreLoad edge, the one ordering C11 acquire/release does NOT
  create.

  Modes (define exactly one):

    MODE_PLAIN      : fused asm "sw; lw" — the tightest store->load pair.
                      Expected on S31 silicon: r00 violations in the
                      hundreds per 500k rounds (RVWMO). Target-asm only,
                      not buildable for the host.
    MODE_RTLBARRIER : plain Pascal accesses separated by a
                      System.ReadWriteBarrier call (fence iorw,iorw on
                      RV32) — the only position that closes SB.
                      Expected: r00 = 0.
    MODE_ACQREL     : espatomics leaf primitives only:
                      WriteRelease(own flag, 1); ReadAcquire(other flag).
                      C11 acquire/release semantics; RVWMO theory and the
                      2026-11-02 silicon run both say this does NOT close
                      SB (r00 in the 350-430 / 500k range) — the demo
                      documents that acquire/release is not seq_cst.
                      On the host (x86) the same binary exercises the
                      stock backend (System.Interlocked* full barriers)
                      and closes the litmus (x86 is TSO).

  Control words (CurRound/Obs1/Done1) always go through opaque accessors:
  FPC has no volatile, so plain spin loops would cache into registers.
  On the host the accessors are plain non-inlined calls (an opaque call is
  itself the compiler barrier); FenceFull degrades to
  System.ReadWriteBarrier.

  Build (ESP32-S31 / Mosaico; build.sh auto-links usb_hs_console against
  the hello-s31 SDK project — no per-source directives, no -k--wrap):
    scripts/build.sh --soc esp32s31 -dMODE_PLAIN      units/espatomics/demos/dekker.pas
    scripts/build.sh --soc esp32s31 -dMODE_RTLBARRIER units/espatomics/demos/dekker.pas
    scripts/build.sh --soc esp32s31 -dMODE_ACQREL     units/espatomics/demos/dekker.pas
  Host (x86-linux, stock backend — functional check only, performance is
  not a host deliverable):
    fpc -dMODE_ACQREL -Tlinux units/espatomics/demos/dekker.pas

  Capture: usb_hs_console holds app_main up to 10 s waiting for the host
  CDC port (DTR); open the port within 10 s of boot. pyserial's open
  choreography (assert then drop DTR/RTS) hits the USJ-compatible
  auto-download pattern and resets the board — use a raw-fd reader or
  keep DTR asserted.
}

program dekker;

{$mode objfpc}
{$H+}

{$ifdef MODE_PLAIN}{$define MODE_SET}{$endif}
{$ifdef MODE_RTLBARRIER}
  {$ifdef MODE_SET}{$error define exactly one of MODE_PLAIN / MODE_RTLBARRIER / MODE_ACQREL}{$endif}
  {$define MODE_SET}
{$endif}
{$ifdef MODE_ACQREL}
  {$ifdef MODE_SET}{$error define exactly one of MODE_PLAIN / MODE_RTLBARRIER / MODE_ACQREL}{$endif}
  {$define MODE_SET}
{$endif}
{$ifndef MODE_SET}{$error define exactly one of MODE_PLAIN / MODE_RTLBARRIER / MODE_ACQREL}{$endif}
{$undef MODE_SET}

{$ifdef MODE_PLAIN}
  {$ifndef FREERTOS}
  {$error MODE_PLAIN uses target asm and builds on FreeRTOS targets only}
  {$endif}
{$endif}

{$ifdef FREERTOS}
  {$ifdef MODE_ACQREL}
  uses
    espatomics;
  {$endif}
{$else}
  { host (x86-linux): thread manager for BeginThread, SysUtils for the
    delay clock; MODE_ACQREL adds espatomics (stock backend) }
  uses
    cthreads, SysUtils
    {$ifdef MODE_ACQREL} , espatomics {$endif}
    ;
{$endif}

const
  {$IFDEF DEKKER_QUICK}
  Rounds = 100000;
  {$ELSE}
  Rounds = 500000;
  {$ENDIF}
  Chunk = 50000;
  LcgMul: UInt32 = 1103515245;
  LcgAdd: UInt32 = 12345;

var
  CurRound: UInt32;   { 1..Rounds, published by core 0 / the main thread }
  Flag0S: UInt32;     { litmus flags, internal SRAM }
  Gap0: array[0..63] of UInt32;
  Flag1S: UInt32;
  Gap1: array[0..63] of UInt32;
  Obs1: UInt32;       { core 1's litmus load result for the current round }
  Done1: UInt32;      { core 1 finished round Done1 }
  TotalRounds: UInt32;
  { outcome counts: 0=(r0,r1)=(0,0) forbidden by SC, 1=(0,1), 2=(1,0),
    3=(1,1) }
  Counts: array[0..3] of UInt32;

{ control words: keep every cross-thread access in an opaque call so
  nothing is cached in registers }
{$IFDEF FREERTOS}
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
{$ELSE}
{ opaque calls: the optimizer must reload the global at every access }
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
{$ENDIF}

{$IFDEF MODE_PLAIN}
function RvStoreLoad(var FSelf, FOther: UInt32): UInt32; assembler; nostackframe;
asm
  li a2, 1
  sw a2, 0(a0)
  lw a0, 0(a1)
end;
{$ENDIF}

procedure Pad(N: UInt32);
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

function NextPad(var Seed: UInt32): UInt32;
begin
  Seed := Seed * LcgMul + LcgAdd;
  Result := (Seed shr 16) and 255;
end;

{$IFDEF FREERTOS}
procedure vTaskDelay(Ticks: UInt32); cdecl; external;
procedure vTaskDelete(Handle: Pointer); cdecl; external;
function xTaskCreatePinnedToCore(Entry: Pointer; Name: PChar; Stack: UInt32;
  Arg: Pointer; Prio: UInt32; Created: PPointer; Core: LongInt): LongInt; cdecl; external;
{$ELSE}
{ host equivalents: no pinning, coarse busy-wait delay (functional
  fallback check only) }
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

procedure Core1Worker(Arg: Pointer); cdecl;
var
  R, R1, Seed, P, TR: UInt32;
begin
  TR := Load32(TotalRounds);
  Seed := UInt32($13579BDF);
  R := 0;
  while R < TR do
  begin
    while Load32(CurRound) <= R do ;
    R := Load32(CurRound);
    FenceFull;
    P := NextPad(Seed);
    Pad(P);
{$ifdef MODE_PLAIN}
    R1 := RvStoreLoad(Flag1S, Flag0S);
{$endif}
{$ifdef MODE_RTLBARRIER}
    Flag1S := 1;
    System.ReadWriteBarrier;   { the only position that closes SB }
    R1 := Flag0S;
{$endif}
{$ifdef MODE_ACQREL}
    WriteRelease(Flag1S, 1);
    R1 := ReadAcquire(Flag0S);
{$endif}
    FenceFull;
    Store32(Obs1, R1);
    FenceFull;
    Store32(Done1, R);
    if (R mod Chunk) = 0 then
      vTaskDelay(2);
  end;
  vTaskDelete(nil);
end;

var
  Seed, R, R0, R1, Idx: UInt32;
begin
  Store32(CurRound, 0);
  Store32(Flag0S, 0);
  Store32(Flag1S, 0);
  Store32(Obs1, 0);
  Store32(Done1, 0);
  for Idx := 0 to 3 do
    Counts[Idx] := 0;

  WriteLn('dekker: dual-core SB litmus, mode='
{$ifdef MODE_PLAIN}      + 'plain' {$endif}
{$ifdef MODE_RTLBARRIER} + 'rtlbarrier' {$endif}
{$ifdef MODE_ACQREL}     + 'acqrel' {$endif}
  );
  WriteLn('cores=2 rounds=', Rounds);

  Store32(TotalRounds, Rounds);
  { give the host-side serial listener time to attach after the
    post-flash reboot before the run starts }
  WriteLn('starting in 3s');
  vTaskDelay(300);

{$IFDEF FREERTOS}
  if xTaskCreatePinnedToCore(@Core1Worker, 'dek-core1', 4096, nil, 22, nil, 1) <> 1 then
  begin
    WriteLn('ERROR: cannot create core-1 task');
    Halt(1);
  end;
{$ELSE}
  HostTaskEntry := @Core1Worker;
  BeginThread(@HostTaskMain, nil);
{$ENDIF}

  Seed := UInt32($2468ACE1);
  R := 0;
  while R < Rounds do
  begin
    Inc(R);
    Store32(Flag0S, 0);
    Store32(Flag1S, 0);
    FenceFull;
    Store32(CurRound, R);
    FenceFull;
    Pad(NextPad(Seed));
{$ifdef MODE_PLAIN}
    R0 := RvStoreLoad(Flag0S, Flag1S);
{$endif}
{$ifdef MODE_RTLBARRIER}
    Flag0S := 1;
    System.ReadWriteBarrier;
    R0 := Flag1S;
{$endif}
{$ifdef MODE_ACQREL}
    WriteRelease(Flag0S, 1);
    R0 := ReadAcquire(Flag1S);
{$endif}
    while Load32(Done1) < R do ;
    FenceFull;
    R1 := Load32(Obs1);
    if (R0 = 0) and (R1 = 0) then
      Idx := 0
    else if R0 = 0 then
      Idx := 1
    else if R1 = 0 then
      Idx := 2
    else
      Idx := 3;
    Inc(Counts[Idx]);
    if (R mod Chunk) = 0 then
      vTaskDelay(2);
  end;

  WriteLn('outcome r00=', Counts[0], ' r01=', Counts[1],
    ' r10=', Counts[2], ' r11=', Counts[3],
    ' SC-violations=', Counts[0]);
  WriteLn('dekker done');
end.
