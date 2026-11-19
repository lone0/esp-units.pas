{ Foreign FreeRTOS task (xTaskCreate, not BeginThread) adopts Pascal
  threadvars after InitMultiThreading — #41793 / fthreads SysRelocateThreadVar.
  Shape inspired by FPCSource tests/test/units/system/tinitmtforeign.pp. }
program t_threads_foreign_threadvar;

{$mode objfpc}{$H+}

uses
  idfheap,
  fthreads,
  esp_task;

threadvar
  TV: LongInt;

var
  Status: LongInt; { 0=pending, 1=pass, else fail }

procedure ForeignTask(param: pointer); cdecl;
begin
  TV := 42;
  if TV <> 42 then
    Status := 2
  else
    Status := 1;
  vTaskDelete(nil);
end;

var
  spins: LongInt;
begin
  TV := 7;
  Status := 0;
  InitMultiThreading;

  if xTaskCreate(@ForeignTask, 'foreign', 4096, nil, 5, nil) <> pdPASS then
    halt(1);

  spins := 0;
  while (Status = 0) and (spins < 500) do
  begin
    vTaskDelay(pdMS_TO_TICKS(10));
    Inc(spins);
  end;

  if Status <> 1 then
    halt(2);
  if TV <> 7 then
    halt(3);

  writeln('ok');
end.
