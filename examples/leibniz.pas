program leibniz;
{ Origin: https://github.com/niklas-heer/speed-comparison/blob/master/src/leibniz.pas }
{ Computes Pi using the Leibniz series. }

{ ESP32-S3 single-precision performance notes (vs the C twin under
  speed-compare/leibniz.c, both built -O2 for Xtensa lx7hf):

  The series is the usual alternating sum. This example uses Single only;
  numerical quality is not the point — the goal is to see what the FPC
  Xtensa backend emits for float ops.

  Hardware FPU coverage on S3:
    - add / sub / mul of Single become add.s / sub.s / mul.s (and neg.s).
    - There is no one-instruction div.s. GCC calls ROM __divsf3, a short
      FPU reciprocal iteration (div0.s / maddn.s / divn.s, ~30 insns, no
      nested calls). FPC routes the built-in Single "/" through SoftFloat
      float32_div instead (compiler/xtensa/ncpuadd.pas first_addfloat
      excludes slashn from the hard-FPU path and falls into
      first_addfloat_soft). That helper works on integer bit-fields with
      several call8s (ESTIMATEDIV64TO32, MUL32TO64, SUB64, ADD64,
      ROUNDANDPACKFLOAT32) and no .s ops.

  Source-level changes in this file (and why):

  1. Locals inside a nested procedure, not program-level vars.
     A program var becomes a unit global (U_$P$LEIBNIZ_$$_PI / _X in BSS).
     Every use then costs l32r of the address plus lsi/ssi. Locals of
     run_leibniz live at fixed a1 offsets; -O2 can also treat them as
     regvars when the live range allows. t0/t1 stay in the outer var
     section so the main body can print the elapsed time after the call.

  2. x := -x instead of x := x * -1.
     Unary minus of Single lowers to neg.s. The multiply form loaded a
     -1.0 constant from rodata (l32r + lsi) and used mul.s.

  3. Running integer denominator instead of (2*i - 1) each iteration.
     The first term uses denom = 3 (= 2*2 - 1); each later term adds 2.
     That replaces slli + addi -1 with a single addi +2, matching the
     strength reduction GCC applies on the C side.

  4. Call ROM __divsf3 instead of the built-in Single "/".
     The operator cannot be redirected from user code; an explicit cdecl
     external matches libgcc's integer-register float ABI (Xtensa FPC
     already passes Single in GPRs for cdecl). The IDF ROM libgcc script
     resolves __divsf3 to an absolute address, so no extra library is
     needed. This is an application workaround; the durable fix is still
     teaching slashn of s32real to emit __divsf3 in the compiler.

  Remaining gaps vs C:
    - pi / x / denom may still spill to the stack around the call in the
      current -O2 output; C keeps pi in an F register and the denominator
      in an address register across the iteration.
    - FPC mode does not enable excess precision; the loop stays Single.
      writeln(pi) widens once after the loop (float32_to_float64) and is
      outside the timed series itself.
}

uses
  idfheap, TypInfo;

{ Microseconds since boot, monotonic — IDF's own timer. Declared here so the
  example needs no extra unit; esp_timer is already in the RTL's link list. }
function esp_timer_get_time: int64; cdecl; external name 'esp_timer_get_time';

{ ROM / libgcc single divide (FPU reciprocal). Same ABI as GCC's call. }
function __divsf3(a, b: single): single; cdecl; external name '__divsf3';

var
  { Outer so main can print the interval after run_leibniz returns. }
  t0, t1: int64;

  procedure run_leibniz;
  var
    rounds, i, denom: longint;
    { Locals (not program globals): avoid per-iteration l32r to BSS. }
    pi, x: single; {double;}
  begin
    WriteLn('Leibniz Pi of type ' + PTypeInfo(TypeInfo(pi))^.Name);
    rounds := 1000000;
    pi := 1.0;
    x := 1.0;
    { 2*i-1 for i=2; Inc(denom, 2) each iteration (strength reduction). }
    denom := 3;
    t0 := esp_timer_get_time;
    for i := 2 to rounds + 1 do
    begin
      x := -x;                 { neg.s — not mul.s by a -1.0 literal }
      { Avoid SoftFloat float32_div; call ROM __divsf3 like GCC. }
      pi := pi + __divsf3(x, Single(denom));
      Inc(denom, 2);
    end;
    t1 := esp_timer_get_time;

    pi := pi * 4;

    writeln(pi);
    writeln('rounds: ', rounds);
  end;

begin
  run_leibniz();

  writeln('loop: ', t1 - t0, ' us = ', (t1 - t0) / 1000:0:3, ' ms');
end.
