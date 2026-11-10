{
  Free Pascal TThreadManager on ESP-IDF FreeRTOS (IDF 6.x).

  Adapted from ccrause/fpc-esp-freertos freertos-fpc/fthreads.pp
  (esp-idf-v5.5). Changes for this tree:
    - uses idfheap instead of fmem
    - thin esp_task / esp_semphr bindings (IDF 6.1 linkable symbols)
    - S3 / S31 MCU awareness for CPUCount
    - critical-section teardown uses xSemaphoreGive (not GiveRecursive)
    - ESP-IDF stack depths are bytes

  This unit does NOT change the freertos RTL stubs. Opt in by putting
  idfheap then fthreads early in uses (before classes). FPCSource keeps
  the no-thread/stub contract; this is an application-side supplement.
}

unit fthreads;

{$mode objfpc}{$H+}
{$inline on}

interface

const
  DefaultStackSize = 4 * 1024;

function GetCPUCount: LongWord;
property CPUCount: LongWord read GetCPUCount;

{ Prefer BeginThread for the first threading call (sets up the manager).
  fBeginThreadNamed alone does not replace that first-call contract. }
function fBeginThreadNamed(StackSize: PtrUInt;
  ThreadFunction: TThreadFunc; P: pointer;
  var ThreadId: TThreadID; constref aname: shortstring): TThreadID;

implementation

uses
  idfheap,   { Pascal heap → heap_caps_* before TLS alloc }
  esp_task,
  esp_semphr;

const
  { With CONFIG_FREERTOS_TLSP_DELETION_CALLBACKS the IDF doubles the
    pointer array; user indices are still 0 .. N-1 in the first half.
    Both idf-build-s3 and idf-build-s31 use N=1 → index 0 is valid. }
  DataIndex: PtrUInt = 0;
  pdTRUE_LOCAL = 1;

var
  FreeRTOSThreadManager: TThreadManager;
  ThreadVarBlockSize: dword = 0;
  TLSAPISupported: boolean = false;
  TLSInitialized: boolean = false;
  threadCount: uint32 = 0;

procedure HandleError(Errno: Longint); external name 'FPC_HANDLEERROR';
procedure fpc_threaderror; external name 'FPC_THREADERROR';

{ Raw IDF allocator for the TLS block — must not go through GetMem, which
  can re-enter SysRelocateThreadVar before the TLS pointer is installed. }
const
  MALLOC_CAP_8BIT = 1 shl 2;
  MALLOC_CAP_DEFAULT = 1 shl 12;
  TLS_CAPS = MALLOC_CAP_8BIT or MALLOC_CAP_DEFAULT;

function heap_caps_malloc(size, caps: ptruint): pointer; cdecl; external name 'heap_caps_malloc';
procedure heap_caps_free(p: pointer); cdecl; external name 'heap_caps_free';

procedure SysInitThreadvar(var Offset: dword; Size: dword);
begin
{$ifdef CPUXTENSA}
  ThreadVarBlockSize := align(ThreadVarBlockSize, 4);
{$endif}
  Offset := ThreadVarBlockSize;
  Inc(ThreadVarBlockSize, Size);
end;

procedure SysAllocateThreadVars;
var
  p: pointer;
begin
  if not (TLSAPISupported and TLSInitialized) then
    HandleError(3);
  p := heap_caps_malloc(ThreadVarBlockSize, TLS_CAPS);
  if p = nil then
    HandleError(203);
  FillByte(p^, ThreadVarBlockSize, 0);
  vTaskSetThreadLocalStoragePointer(nil, TBaseType(DataIndex), p);
end;

function SysRelocateThreadVar(Offset: dword): pointer;
var
  p: pointer;
begin
  p := pvTaskGetThreadLocalStoragePointer(nil, TBaseType(DataIndex));
  if p = nil then
  begin
    SysAllocateThreadVars;
    InitThread(DefaultStackSize);
    p := pvTaskGetThreadLocalStoragePointer(nil, TBaseType(DataIndex));
  end;
  SysRelocateThreadVar := p + Offset;
end;

procedure SysInitMultithreading;
begin
  TLSAPISupported := true;
  IsMultiThread := true;
  TLSInitialized := true;
  InitThreadVars(@SysRelocateThreadVar);
end;

procedure SysFiniMultithreading;
var
  p: pointer;
begin
  if IsMultiThread and TLSAPISupported then
  begin
    p := pvTaskGetThreadLocalStoragePointer(nil, TBaseType(DataIndex));
    if p <> nil then
      heap_caps_free(p);
  end;
end;

procedure SysReleaseThreadVars;
var
  p: pointer;
begin
  if TLSAPISupported then
  begin
    p := pvTaskGetThreadLocalStoragePointer(nil, TBaseType(DataIndex));
    if p <> nil then
    begin
      heap_caps_free(p);
      vTaskSetThreadLocalStoragePointer(nil, TBaseType(DataIndex), nil);
    end;
  end
  else
    RunError(3);
