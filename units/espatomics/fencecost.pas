{ fencecost.pas — per-encoding fence cost on the ESP32-S31 (Mosaico).

  cq_instrcost measured full `fence iorw,iorw` ≈ 8 ns vs narrow
  `fence r,rw`/`fence rw,w` ≈ 10 ns, but its inline variants differ in
  surrounding code layout. This probe isolates the ENCODING itself: asm
  loops with an IDENTICAL body that differ only in the fence's
  predecessor/successor sets, plus a no-fence baseline;
  fence cost = (T_encoding - T_none) / iteration, min of 3 reps.

  R-loop: lw + fence — the acquire-side shape (the fence waits for the
  load it precedes-ordering for). W-loop: sw + fence — the release-side
  shape (the fence drains the store it follows). Encodings whose
  predecessor set misses the loop's access (rw,w/ow,ow in the R-loop,
  r,rw/ir,ir in the W-loop) measure the fence's floor cost.

  Motivation: the 2026-11-06 demos acceptance measured the RTL-barrier
  SPSC shape consistently FASTER than the acquire/release leaf shape
  (+2.7% items/s, non-overlapping 5x interleaved A/B) although both
  carry 2 calls + 2 fences per item and equal static instruction counts
  — pointing at a per-encoding fence premium on this silicon.

  Build:  ESP32_SDK_PROJECT=.../hello-s31 \
          scripts/build.sh --soc esp32s31 units/espatomics/fencecost.pas
}

program fencecost;

{$mode objfpc}
{$H+}

procedure vTaskDelay(Ticks: UInt32); cdecl; external;
function esp_timer_get_time: Int64; cdecl; external;

const
  N = 2000000;
  Reps = 3;
  Count = 7;  { encodings incl. the no-fence baseline }

type
  TLoop = procedure(var V: UInt32; N: UInt32);

{$define LRW(name, access, enc)}
{$undef LRW}

{ R-loop bodies: lw a2,0(a0) then the fence }
procedure RNone(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: lw a2, 0(a0)
     addi a1, a1, -1
     bnez a1, .L1
end;

procedure RIorw(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: lw a2, 0(a0)
     fence iorw, iorw
     addi a1, a1, -1
     bnez a1, .L1
end;

procedure RRwRw(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: lw a2, 0(a0)
     fence rw, rw
     addi a1, a1, -1
     bnez a1, .L1
end;

procedure RRr(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: lw a2, 0(a0)
     fence r, rw
     addi a1, a1, -1
     bnez a1, .L1
end;

procedure RRwW(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: lw a2, 0(a0)
     fence rw, w
     addi a1, a1, -1
     bnez a1, .L1
end;

procedure RIr(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: lw a2, 0(a0)
     fence ir, ir
     addi a1, a1, -1
     bnez a1, .L1
end;

procedure ROw(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: lw a2, 0(a0)
     fence ow, ow
     addi a1, a1, -1
     bnez a1, .L1
end;

{ W-loop bodies: sw a2,0(a0) then the fence }
procedure WNone(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: sw a2, 0(a0)
     addi a1, a1, -1
     bnez a1, .L1
end;

procedure WIorw(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: sw a2, 0(a0)
     fence iorw, iorw
     addi a1, a1, -1
     bnez a1, .L1
end;

procedure WRwRw(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: sw a2, 0(a0)
     fence rw, rw
     addi a1, a1, -1
     bnez a1, .L1
end;

procedure WRr(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: sw a2, 0(a0)
     fence r, rw
     addi a1, a1, -1
     bnez a1, .L1
end;

procedure WRwW(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: sw a2, 0(a0)
     fence rw, w
     addi a1, a1, -1
     bnez a1, .L1
end;

procedure WIr(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: sw a2, 0(a0)
     fence ir, ir
     addi a1, a1, -1
     bnez a1, .L1
end;

procedure WOw(var V: UInt32; N: UInt32); assembler; nostackframe;
asm
.L1: sw a2, 0(a0)
     fence ow, ow
     addi a1, a1, -1
     bnez a1, .L1
end;

const
  Names: array[0..Count - 1] of PChar =
    ('none', 'iorw,iorw', 'rw,rw', 'r,rw', 'rw,w', 'ir,ir', 'ow,ow');
  RLoops: array[0..Count - 1] of TLoop =
    (@RNone, @RIorw, @RRwRw, @RRr, @RRwW, @RIr, @ROw);
  WLoops: array[0..Count - 1] of TLoop =
    (@WNone, @WIorw, @WRwRw, @WRr, @WRwW, @WIr, @WOw);

var
  X: UInt32;
  MinR, MinW: array[0..Count - 1] of Int64;
  Rep, K: LongInt;
  T0, T1: Int64;
begin
  X := 0;
  for K := 0 to Count - 1 do
  begin
    MinR[K] := High(Int64);
    MinW[K] := High(Int64);
  end;

  WriteLn('fencecost: per-encoding fence cost on ESP32-S31');
  WriteLn('iters=', N, ' reps=', Reps);
  WriteLn('starting in 3s');
  vTaskDelay(300);

  for Rep := 0 to Reps - 1 do
  begin
    for K := 0 to Count - 1 do
    begin
      T0 := esp_timer_get_time;
      RLoops[K](X, N);
      T1 := esp_timer_get_time;
      if T1 - T0 < MinR[K] then
        MinR[K] := T1 - T0;
      T0 := esp_timer_get_time;
      WLoops[K](X, N);
      T1 := esp_timer_get_time;
      if T1 - T0 < MinW[K] then
        MinW[K] := T1 - T0;
    end;
  end;

  WriteLn('encoding       R-loop-ns/it  W-loop-ns/it  R-fence-ns  W-fence-ns');
  for K := 0 to Count - 1 do
    WriteLn(Names[K]: 12,
      ' ', MinR[K] * 1000 div N: 12,
      ' ', MinW[K] * 1000 div N: 12,
      ' ', (MinR[K] - MinR[0]) * 1000 div N: 11,
      ' ', (MinW[K] - MinW[0]) * 1000 div N: 11);
  WriteLn('fencecost done');
end.
