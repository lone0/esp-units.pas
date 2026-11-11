program fpcthreads;

{$inline on}

{ CHANGE: upstream starts with {$include freertosconfig.inc} and uses the
  freertos-fpc binding units fmem/task/esp_err/portmacro/projdefs/gpio
  (+ gpio_types on LX6); none of those exist in this tree. The upstream
  program structure is kept, with these necessary adaptations:

    - idfheap replaces fmem (this tree's heap_caps_*-backed memory
      manager; must stay first in uses), esp_task replaces the
      task/portmacro/projdefs surface.

    - portTICK_PERIOD_MS / pdMS_TO_TICKS come from esp_task; the tick
      period is calibrated at unit initialization from the RUNNING kernel
      (xPortGetTickRateHz), so demo timings are correct for the
      CONFIG_FREERTOS_HZ of whichever project is linked (100 Hz anchors:
      10 ms/tick; 1000 Hz projects: 1 ms/tick).

    - upstream's printRealTimeStats (the per-task run-time stats table)
      is dropped: it needs CONFIG_FREERTOS_USE_TRACE_FACILITY, which
      neither closure project enables - uxTaskGetSystemState is not
      compiled into their libfreertos.a and cannot be linked. Enabling it
      would change the frozen SDK baselines (hello-s31 is the esp32s31
      closure anchor and must stay untouched). printLeftAlignedPadded
      (only used by that table) goes with it.

    - the "Main running on core ID" line is dropped for the same kind of
      reason: IDF 6.1 implements xPortGetCoreID as a static inline, no
      linkable symbol.

    - the GPIO surface for the blink thread is declared directly against
      the IDF 6.1 esp_driver_gpio symbols; the record layout and the
      values below are the C gpio_config_t / gpio_types.h enums. }

uses
  { CHANGE: upstream: fmem, fthreads, task, esp_err, portmacro, projdefs,
    gpio {$ifdef CPULX6}, gpio_types {$endif} }
  idfheap,
  fthreads,
  esp_task;

const
  numSpinTasks            = 2;
  MaxIterations           = 400;     // Actual CPU cycles used will depend on compiler optimization

