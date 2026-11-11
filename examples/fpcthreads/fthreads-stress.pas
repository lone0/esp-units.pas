program fthreads_stress;

{$mode objfpc}{$H+}

{ Stress the fthreads once-only TLS init guard.

  8 waves × 8 BeginThread calls (64 creates). Each wave waits to finish
  before the next so stacks fit. Every create still calls
  SysInitMultithreading; TLS block size must stay equal to the size after
  the first BeginThread. Workers also use threadvars under a CS.

  Success marker: FTHREADS_STRESS_DONE }

uses
  idfheap,
  fthreads,
  esp_task,
  sysutils;

const
  WaveSize = 8;
  WaveCount = 8;
  ItersPerWorker = 40;
  WorkerStack = 4096;

threadvar
  TVWorkerId: longint;
  TVHits: longint;

var
  CS: TRTLCriticalSection;
  WaveGate: PRTLEvent;
  SharedCount: longint;
  WaveFinished: longint;
  SizeAfterFirst: dword;
  Fail: boolean;

function Worker(arg: pointer): ptrint;
var
  id, i: longint;
begin
  id := PtrInt(arg);
  TVWorkerId := id;
  TVHits := 0;
  for i := 1 to ItersPerWorker do
  begin
    if TVWorkerId <> id then
    begin
      EnterCriticalSection(CS);
      Fail := true;
      LeaveCriticalSection(CS);
      break;
    end;
    Inc(TVHits);
    EnterCriticalSection(CS);
    Inc(SharedCount);
    LeaveCriticalSection(CS);
    if (i and 7) = 0 then
      ThreadSwitch;
  end;
  if TVHits <> ItersPerWorker then
  begin
    EnterCriticalSection(CS);
    Fail := true;
    LeaveCriticalSection(CS);
  end;
  EnterCriticalSection(CS);
  Inc(WaveFinished);
  if WaveFinished = WaveSize then
    RTLEventSetEvent(WaveGate);
  LeaveCriticalSection(CS);
  Result := 0;
end;

var
  w, i: longint;
  tid: TThreadID;
  sz: dword;
  totalWorkers: longint;
begin
  totalWorkers := WaveCount * WaveSize;
  writeln('fthreads stress; CPUCount=', CPUCount,
          ' waves=', WaveCount, 'x', WaveSize,
          ' total BeginThread=', totalWorkers);
  InitCriticalSection(CS);
  WaveGate := RTLEventCreate;
  SharedCount := 0;
  Fail := false;
  SizeAfterFirst := 0;

  for w := 0 to WaveCount - 1 do
  begin
    WaveFinished := 0;
    { Ensure the binary event is empty before this wave. }
    RTLEventResetEvent(WaveGate);

    for i := 0 to WaveSize - 1 do
    begin
      tid := BeginThread(@Worker, pointer(w * WaveSize + i), tid, WorkerStack);
      if tid = 0 then
      begin
        writeln('BeginThread failed wave=', w, ' i=', i);
        halt(1);
      end;
      sz := GetFPCThreadVarBlockSize;
      if SizeAfterFirst = 0 then
      begin
        SizeAfterFirst := sz;
        writeln('TLS block size after first BeginThread=', SizeAfterFirst);
        if SizeAfterFirst = 0 then
        begin
          writeln('FTHREADS_STRESS_FAIL empty TLS size');
          halt(2);
        end;
      end
      else if sz <> SizeAfterFirst then
      begin
        writeln('FTHREADS_STRESS_FAIL TLS size grew: was ', SizeAfterFirst,
                ' now ', sz, ' after BeginThread #', w * WaveSize + i + 1);
        halt(3);
      end;
    end;

    RTLEventWaitFor(WaveGate);
    writeln('wave ', w, ' done; shared=', SharedCount, ' TLS=', GetFPCThreadVarBlockSize);
  end;

  sz := GetFPCThreadVarBlockSize;
  writeln('shared=', SharedCount, ' TLS size=', sz, ' fail=', Fail);

  if Fail or (SharedCount <> totalWorkers * ItersPerWorker) or
     (sz <> SizeAfterFirst) then
  begin
    writeln('FTHREADS_STRESS_FAIL');
    halt(4);
  end;

  DoneCriticalSection(CS);
  RTLEventDestroy(WaveGate);
  writeln('FTHREADS_STRESS_DONE');
end.
