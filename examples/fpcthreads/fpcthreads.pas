program fpcthreads;

{$mode objfpc}{$H+}

{ Smoke demo for units/freertos-fpc/fthreads (ESP-IDF Delphi-style threads).

  Provenance: adapted from ccrause/fpc-esp-freertos examples/fpcthreads
  (esp-idf-v5.5). This version is emulator-friendly: finite work, no GPIO,
  no FreeRTOS run-time stats (those need CONFIG_FREERTOS_USE_TRACE_FACILITY),
  prints FTHREADS_DONE and exits.

  uses order: idfheap, fthreads, then the rest. }

uses
  idfheap,
  fthreads,
  esp_task,
  sysutils;

const
  NumWorkers = 2;
  WorkerStack = 8192;

var
  Gate: PRTLEvent;
  CS: TRTLCriticalSection;
  SharedCount: longint;
  Finished: longint;
  MainId: TThreadID;

function Worker(arg: pointer): ptrint;
var
  i: longint;
begin
  { Avoid writeln here — console I/O is not proven multi-task-safe. }
  for i := 1 to 100 do
  begin
    EnterCriticalSection(CS);
    Inc(SharedCount);
    LeaveCriticalSection(CS);
    if (i and 15) = 0 then
      ThreadSwitch;
  end;
  EnterCriticalSection(CS);
  Inc(Finished);
  if Finished = NumWorkers then
    RTLEventSetEvent(Gate);
  LeaveCriticalSection(CS);
  Result := PtrInt(arg);
end;

var
  i: longint;
  tid: TThreadID;
begin
  writeln('fpcthreads smoke; CPUCount=', CPUCount);
  MainId := GetCurrentThreadId;
  writeln('main thread ', hexstr(PtrUInt(MainId), 8));

  InitCriticalSection(CS);
  Gate := RTLEventCreate;
  SharedCount := 0;
  Finished := 0;

  for i := 0 to NumWorkers - 1 do
  begin
    tid := BeginThread(@Worker, pointer(i), tid, WorkerStack);
    if tid = 0 then
    begin
      writeln('BeginThread failed for worker ', i);
      halt(1);
    end;
    writeln('started worker ', i, ' as ', hexstr(PtrUInt(tid), 8));
  end;

  RTLEventWaitFor(Gate);
  writeln('shared=', SharedCount, ' finished=', Finished);
  if SharedCount <> NumWorkers * 100 then
  begin
    writeln('FTHREADS_FAIL count');
    halt(2);
  end;

  DoneCriticalSection(CS);
  RTLEventDestroy(Gate);
  writeln('FTHREADS_DONE');
end.
