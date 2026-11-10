unit esp_semphr;

{$mode objfpc}{$H+}

{ Thin ESP-IDF FreeRTOS semaphore bindings for IDF 6.x.
  Macros in semphr.h are expressed as Pascal wrappers around the real
  queue/mutex symbols so FPC can link them. }

interface

uses
  esp_task;

type
  TSemaphoreHandle = pointer;

function xSemaphoreCreateMutex: TSemaphoreHandle; inline;
function xSemaphoreCreateBinary: TSemaphoreHandle; inline;
function xSemaphoreTake(xSemaphore: TSemaphoreHandle; xBlockTime: TTickType): TBaseType; inline;
function xSemaphoreGive(xSemaphore: TSemaphoreHandle): TBaseType; inline;
procedure vSemaphoreDelete(xSemaphore: TSemaphoreHandle); inline;

implementation

const
  { FreeRTOS queue.h }
  queueQUEUE_TYPE_MUTEX = 1;
  queueQUEUE_TYPE_BINARY_SEMAPHORE = 3;
  queueSEND_TO_BACK = 0;
  semSEMAPHORE_QUEUE_ITEM_LENGTH = 0;
  semGIVE_BLOCK_TIME = 0;

function xQueueCreateMutex(ucQueueType: byte): TSemaphoreHandle;
  cdecl; external name 'xQueueCreateMutex';
function xQueueGenericCreate(
  uxQueueLength, uxItemSize: TUBaseType; ucQueueType: byte
): TSemaphoreHandle; cdecl; external name 'xQueueGenericCreate';
function xQueueSemaphoreTake(
  xQueue: TSemaphoreHandle; xTicksToWait: TTickType
): TBaseType; cdecl; external name 'xQueueSemaphoreTake';
function xQueueGenericSend(
  xQueue: TSemaphoreHandle; pvItemToQueue: pointer;
  xTicksToWait: TTickType; xCopyPosition: TBaseType
): TBaseType; cdecl; external name 'xQueueGenericSend';
procedure vQueueDelete(xQueue: TSemaphoreHandle); cdecl; external name 'vQueueDelete';

function xSemaphoreCreateMutex: TSemaphoreHandle;
begin
  xSemaphoreCreateMutex := xQueueCreateMutex(queueQUEUE_TYPE_MUTEX);
end;

function xSemaphoreCreateBinary: TSemaphoreHandle;
begin
  xSemaphoreCreateBinary := xQueueGenericCreate(
    1, semSEMAPHORE_QUEUE_ITEM_LENGTH, queueQUEUE_TYPE_BINARY_SEMAPHORE);
end;

function xSemaphoreTake(xSemaphore: TSemaphoreHandle; xBlockTime: TTickType): TBaseType;
begin
  xSemaphoreTake := xQueueSemaphoreTake(xSemaphore, xBlockTime);
end;

function xSemaphoreGive(xSemaphore: TSemaphoreHandle): TBaseType;
begin
  xSemaphoreGive := xQueueGenericSend(
    xSemaphore, nil, semGIVE_BLOCK_TIME, queueSEND_TO_BACK);
end;

procedure vSemaphoreDelete(xSemaphore: TSemaphoreHandle);
begin
  vQueueDelete(xSemaphore);
end;

end.
