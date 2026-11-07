{ circularqueue.pas — minimal-shape SPSC ring on the ESP32-S31 (Mosaico),
  one access-mode shape per binary, split by compile-time macro. Producer
  on core 1, consumer (main) on core 0, 1M bytes through a 1024-slot ring.

  The shape is the minimal correct SPSC ordering per item:
    producer: bare own-cursor read, acquire-load of Tail, data write,
              release-store of Head
    consumer: bare own-cursor read, acquire-load of Head, data read,
              release-store of Tail
  and the ONLY variable is how those accesses are spelled:

    MODE_PLAIN      : bare reads/writes everywhere. Weak memory plus
                      register caching: the expected result on S31 is a
                      permanent livelock (stale cached cursor) or silent
                      corruption — the broken control. Highest raw speed.
    MODE_RTLBARRIER : plain accesses separated by the RTL's full-barrier
                      calls (System.ReadWriteBarrier / WriteBarrier /
                      ReadBarrier, one call each, 4-5 per item).
                      Expected: 0 errors, slowest.
    MODE_ACQREL     : espatomics leaf primitives only — ReadAcquire /
                      WriteRelease, one call per cursor access, narrow
                      fences inside the leaves. C11 message-passing
                      shape. Expected: 0 errors, >= the barrier shape's
                      throughput. On the host (x86) the same binary
                      exercises the stock backend (System.Interlocked*
                      full barriers).

  Console: build.sh auto-links usb_hs_console against the hello-s31 SDK
  project (no per-source directives, no -k--wrap). Capture within 10 s of
  boot (DTR window); see dekker.pas for the pyserial caveat.

  Build (ESP32-S31 / Mosaico):
    scripts/build.sh --soc esp32s31 -dMODE_PLAIN      units/espatomics/demos/circularqueue.pas
    scripts/build.sh --soc esp32s31 -dMODE_RTLBARRIER units/espatomics/demos/circularqueue.pas
    scripts/build.sh --soc esp32s31 -dMODE_ACQREL     units/espatomics/demos/circularqueue.pas
  Host (x86-linux, stock backend — functional check only, performance is
  not a host deliverable):
    fpc -dMODE_ACQREL -Tlinux units/espatomics/demos/circularqueue.pas
}

program circularqueue;

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

{$ifdef FREERTOS}
  {$ifdef MODE_ACQREL}
  uses
    espatomics;
  {$endif}
{$else}
  { host (x86-linux): thread manager for BeginThread, SysUtils for the
    delay/timing clock; MODE_ACQREL adds espatomics (stock backend) }
  uses
    cthreads, SysUtils
    {$ifdef MODE_ACQREL} , espatomics {$endif}
    ;
{$endif}

const
  RingSize = 1024;
  RingMask = RingSize - 1;
  Items = 1000000;

var
  Buffer: array[0..RingMask] of Byte;
  Head: UInt32;   { producer cursor — written only by the producer }
  Tail: UInt32;   { consumer cursor — written only by the consumer }
  ConsSum, ConsCount, Corrupt: UInt32;

{$IFDEF FREERTOS}
procedure vTaskDelay(Ticks: UInt32); cdecl; external;
procedure vTaskDelete(Handle: Pointer); cdecl; external;
function esp_timer_get_time: Int64; cdecl; external;
function xTaskCreatePinnedToCore(Entry: Pointer; Name: PChar; Stack: UInt32;
  Arg: Pointer; Prio: UInt32; Created: PPointer; Core: LongInt): LongInt; cdecl; external;
{$ELSE}
{ host equivalents: no pinning, ms-granular clock, coarse busy-wait delay
  (functional fallback check only) }
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

function esp_timer_get_time: Int64;
begin
  Result := Int64(GetTickCount64) * 1000;         { ms-accurate microseconds }
end;

procedure vTaskDelete(Handle: Pointer);
begin
end;
{$ENDIF}

function TryEnqueue(Value: Byte): Boolean;
var
  NH: UInt32;