{ CHANGE: from upstream's gpio/gpio_types binding units, not present here }
const
  GPIO_NUM_2              = 2;
  GPIO_MODE_OUTPUT        = 2;      { gpio_mode_t }
  GPIO_PULLUP_DISABLE     = 0;      { gpio_pullup_t }
  GPIO_PULLDOWN_DISABLE   = 0;      { gpio_pulldown_t }
  GPIO_INTR_DISABLE       = 0;      { gpio_int_type_t }

type
  Tgpio_config = record   { gpio_config_t, esp_driver_gpio/gpio.h }
    pin_bit_mask: qword;
    mode: dword;
    pull_up_en: dword;
    pull_down_en: dword;
    intr_type: dword;
  end;

{ CHANGE: upstream declares these in gpio.pp as
  "function gpio_config(constref GPIOConfig: Tgpio_config): Tesp_err; external;"
  - constref matches the C ABI's by-reference passing of the 24-byte
  gpio_config_t; a by-value cdecl declaration would hand the first struct
  word to gpio_config in a register (observed as LoadProhibited). }
function gpio_config(constref config: Tgpio_config): dword; cdecl; external name 'gpio_config';
function gpio_set_direction(gpio_num, mode: dword): dword; cdecl; external name 'gpio_set_direction';
function gpio_set_level(gpio_num, level: dword): dword; cdecl; external name 'gpio_set_level';

var
  startSpinTask: PRTLEvent;
  blinkCS: TRTLCriticalSection;

function spinThread(arg: pointer): ptrint; noreturn;
var
  Iterations: uint32 = 0;
  i: integer;
begin
  Iterations := MaxIterations div (uint32(arg) + 1);

  // Wait for start event...
  RTLEventWaitFor(startSpinTask);
  while true do
  begin
    // Spin...
    for i := 0 to Iterations-1 do
    begin
      asm NOP end;
      if i div 10 = 0 then
        ThreadSwitch; // Thread switch occasionally to make other threads more responsive
    end;
    vTaskDelay(pdMS_TO_TICKS(10));
  end;
end;

const
  LED = GPIO_NUM_2;  // NodeMCU LED on ESP-12E module, also ESP32 DevKit V1 from DOIT
  //LED = GPIO_NUM_13; // Sonoff Basic

function blinkThread(parameter : pointer) : ptrint; noreturn;
var
  cfg: Tgpio_config;
begin
  // Configure pin state
  cfg.pin_bit_mask := 1 shl ord(LED);
  cfg.mode := GPIO_MODE_OUTPUT;
  cfg.pull_up_en := GPIO_PULLUP_DISABLE;
  cfg.pull_down_en := GPIO_PULLDOWN_DISABLE;
  cfg.intr_type := GPIO_INTR_DISABLE;
  gpio_config(cfg);
  gpio_set_direction(LED, GPIO_MODE_OUTPUT);
  repeat
    EnterCriticalSection(blinkCS);
    LeaveCriticalSection(blinkCS); // immediately release CS again, it is used as a gate only
    gpio_set_level(LED, 0);
    vTaskDelay(250 div portTICK_PERIOD_MS);
    gpio_set_level(LED, 1);
    vTaskDelay(250 div portTICK_PERIOD_MS);
  until false;
end;

var
  i: integer;
  blinkID: TThreadID;
  statsTick: uint32;
  loopcount: uint32 = 0;
  taskName: string[16];

begin
  //Create RTL event to signal spin threads
  startSpinTask := RTLEventCreate;
  //Create spin tasks
  for i := 0 to numSpinTasks-1 do
  begin
    writeln('Creating fpc task ', i);
    // Pass i as parameter to task
    // Larger i will run fewer spin cycles
    BeginThread(@spinThread,        // thread to launch
               pointer(i),          // pointer parameter to be passed to thread function
               blinkID,             // new thread ID
               2*1024);             // stacksize
  end;

  vTaskDelay(pdMS_TO_TICKS(100));
  writeln('Starting spinTasks');
  //Start all the spin tasks
  for i := 0 to numSpinTasks-1 do
  begin
    RTLEventSetEvent(startSpinTask);
    // Potential race situation where next RTLEventSetEvent is called
    // before spinThread had an opportunity to read first event.
    // Put delay here so that spin thread gets an opportunity to read the first event.
    // An alternative design could be a pair of ping-pong events.
    vTaskDelay(50);
  end;

  // Blink thread...
  InitCriticalSection(blinkCS);
  EnterCriticalSection(blinkCS);  // blinkCS will now block
  //writeln('Starting blink thread');
  taskName := 'blink';
  fBeginThreadNamed(2*1024,        // stacksize
                    @blinkThread,  // thread to launch
                    nil,           // pointer parameter to be passed to thread function
                    blinkID,       // the new thread ID
                    taskName);

  //Allow other core to finish initialization
  vTaskDelay(pdMS_TO_TICKS(100));
  writeln('After blink thread');

  { CHANGE: upstream prints 'Main running on core ID ', xPortGetCoreID
    here; IDF 6.1 has no linkable xPortGetCoreID (static inline) }

  // Wait period between stats calls, in sys ticks
  statsTick := pdMS_TO_TICKS(2000);
  repeat
    inc(loopcount);
    // Block/unblock blink loop
    if odd(loopcount) then
    begin
      writeln('Resume blink');
      LeaveCriticalSection(blinkCS);
    end
    else
    begin
      writeln('Pause blink');
      EnterCriticalSection(blinkCS);
    end;
    vTaskDelay(statsTick);
    { CHANGE: upstream prints the per-task run-time stats table here
      (printRealTimeStats, with an error line on failure); dropped - the
      trace-facility symbols cannot be linked against the closure
      projects, see the header note }
  until false;
end.
