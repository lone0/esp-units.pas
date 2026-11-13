{ upstream provenance: FPCSource-esp-idf tests/test/tmt1.pp }
{ %skiptarget=$nothread }

{$mode objfpc}

{$ifdef CPUWASM32}
  { This test runs out of memory, when using the default WebAssembly shared
    memory limit of 256 MiB, so we increase it to 512 MiB }
  {$M 1048576,536870912,536870912}
{$endif}

uses
  idfheap,
  fthreads,
  esp_task,
  sysutils
  ;

const
{$if defined(cpuarm) or defined(cpuavr) or defined(cpui8086) or defined(cpum68k) or defined(cpumips) or defined(cpuz80) or defined(cpuxtensa) or defined(cpuriscv32)}
  {$define slowcpu}
{$endif slowcpu}

{$ifdef slowcpu}
   threadcount = 8;
   stringlen = 2000;
{$else slowcpu}
   threadcount = 100;
   stringlen = 10000;
{$endif slowcpu}

var
   finished : longint;
threadvar
   thri : longint;

function f(p : pointer) : ptrint;
  var
     s : ansistring;
  begin
     writeln('thread ',longint(p),' started');
     thri:=0;
     while (thri<stringlen) do
      begin
        s:=s+'1';
        inc(thri);
      end;
     writeln('thread ',longint(p),' finished');
     InterLockedIncrement(finished);
     f:=0;
  end;

var
   i : ptrint;
   started: longint;
begin
   finished:=0;
   started:=0;

   for i:=1 to threadcount do
     if BeginThread({$ifdef fpc}@{$endif}f,pointer(i)) <> tthreadid(0) then
       inc(started);

   while volatile(finished)<started do
     { SysUtils.Sleep is unimplemented on the FreeRTOS RTL. }
     vTaskDelay(pdMS_TO_TICKS(1));
   writeln(finished);
end.
