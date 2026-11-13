unit esp_task;

{$mode objfpc}{$H+}

{ Thin ESP-IDF FreeRTOS task bindings for IDF 6.x.
  Only the surface needed by fthreads (+ a few helpers for examples).
  Stack depths are in BYTES (ESP-IDF convention).

  portTICK_PERIOD_MS is calibrated at unit initialization from the
  RUNNING kernel (xPortGetTickRateHz, IDF 6.1), so ms->tick conversions
  are correct for whatever CONFIG_FREERTOS_HZ the linked project uses
  (100 Hz anchors: 10; 1000 Hz projects like mosaico-s31/waveshare-s3: 1).
  The default value only covers a degenerate read. Upstream writes it as
  a compile-time constant (1000 div configTICK_RATE_HZ); our units are
  compiled per-architecture, not per-project, so the value must come from
  the linked kernel at runtime instead. }

interface

type
  TTaskHandle = pointer;
  PTaskHandle = ^TTaskHandle;
  TBaseType = longint;
  TUBaseType = longword;
  TTickType = longword;
  PTickType = ^TTickType;
  TTaskFunction = procedure(pvParameters: pointer); cdecl;

const
  tskIDLE_PRIORITY = 0;
  tskNO_AFFINITY = TBaseType($7FFFFFFF);
  portMAX_DELAY = TTickType($FFFFFFFF);
  pdTRUE = 1;
  pdFALSE = 0;
  pdPASS = pdTRUE;

var
  { ms per FreeRTOS tick; a var (upstream has a constant) so the unit
    initialization below can calibrate it from the linked kernel }
  portTICK_PERIOD_MS: longword = 10;

function xPortGetTickRateHz: longword; cdecl; external name 'xPortGetTickRateHz';

function pdMS_TO_TICKS(ms: longword): TTickType; inline;

function xTaskCreatePinnedToCore(
  pvTaskCode: TTaskFunction;
  pcName: PChar;
  usStackDepth: longword; { bytes }
  pvParameters: pointer;
  uxPriority: TUBaseType;
  pvCreatedTask: PTaskHandle;
  xCoreID: TBaseType
): TBaseType; cdecl; external name 'xTaskCreatePinnedToCore';

{ Unpinned create = pinned with tskNO_AFFINITY (ESP-IDF SMP). }
function xTaskCreate(
  pvTaskCode: TTaskFunction;
  pcName: PChar;
  usStackDepth: longword;
  pvParameters: pointer;
  uxPriority: TUBaseType;
  pvCreatedTask: PTaskHandle
): TBaseType; inline;

procedure vTaskDelete(xTaskToDelete: TTaskHandle); cdecl; external name 'vTaskDelete';
procedure vTaskDelay(xTicksToDelay: TTickType); cdecl; external name 'vTaskDelay';
procedure vTaskSuspend(xTaskToSuspend: TTaskHandle); cdecl; external name 'vTaskSuspend';
procedure vTaskResume(xTaskToResume: TTaskHandle); cdecl; external name 'vTaskResume';
procedure vTaskPrioritySet(xTask: TTaskHandle; uxNewPriority: TUBaseType); cdecl; external name 'vTaskPrioritySet';
function uxTaskPriorityGet(xTask: TTaskHandle): TUBaseType; cdecl; external name 'uxTaskPriorityGet';
function xTaskGetCurrentTaskHandle: TTaskHandle; cdecl; external name 'xTaskGetCurrentTaskHandle';

procedure vTaskSetThreadLocalStoragePointer(
  xTaskToSet: TTaskHandle; xIndex: TBaseType; pvValue: pointer
); cdecl; external name 'vTaskSetThreadLocalStoragePointer';

function pvTaskGetThreadLocalStoragePointer(
  xTaskToQuery: TTaskHandle; xIndex: TBaseType
): pointer; cdecl; external name 'pvTaskGetThreadLocalStoragePointer';

procedure taskYIELD; cdecl; external name 'vPortYield';

implementation

function pdMS_TO_TICKS(ms: longword): TTickType; inline;
begin
  pdMS_TO_TICKS := (ms + portTICK_PERIOD_MS - 1) div portTICK_PERIOD_MS;
end;

function xTaskCreate(
  pvTaskCode: TTaskFunction;
  pcName: PChar;
  usStackDepth: longword;
  pvParameters: pointer;
  uxPriority: TUBaseType;
  pvCreatedTask: PTaskHandle
): TBaseType;
begin
  xTaskCreate := xTaskCreatePinnedToCore(
    pvTaskCode, pcName, usStackDepth, pvParameters, uxPriority,
    pvCreatedTask, tskNO_AFFINITY);
end;

initialization
  { calibrate from the RUNNING kernel (returns the linked kernel's
    configTICK_RATE_HZ); 0 keeps the 100 Hz default }
  if xPortGetTickRateHz > 0 then
    portTICK_PERIOD_MS := 1000 div xPortGetTickRateHz;

end.