begin
  NH := (Head + 1) and RingMask;
{$ifdef MODE_PLAIN}
  if NH = Tail then
    Exit(False);
  Buffer[Head] := Value;
  Head := NH;
{$endif}
{$ifdef MODE_RTLBARRIER}
  if NH = Tail then
    Exit(False);
  System.ReadWriteBarrier;   { tail read -> data write (R->W) }
  Buffer[Head] := Value;
  System.WriteBarrier;       { data write -> head publish (W->W) }
  Head := NH;
{$endif}
{$ifdef MODE_ACQREL}
  if NH = ReadAcquire(Tail) then
    Exit(False);
  Buffer[Head] := Value;
  WriteRelease(Head, NH);
{$endif}
  Result := True;
end;

function TryDequeue(out Value: Byte): Boolean;
var
  NT: UInt32;
begin
  NT := (Tail + 1) and RingMask;
{$ifdef MODE_ACQREL}
  if Tail = ReadAcquire(Head) then
    Exit(False);
{$else}
  if Tail = Head then
    Exit(False);
{$ifdef MODE_RTLBARRIER}
  System.ReadBarrier;        { head read -> data read (R->R) }
{$endif}
{$endif}
  Value := Buffer[Tail];
{$ifdef MODE_RTLBARRIER}
  System.ReadWriteBarrier;   { data read -> tail publish (R->W) }
{$endif}
{$ifdef MODE_ACQREL}
  WriteRelease(Tail, NT);
{$else}
  Tail := NT;
{$endif}
  Result := True;
end;

procedure ProducerWorker(Arg: Pointer); cdecl;
var
  I, Failures: UInt32;
begin
  Failures := 0;
  for I := 0 to Items - 1 do
  begin
    while not TryEnqueue(Byte(I)) do
    begin
      Inc(Failures);
      if (Failures and 65535) = 0 then
        vTaskDelay(0);   { pure yield: keep the scheduler alive }
    end;
  end;
{$IFDEF FREERTOS}
  vTaskDelete(nil);
{$ENDIF}
end;

var
  V: Byte;
  Idle, I, Expected: UInt32;
  T0, T1, UseC: Int64;
  Check: string;
begin
  Head := 0;
  Tail := 0;
  ConsSum := 0;
  ConsCount := 0;
  Corrupt := 0;

  Expected := 0;
  for I := 0 to Items - 1 do
    Expected := Expected + Byte(I);

  WriteLn('circularqueue: minimal-shape SPSC, mode='
{$ifdef MODE_PLAIN}      + 'plain' {$endif}
{$ifdef MODE_RTLBARRIER} + 'rtlbarrier' {$endif}
{$ifdef MODE_ACQREL}     + 'acqrel' {$endif}
  );
  WriteLn('cores=2 items=', Items, ' ring=', RingSize);

  { give the host-side serial listener time to attach after the
    post-flash reboot before the run starts }
  WriteLn('starting in 3s');
  vTaskDelay(300);

  T0 := esp_timer_get_time;
{$IFDEF FREERTOS}
  if xTaskCreatePinnedToCore(@ProducerWorker, 'cq-prod', 4096, nil, 22, nil, 1) <> 1 then
  begin
    WriteLn('ERROR: cannot create producer task');
    Halt(1);
  end;
{$ELSE}
  HostTaskEntry := @ProducerWorker;
  BeginThread(@HostTaskMain, nil);
{$ENDIF}

  { the consumer runs on this core (0) }
  Idle := 0;
  while ConsCount < Items do
  begin
    if TryDequeue(V) then
    begin
      if V <> (ConsCount and 255) then
        Inc(Corrupt);
      ConsSum := ConsSum + V;
      Inc(ConsCount);
    end
    else
    begin
      Inc(Idle);
      if (Idle and 1023) = 0 then
      begin
{$ifdef MODE_PLAIN}
        vTaskDelay(1);   { real sleep: the livelocking variant needs it }
{$else}
        vTaskDelay(0);   { pure yield }
{$endif}
      end;
    end;
  end;
  T1 := esp_timer_get_time;
  UseC := T1 - T0;
  if UseC = 0 then
    UseC := 1;

  if (ConsSum = Expected) and (Corrupt = 0) then
    Check := 'ok'
  else
    Check := 'FAIL';
  WriteLn('items=', Items, ' usec=', UseC,
    ' items/s=', Int64(Items) * 1000000 div UseC,
    ' checksum=', Check, ' corrupt=', Corrupt);
  WriteLn('circularqueue done');
end.