end;

type
  PThreadInfo = ^TThreadInfo;
  TThreadInfo = record
    f: TThreadFunc;
    p: pointer;
    stklen: cardinal;
  end;

procedure ThreadMain(param: pointer); cdecl;
var
  ti: TThreadInfo;
begin
  SysAllocateThreadVars;
  ti := PThreadInfo(param)^;
  Dispose(PThreadInfo(param));
  InitThread(ti.stklen);
  ti.f(ti.p);
  DoneThread;
  vTaskDelete(nil);
end;

function fBeginThreadNamed(StackSize: PtrUInt;
  ThreadFunction: TThreadFunc; P: pointer;
  var ThreadId: TThreadID; constref aname: shortstring): TThreadID;
var
  TI: PThreadInfo;
  RC: TBaseType;
  namebuf: array[0..16] of char;
  nlen, i: integer;
begin
  SysInitMultithreading;
  New(TI);
  TI^.f := ThreadFunction;
  TI^.p := P;
  TI^.stklen := StackSize;
  ThreadId := 0;

  nlen := Length(aname);
  if nlen > 15 then
    nlen := 15;
  for i := 1 to nlen do
    namebuf[i - 1] := aname[i];
  namebuf[nlen] := #0;

  RC := xTaskCreate(@ThreadMain, @namebuf[0], StackSize, TI, 1, @ThreadId);
  if RC = pdTRUE_LOCAL then
    fBeginThreadNamed := ThreadId
  else
  begin
    fBeginThreadNamed := 0;
    Dispose(TI);
    RunError(203);
  end;
end;

function SysBeginThread(SA: pointer; StackSize: PtrUInt;
  ThreadFunction: TThreadFunc; P: pointer;
  CreationFlags: dword; var ThreadId: TThreadID): TThreadID;
var
  threadName: string[16];
  s: string[10];
begin
  Inc(threadCount);
  Str(threadCount, s);
  threadName := 'fpc-' + s;
  SysBeginThread := fBeginThreadNamed(StackSize, ThreadFunction, P, ThreadId, threadName);
end;

procedure SysEndThread(ExitCode: cardinal);
begin
  DoneThread;
  vTaskDelete(nil);
  ExitCode := 0;
end;

procedure SysThreadSwitch;
begin
  taskYIELD;
end;

function SysSuspendThread(ThreadHandle: TThreadID): dword;
begin
  vTaskSuspend(pointer(ThreadHandle));
  SysSuspendThread := 0;
end;

function SysResumeThread(ThreadHandle: TThreadID): dword;
begin
  vTaskResume(pointer(ThreadHandle));
  SysResumeThread := 0;
end;

function SysKillThread(ThreadHandle: TThreadID): dword;
begin
  vTaskDelete(TTaskHandle(ThreadHandle));
  SysKillThread := 0;
end;

function SysCloseThread(ThreadHandle: TThreadID): dword;
begin
  SysCloseThread := 0;
end;

function SysWaitForThreadTerminate(ThreadHandle: TThreadID;
  TimeoutMs: longint): dword;
begin
  { FreeRTOS has no join; apps should use RTLEvent / queues. }
  SysWaitForThreadTerminate := 1;
end;

function SysThreadSetPriority(ThreadHandle: TThreadID; Prio: longint): boolean;
begin
  if Prio < 0 then
    Prio := 0;
  vTaskPrioritySet(TTaskHandle(ThreadHandle), TUBaseType(Prio));
  SysThreadSetPriority := true;
end;

function SysThreadGetPriority(ThreadHandle: TThreadID): longint;
begin
  SysThreadGetPriority := longint(uxTaskPriorityGet(TTaskHandle(ThreadHandle)));
end;

function SysGetCurrentThreadID: TThreadID;
begin
  SysGetCurrentThreadID := TThreadID(xTaskGetCurrentTaskHandle);
end;

procedure SysSetThreadDebugNameA(threadHandle: TThreadID; const ThreadName: AnsiString);
begin
  { Name is fixed at xTaskCreate time on FreeRTOS. }
end;

{$ifdef FPC_HAS_FEATURE_UNICODESTRINGS}
procedure SysSetThreadDebugNameU(threadHandle: TThreadID; const ThreadName: UnicodeString);
begin
end;
{$endif}

procedure SysInitCriticalSection(var CS);
begin
  TSemaphoreHandle(CS) := xSemaphoreCreateMutex;
  if pointer(CS) = nil then
    fpc_threaderror;
end;

procedure SysDoneCriticalSection(var CS);
begin
  if pointer(CS) <> nil then
  begin
    xSemaphoreGive(TSemaphoreHandle(CS));
    vSemaphoreDelete(TSemaphoreHandle(CS));
    pointer(CS) := nil;
  end;
end;

procedure SysEnterCriticalSection(var CS);
begin
  if xSemaphoreTake(TSemaphoreHandle(CS), portMAX_DELAY) <> pdTRUE_LOCAL then
    fpc_threaderror;
end;

function SysTryEnterCriticalSection(var CS): longint;
begin
  if xSemaphoreTake(TSemaphoreHandle(CS), 0) = pdTRUE_LOCAL then
    SysTryEnterCriticalSection := 1
  else
    SysTryEnterCriticalSection := 0;
end;

procedure SysLeaveCriticalSection(var CS);
begin
  if xSemaphoreGive(TSemaphoreHandle(CS)) <> pdTRUE_LOCAL then
    fpc_threaderror;
end;

function SysRTLEventCreate: PRTLEvent;
begin
  SysRTLEventCreate := PRTLEvent(xSemaphoreCreateBinary);
  if SysRTLEventCreate = nil then
    fpc_threaderror;
end;

procedure SysRTLEventDestroy(AEvent: PRTLEvent);
begin
  vSemaphoreDelete(TSemaphoreHandle(AEvent));
end;

procedure SysRTLEventSetEvent(AEvent: PRTLEvent);
begin
  xSemaphoreGive(TSemaphoreHandle(AEvent));
end;

procedure SysRTLEventWaitFor(AEvent: PRTLEvent);
begin
  if xSemaphoreTake(TSemaphoreHandle(AEvent), portMAX_DELAY) <> pdTRUE_LOCAL then
    fpc_threaderror;
end;

procedure SysRTLEventWaitForTimeout(AEvent: PRTLEvent; Timeout: longint);
begin
  xSemaphoreTake(TSemaphoreHandle(AEvent), TTickType(Timeout div portTICK_PERIOD_MS));
end;

procedure SysRTLEventResetEvent(AEvent: PRTLEvent);
begin
  xSemaphoreTake(TSemaphoreHandle(AEvent), 0);
end;

{$DEFINE HAS_GETCPUCOUNT}
function GetCPUCount: LongWord;
begin
{$ifdef FPC_MCU_ESP32S3}
  GetCPUCount := 2;
{$else}
{$ifdef FPC_MCU_ESP32}
  GetCPUCount := 2;
{$else}
  GetCPUCount := 1; { S31 and other single-core ESP targets }
{$endif}
{$endif}
end;

procedure InitSystemThreads;
begin
  with FreeRTOSThreadManager do
  begin
    InitManager := nil;
    DoneManager := nil;
    BeginThread := @SysBeginThread;
    EndThread := @SysEndThread;
    SuspendThread := @SysSuspendThread;
    ResumeThread := @SysResumeThread;
    KillThread := @SysKillThread;
    CloseThread := @SysCloseThread;
    ThreadSwitch := @SysThreadSwitch;
    WaitForThreadTerminate := @SysWaitForThreadTerminate;
    ThreadSetPriority := @SysThreadSetPriority;
    ThreadGetPriority := @SysThreadGetPriority;
    GetCurrentThreadId := @SysGetCurrentThreadId;
    SetThreadDebugNameA := @SysSetThreadDebugNameA;
{$ifdef FPC_HAS_FEATURE_UNICODESTRINGS}
    SetThreadDebugNameU := @SysSetThreadDebugNameU;
{$endif}
    InitCriticalSection := @SysInitCriticalSection;
    DoneCriticalSection := @SysDoneCriticalSection;
    EnterCriticalSection := @SysEnterCriticalSection;
    TryEnterCriticalSection := @SysTryEnterCriticalSection;
    LeaveCriticalSection := @SysLeaveCriticalSection;
    InitThreadVar := @SysInitThreadVar;
    RelocateThreadVar := @SysRelocateThreadVar;
    AllocateThreadVars := @SysAllocateThreadVars;
    ReleaseThreadVars := @SysReleaseThreadVars;
    BasicEventCreate := nil;
    BasicEventDestroy := nil;
    BasicEventSetEvent := nil;
    BasicEventResetEvent := nil;
    BasiceventWaitFor := nil;
    RTLEventCreate := @SysRTLEventCreate;
    RTLEventDestroy := @SysRTLEventDestroy;
    RTLEventSetEvent := @SysRTLEventSetEvent;
    RTLEventResetEvent := @SysRTLEventResetEvent;
    RTLEventWaitFor := @SysRTLEventWaitFor;
    RTLEventWaitForTimeout := @SysRTLEventWaitForTimeout;
  end;
  SetThreadManager(FreeRTOSThreadManager);
end;

initialization
  if ThreadingAlreadyUsed then
  begin
    writeln('Threading used before fthreads init; put idfheap,fthreads early in uses.');
    runerror(211);
  end;
  InitSystemThreads;

end.
