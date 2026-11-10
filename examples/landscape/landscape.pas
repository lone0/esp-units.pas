program landscape;

{ SWAG 0119.PAS "Landscape" (Marcin Borkowski, 1994-08-24) on the
  ESP-Mosaico CO5300 480x480 QSPI AMOLED - fidelity port, native panel
  resolution.

  Architecture: the 1994 code is kept LINE-ALIGNED (pal, ncol, plasma,
  draw, the main sequence) with its constants retuned to the panel
  (parameters only - the algorithm structure is untouched), and
  everything the ESP world forces on us lives in one display-adapter
  section (esp_init / vga_setmode / vga_flush / ctrl_task) that the
  main program calls where the original had its DOS counterparts:

    94 original                        this port
    ----------------------------------------------------------------
    uses crt                           uses idfheap, c_bmgr, ...
    new(mp); fillchar(mp^,65535,0)     GetMem(raw, MAP_BLOCK) + pad
    new(scr)                           scr := frame[0]  (in esp_init)
    asm int10 $13 end                  vga_setmode (panel buffers clear)
    port[$3C8]/[$3C9] palette load     vga_setmode (pal -> BE RGB565 LUT)
    draw(): ...; move(scr^,A000:0)     draw(): ...; vga_flush
    case readkey of #75/#77/#72/#80    dir+ctrl_dturn; y+ctrl_dy; x+ctrl_dx
                                       (ctrl_* = "key state", refreshed by
                                       the background ctrl_task: BMI270
                                       tilt steering, or wander simulation
                                       when the sensor is absent - the
                                       frame loop cannot tell which)

  Native-resolution parameter mapping (draw's inline constants; each is
  the 94 value times the resolution ratio, FOCAL_Y additionally carries
  the mode-13h pixel aspect so the square panel reproduces what a 4:3
  CRT actually showed - world anisotropy 10:1):
    320 -> 480 (panel width)      64000 -> 480*480*2 (16 bpp surface)
    160/100 -> 240 (center/horizon)
    360 -> 540 = 360 x 1.5
     30 ->  54 =  30 x 1.5 x 1.2
    318 -> 478 = 480-2 clip       300 -> 450 (span fill, x 1.5)
    rng sentinel 200 -> 480, byte -> word (values exceed 255)
  The palette lookup moved into draw's paint line (scr[..] := lut[mpc]):
  scr is now a 480x480 BE-RGB565 double buffer (frame[0]/[1] in PSRAM,
  flipped by vga_flush) - no expansion pass, no stretch; the DAC's
  index-to-RGB job happens where the index byte was stored.

  Deviations from verbatim (complete list):
    1. uses crt -> the ESP units; console = the board's USB CDC.
    2. mp sits in a padded block (plasma writes up to 256*256+256 and
       draw samples 256*iyp+ixp with iyp/ixp outside 0..255; both stay
       verbatim because the pad makes them in-block). The pad is zeroed
       - the same fresh-heap zeros DOS used to hand back.
    3. scr: was one 64000-byte palette-index buffer; now a pointer into
       the 480x480 BE-RGB565 double panel buffer, painted through the
       LUT (the DAC's job, at paint time) and flipped by the adapter.
       draw's constants are retuned per the table above; rng grew to
       word[0..481] for the same reason.
    4. the readkey steering branch consumes ctrl_dturn/dx/dy - three
       integers the background ctrl_task recomputes every 333 ms from
       the BMI270's gravity vector (lean = the 94 #75/#77 turns,
       proportional, capped at 10 deg/frame; flat = #72 forward,
       vertical = #80 backward, dead zone = hover) or, sensor absent,
       from a wander simulation. All float math and the I2C read live
       in that task; the frame loop is integer-only and oblivious.
       Movement lags a turn by up to one sample period (slight sideslip
       while banking) - the accepted cost of the slow cadence.
    5. fps diagnostics live inside vga_flush (adapter side).

  Display adapter facts (all verified on hardware, 2026-11-08):
    - the BMGR-generated panel-io bounces PSRAM through internal RAM
      (psram_dma_direct off); the app builds its own panel-io with the
      flag on and its own CO5300 panel object on the same bus.
    - the generated 40 MHz pclk is raised to 80 MHz (wire 11.5 ms per
      full frame) - the panel class standard clock.
    - draw_bitmap x_end/y_end are EXCLUSIVE in this driver (CASET gets
      x_end-1): the full frame is (0,0,W,H). Passing W-1/H-1 leaves the
      last column/row unwritten and shears every row by one pixel.
    - NO sync to the panel scan: flushes start at a random phase, so
      roughly a third of the frames show a tear line (measured in the
      TE-synced A/B on hardware) - accepted to keep the loop dead
      simple. A TE-synced variant worked (GPIO43, edge-locked flush,
      zero tears) but needed an ISR or a spin; simplicity won. The
      full TE design + the A/B measurements live in this file's git
      history and the README.
    - the double buffer exists because draw_bitmap returns before its
      DMA completes (tx_color queues): rendering into the buffer that
      is NOT being streamed is what makes the async pipeline correct,
      and takes the 11.5 ms wire time off the critical path. The
      descriptor-recycle blocking inside that path (a few ms per frame)
      is also what feeds the idle task - no explicit delay needed.
    - the 94 row-overpaint quirk writes one row past the frame on the
      first touch of each column: the frame buffers carry FRAME_SLACK
      tail bytes so the write stays in-allocation (without it: heap
      corruption -> delayed abort -> black screen, found the hard way).

  Performance: ~30 fps - bounded by the ~30 ms column-strided paint
  into PSRAM (cache-line fetch+writeback amplification); the flush and
  control add ~1 ms. Fidelity note: the original ran ~15-20 fps on a
  486; this port outpaces it.

  Build (SDK anchor = the Mosaico project):

    ESP_FPC_ROOT=/mnt/storage/fpc-cross \
    ESP32_SDK_PROJECT=/mnt/storage/fpc-esp/mosaico-s31 \
    ../../scripts/build.sh landscape.pas --soc esp32s31 \
        --lib espressif__esp_board_manager --lib gen_bmgr_codes \
        --lib esp_lcd --lib espressif__esp_lcd_co5300 \
        --lib waveshare__esp_lcd_touch_cst9217 --lib espressif__esp_lcd_touch \
        --lib espressif__esp_codec_dev --lib espressif__i2c_bus \
        --lib espressif__button --lib espressif__bq27220 \
        --lib espressif__esp_video --lib espressif__esp_cam_sensor \
        --lib espressif__esp_sccb_intf --lib esp_driver_cam --lib esp_driver_ppa \
        --lib esp_hal_cam --lib esp_driver_gpio --lib esp_driver_spi \
        --lib esp_driver_i2c --lib esp_driver_i2s --lib esp_driver_ledc \
        --lib esp_hal_ledc --lib esp_hal_gpio --lib esp_hal_lcd \
        --lib esp_hal_i2c --lib esp_hal_i2s --lib esp_timer --lib esp_partition \
        --lib log --lib vfs --lib esp_system

  (the camera family comes from the whole-archived BMGR registry, which
  references dev_camera even though this app never opens a camera)

  Flash: mkflash --soc esp32s31 --tight + esptool --no-stub - see README.md. }

{$mode objfpc}{$H+}
{$packrecords C}   { the adapter's C-ABI records (bmi2 layouts, vendor cfg) }

uses
  idfheap,           { MUST be first: installs the IDF heap manager }
  c_bmgr,            { esp_board_manager binding (units/, L1) }
  c_esp_lcd,         { esp_lcd panel ops binding (units/, L1) }
  bmi270tilt,        { TBmi270Tilt: two tilt angles off the BMI270 (L2) }
  Math;              { arctan2 for the ctrl task's homing guard }

{ ==================================================== ESP adapter - C ABI }

{ driver/gpio.h - esp_driver_gpio: motor off (dev_gpio_ctrl inits at
  active_level=1, so the vibration motor must be pulled to 0) }
function gpio_set_level(gpio_num: cint; level: cuint32): esp_err_t; cdecl; external;

{ esp_timer - fps/telemetry }
function esp_timer_get_time: int64; cdecl; external;


{ FreeRTOS - the background control task (all float math and the I2C
  sensor read live there; the frame loop consumes ready integers).
  IDF 6.1 carries the SMP kernel: xTaskCreate is a macro, this is the
  real symbol. ESP-IDF task stack depth is in BYTES; pdPASS = 1 }
function xTaskCreatePinnedToCore(task_fn: pointer; name: PChar;
  stack_depth: cuint32; parameters: pointer; priority: cuint;
  created_handle: pointer; core_id: cint): cint; cdecl; external;
procedure vTaskDelay(ticks: cuint32); cdecl; external;

{ espressif__esp_lcd_co5300 - AMOLED brightness (a vendor register call;
  the board pack models no brightness device, and every panel re-init
  resets the register to the driver default max) }
function esp_lcd_panel_co5300_set_brightness(panel: esp_lcd_panel_handle_t;
  brightness_percent: cuint8): esp_err_t; cdecl; external;

{ ================================================================== 94 code }
{ The 1994 declarations, verbatim and first (Pascal wants declare-before-
  use; the adapter below references these) }

type
  lrgarr = array[0..65534]of byte;     { 94 verbatim; mp gets a padded
                                         block of this base type }
  plrgarr = ^lrgarr;

const
 pal : array[1..384]of byte =
 (0,0,0,48,48,48,1,0,43,1,3,43,2,5,44,2,7,44,3,9,45,4,11,46,5,13,47,6,15,48,
  7,17,49,8,19,50,9,21,51,10,22,52,11,24,52,12,26,54,13,28,54,14,30,56,15,32,
  56,16,34,58,17,34,58,17,36,58,18,38,60,19,40,60,20,42,62,21,44,62,10,31,0,
  11,31,0,11,31,1,11,32,1,12,32,1,12,32,2,12,33,2,13,33,2,14,33,3,15,33,3,15,
  34,3,15,34,4,15,35,4,16,35,4,16,35,5,16,36,5,17,36,5,17,36,6,18,37,6,18,38,
  7,19,38,8,20,39,8,20,40,9,21,40,10,22,41,10,22,42,11,23,42,12,24,43,12,24,
  44,13,25,44,14,25,45,14,26,46,15,27,46,16,27,47,17,28,47,18,28,48,19,29,49,
  19,30,49,20,30,50,21,31,51,21,32,51,22,32,52,23,33,53,23,34,53,24,34,54,25,
  35,55,25,36,55,26,36,56,27,37,57,27,38,57,27,39,57,27,41,57,27,42,57,27,43,
  57,27,44,57,27,45,57,27,46,57,27,47,57,27,49,57,27,50,57,27,51,57,27,52,57,
  27,53,57,27,55,57,27,56,57,27,57,57,27,58,57,27,58,57,26,58,57,25,58,57,24,
  58,56,23,58,55,22,58,54,20,58,53,19,58,51,18,58,50,17,58,50,16,58,49,15,58,
  48,14,58,47,13,58,46,12,58,45,11,58,44,11,58,44,10,58,43,10,58,42,9,57,41,
  8,57,40,8,56,39,7,56,38,6,55,37,5,55,35,4,54,33,4,54,31,2,32,32,32,63,63,63,
  63,63,63,63,63,63,63,63,63,48,48,48,63,63,63,63,63,63);

var
 mp : ^lrgarr;                        { 94: mp,scr : ^lrgarr - scr 重定为
  面板像素宽的 16 位双缓冲指针(适配层), 见 draw }
 scr : ^cuint16;
 rng : array[0..481]of word;          { 94: array[0..320]of byte - 480 列 +
  480 哨兵值需 word }
 dir,i,x,y : integer;
 diff : integer;                      { 归航逐帧追踪用的角差(适配层) }

{ =============================================== ESP adapter - display }

const
  TAG = 'LANDSCAPE';

  { panel geometry (CO5300, BMGR generated config: 480x480, RGB565 BE,
    QSPI, rotation identity) }
  W = 480;
  H = 480;

  { no TE sync: flushes start at a random phase of the panel scan, so
    roughly a third of the frames show a tear line (measured, A/B'd on
    hardware) - accepted in exchange for keeping the loop dead simple.
    The flush path still blocks a few ms per frame inside the SPI driver
    (descriptor recycling), which feeds the idle task / watchdog }
  TSK_NO_AFFINITY = $7FFFFFFF;   { the EFFECTIVE constant in IDF 6.1
                            (FreeRTOS-Kernel/include/freertos/task.h).
                            Do NOT use -1: a stale copy of this header
                            (FreeRTOS-Kernel-SMP/...) defines it as -1,
                            but xTaskCreatePinnedToCore asserts
                            core_id in 0,1,$7FFFFFFF - passing -1
                            fails the assert and aborts with the
                            console dead (a silent reset that cost a
                            long bisect; root-caused by disassembling
                            the kernel entry + a C-probe experiment) }

  { tail slack for the 94 row-overpaint quirk: the paint loop writes one
    row past the frame at the first touch of each column (rng sentinel
    480) - 960 B/frame on the native-480 surface. The original had the
    same overpaint inside its own 65535-byte allocation; the slack keeps
    it inside ours. Without it: adjacent-heap-header corruption ->
    delayed abort -> panic-reboot loop -> black panel. }
  FRAME_SLACK = 2048;

  { BMI270 tilt steering (the 94 keys' replacement): addr 0x69 (SDO high,
  same as imu_gesture.c), accel-only, +-4G/100Hz like the official BSP
  defaults. Mapping: lean left/right = the 94 #75/#77 turns (proportional
  to lean, capped at the original's 10 deg/frame); flat = #72 forward,
  vertical = #80 backward, dead zone between = hover (the original
  moved only on keypress). Homing always guards the map edge }
  BMI270_I2C_ADDR = $69;     { board fact: SDO pulled high }
  ROLL_DEAD  = 12;                  { deg of lean before steering starts }
  ROLL_FULL  = 45;                  { deg of lean = full 10 deg/frame turn }
  PITCH_FWD  = 25;                  { tilt below = forward (#72) }
  PITCH_BACK = 55;                  { tilt above = backward (#80) }
  LEAN_SIGN  = -1;                  { this mounting: lean-left reads rolldeg>0,
                                      sign chosen so lean-left = the 94 #75
                                      (dec dir = turn left; the scene then
                                      slides RIGHT, like turning your head
                                      left - verified on hardware) }

  { background control-task cadence (ms; FREERTOS_HZ=1000: ms == ticks).
    3 Hz - a hand-held lean is a slow signal; the frame loop applies the
    published integers every frame regardless (a held lean behaves like
    a held key), only sub-period transients get quantized }
  CTRL_PERIOD_MS = 333;

  { mp out-of-bounds pad. 94 reached past its 64 KiB map line: plasma
    writes up to 256*256+256 = 65792 and draw samples 256*iyp+ixp with
    iyp/ixp in [-110, 365] -> indices [-28270, 93725]. On DOS those hit
    adjacent (mapped, harmless) RAM; here the pad keeps them inside this
    allocation so the algorithm needs no edits. Rounded to 4 KiB. }
  MAP_LOW   = 28672;
  MAP_BLOCK = 122880;

  { autopilot (the 94 readkey branch's replacement): wander + homing }
  STEP       = 1;         { map units per frame; 94 used 4 per keypress }
  WANDER_AMP = 2;         { deg per frame, sinusoidal heading wander }
  WANDER_DIV = 25;
  HOME_MARGIN = 72;       { roam box: steer home outside 72..183 }
  HOME_RATE   = 3;        { deg per frame toward center, max }
  BRIGHTNESS  = 60;       { percent, AMOLED unattended }

type
  { periph_gpio.h - not bound in c_bmgr; only ever read for the motor }
  TPeriphGpioHandle = record
    gpio_num: cint;
  end;
  PPeriphGpioHandle = ^TPeriphGpioHandle;

var
  { the double frame buffer replaces the VGA's visible A000 segment -
    two 480x480 BE-RGB565 panels in PSRAM, flipped under the TE lock }
  frame: array[0..1] of ^cuint16;
  fback: integer;
  lut: array[0..127] of cuint16;   { palette index -> BE RGB565 }

  { panel side, owned by esp_init }
  panel: esp_lcd_panel_handle_t;
  raw: ^lrgarr;                    { the padded mp block (see MAP_*) }

  { diagnostics, adapter side }
  frames, flush_errs: integer;
  last_us: int64;

  { the "key state" the frame loop reads (94: readkey). Written by the
    background ctrl task every CTRL_PERIOD_MS:
      ctrl_dturn   turn per frame        (94 #75/#77)
      ctrl_dx/dy   movement per frame    (94 #72/#80)
      ctrl_home    edge guard engaged: steer toward ctrl_desired
    Aligned 32-bit stores, single writer; a torn combination of adjacent
    samples is a bounded, imperceptible error for this slow signal.
    The homing CHASE (angular diff clamped to +-HOME_RATE) runs per
    frame in the main loop - computing it in this task and letting the
    loop re-apply it 10 times amplified the rate ~10x: overshoot limit
    cycle, dir swinging +-15 deg around the target (measured) }
  ctrl_dturn, ctrl_dx, ctrl_dy: integer;
  ctrl_desired: integer;           { homing target heading (deg) }
  ctrl_home: boolean;              { camera outside the roam box }

  tilt: TBmi270Tilt;               { sensor = tilt steering; imu = nil ->
                                      the ctrl task runs the wander
                                      simulation instead }


{ the background control task = the 94 readkey branch's "other side".
  Every CTRL_PERIOD_MS it recomputes the key state and publishes it as
  three integers: sensor steering when the BMI270 is up (all the float
  math - atan2 angles, movement vector - happens HERE), the wander
  simulation when it is not. The frame loop just applies the numbers;
  it neither knows nor cares where they came from }
procedure ctrl_task(arg: pointer); cdecl;
var
  rolldeg, tiltdeg: double;
  n, desired, diff, dturn, step: integer;
begin
  n := 0;
  repeat
    dturn := 0; step := 0;
    if tilt.imu <> nil then
    begin
      if tilt.Read(rolldeg, tiltdeg) then
      begin
        if abs(rolldeg) > ROLL_DEAD then
        begin
          dturn := LEAN_SIGN * round(10 * rolldeg / ROLL_FULL);
          if dturn > 10 then dturn := 10;
          if dturn < -10 then dturn := -10
        end;
        if tiltdeg < PITCH_FWD then step := 4              { 94: #72 }
        else if tiltdeg > PITCH_BACK then step := -4       { 94: #80 }
      end
    end
    else
    begin
      dturn := round(WANDER_AMP * sin(n / WANDER_DIV));    { autopilot sim }
      step := STEP
    end;

    { homing target (heading toward the map center) - float here; the
      per-frame chase is integer math in the frame loop }
    ctrl_home := (x < HOME_MARGIN) or (x > 255-HOME_MARGIN) or
                 (y < HOME_MARGIN) or (y > 255-HOME_MARGIN);
    if ctrl_home then
      ctrl_desired := round(arctan2(128 - x, 128 - y) * 180 / pi);

    { the 94 movement arithmetic, done here: the frame loop adds
      ready integers. NOTE: LEAN_SIGN applied to the LEAN term only,
      above - folding homing into the same sign flip once turned
      homing into anti-homing (a stable +-3 deg/sample limit cycle at
      exactly 180 deg from the map center: a stationary board swayed
      +-20 deg forever; found via the raw-sample stream) }
    ctrl_dturn := dturn;
    ctrl_dx := round(step * sin(dir/180*pi));
    ctrl_dy := round(step * cos(dir/180*pi));
    inc(n);
    vTaskDelay(CTRL_PERIOD_MS)
  until false
end;

{ everything the 94 program had no equivalent for: board bring-up, the
  DMA-direct panel-io (the BMGR-generated one bounces PSRAM through
  internal RAM), the TE line, the double frame buffer }
procedure esp_init;
var
  ret: esp_err_t;
  motorh, lcdh: pointer;
  lcd_handles: Pdev_display_lcd_handles_t;
  cfgp: Pdev_display_lcd_config_t;
  devcfg: dev_display_lcd_config_t;
  raw16: pointer;
  b: integer;
begin
  if esp_board_manager_init <> ESP_OK then
  begin
    writeln(TAG, ': E esp_board_manager_init failed');
    halt
  end;
  writeln(TAG, ': I board manager init ok');

  { dev_gpio_ctrl semantics: init drives active_level=1 -> constant
    vibration until told otherwise (pi_display.c / board_motor.c hedge) }
  motorh := nil;
  if (esp_board_manager_get_device_handle('vibration_motor', @motorh) = ESP_OK) and
     (motorh <> nil) then
    gpio_set_level(PPeriphGpioHandle(motorh)^.gpio_num, 0);

  { panel config ownership via BMGR's documented re-init path. The
    generated io config leaves psram_dma_direct off (the SPI master
    then bounces every 450 KiB frame through internal RAM - measured
    40 ms/frame) and runs 40 MHz; an esp_lcd panel object binds its io
    at creation, so patching means rebuilding: copy the generated
    config, patch the two fields, then deinit -> override_config ->
    init. The rebuilt panel is BMGR-owned - no duplicate object, one
    config source (generated + APP override) }
  ret := esp_board_manager_get_device_config(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD, @cfgp);
  if (ret <> ESP_OK) or (cfgp = nil) then
  begin
    writeln(TAG, ': E display_lcd config: ', ret);
    halt
  end;
  devcfg := cfgp^;
  devcfg.sub_cfg.spi.io_spi_config.flags :=
    devcfg.sub_cfg.spi.io_spi_config.flags or SPI_FLAG_psram_dma_direct;
  devcfg.sub_cfg.spi.io_spi_config.pclk_hz := 80000000;
  ret := esp_board_manager_deinit_device_by_name(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD);
  if ret <> ESP_OK then
  begin
    writeln(TAG, ': E display_lcd deinit: ', ret);
    halt
  end;
  ret := esp_board_device_override_config(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD,
    @devcfg, cuint16(sizeof(dev_display_lcd_config_t)));
  if ret <> ESP_OK then
  begin
    writeln(TAG, ': E display_lcd override_config: ', ret);
    halt
  end;
  ret := esp_board_manager_init_device_by_name(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD);
  if ret <> ESP_OK then
  begin
    writeln(TAG, ': E display_lcd re-init: ', ret);
    halt
  end;

  { re-fetch: the re-init built a NEW panel object }
  lcdh := nil;
  ret := esp_board_manager_get_device_handle(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD, @lcdh);
  if (ret <> ESP_OK) or (lcdh = nil) then
  begin
    writeln(TAG, ': E display_lcd handle: ', ret);
    halt
  end;
  lcd_handles := Pdev_display_lcd_handles_t(lcdh);
  panel := lcd_handles^.panel_handle;
  if panel = nil then
  begin
    writeln(TAG, ': E display_lcd panel_handle is nil');
    halt
  end;

  { BMGR does not manage brightness on this board (no brightness device
    in the pack; CO5300 is an AMOLED - brightness is a vendor register,
    and every re-init resets it to the driver default max) }
  {if esp_lcd_panel_co5300_set_brightness(panel, BRIGHTNESS) <> ESP_OK then
    writeln(TAG, ': W set_brightness failed (running at driver default)');}

  { BMI270 tilt steering: the sensor chain (open on the BMGR i2c_master
     bus at the board's 0x69, config, boot-pose baseline) lives in the
     bmi270tilt unit; failure just means the ctrl task falls back to
     the wander simulation. The periph name and address are board
     facts - they stay here }
  if tilt.Init('i2c_master', BMI270_I2C_ADDR) then
    writeln(TAG, ': I BMI270 up - tilt steering, lateral zero=',
            tilt.ax0:5:2, 'g')
  else
    writeln(TAG, ': W no BMI270 - wander simulation');

  { double frame buffer, cache-line aligned for the DMA-direct path,
    tail slack for the 94 row-overpaint quirk (see FRAME_SLACK) }
  for b := 0 to 1 do
  begin
    GetMem(raw16, size_t(W * H * 2) + FRAME_SLACK + 64);
    frame[b] := pointer((PtrUInt(raw16) + 63) and not PtrUInt(63));
    fillchar(frame[b]^, W * H * 2 + FRAME_SLACK, 0);
  end;

  fback := 0; frames := 0; flush_errs := 0;
  ctrl_dturn := 0; ctrl_dx := 0; ctrl_dy := 0;
  scr := frame[0];                 { draw paints here; vga_flush flips it }
  last_us := esp_timer_get_time;
  writeln(TAG, ': I display ready (own io psram_dma_direct, 80 MHz)');

  { the control task always runs (sensor steering or the wander sim).
    Created LAST so everything it touches is already up }
  if xTaskCreatePinnedToCore(@ctrl_task, 'ctrl', 8192, nil, 1, nil,
                             TSK_NO_AFFINITY) = 1 then
    writeln(TAG, ': I ctrl task up')
  else
    writeln(TAG, ': W ctrl task failed - the camera hovers in place');
end;

{ the 94 video-mode + DAC block: clear both panel buffers (the panel
  keeps showing whatever the driver init left until the first flush)
  and load the palette - as BE RGB565 LUT entries instead of DAC bytes }
procedure vga_setmode;
var
  i, r, g, b, c: integer;
begin
  fillchar(frame[0]^, W * H * 2, 0);
  fillchar(frame[1]^, W * H * 2, 0);
  for i := 0 to 127 do
  begin
    r := pal[3*i+1] shr 1;         { 6-bit -> 5 }
    g := pal[3*i+2];               { 6-bit fits RGB565 green }
    b := pal[3*i+3] shr 1;
    c := (r shl 11) or (g shl 5) or b;
    lut[i] := cuint16(((c and $FF) shl 8) or ((c shr 8) and $FF));
  end;
end;

{ the 94 blit: move(scr^,mem[$A000:0],64000). draw paints BE RGB565
  straight into the panel buffer scr points at, so the flush is just
  the DMA queue plus the flip; scr follows the flip. No sync to the
  panel scan (accepted tearing, see the consts) - yet the queue path
  blocks a few ms per frame recycling SPI descriptors, which is what
  feeds the idle task. fps telemetry lives here, adapter side. }
procedure vga_flush;
var
  now_us: int64;
  fps10: integer;
begin
  if esp_lcd_panel_draw_bitmap(panel, 0, 0, W, H, scr) <> ESP_OK then
    inc(flush_errs);
  { x_end/y_end are EXCLUSIVE in this driver (CASET gets x_end-1) }
  fback := fback xor 1;
  scr := frame[fback];

  inc(frames);
  if frames mod 100 = 0 then
  begin
    now_us := esp_timer_get_time;
    fps10 := round(1000 * 1000000 / (now_us - last_us));
    writeln(TAG, ': I frame ', frames, ' fps=', fps10 div 10, '.',
            fps10 mod 10, ' err=', flush_errs);
    last_us := now_us;
  end;
end;

{ ================================================================ 94 code }

function ncol(mc,n,dvd : integer): integer;
var loc : integer;
begin
 loc:=(mc+n-random(2*n)) div dvd; ncol:=loc;
 if loc>250 then ncol:=250; if loc<5 then ncol:=5
end;

procedure plasma(x1,y1,x2,y2 : word);
var xn,yn,dxy,p1,p2,p3,p4 : word;
begin
 if (x2-x1<2) and (y2-y1<2) then EXIT;
 p1:=mp^[256*y1+x1]; p2:=mp^[256*y2+x1]; p3:=mp^[256*y1+x2];
 p4:=mp^[256*y2+x2]; xn:=(x2+x1) shr 1; yn:=(y2+y1) shr 1;
 dxy:=5*(x2-x1+y2-y1) div 3;
 if mp^[256*y1+xn]=0 then mp^[256*y1+xn]:=ncol(p1+p3,dxy,2);
 if mp^[256*yn+x1]=0 then mp^[256*yn+x1]:=ncol(p1+p2,dxy,2);
 if mp^[256*yn+x2]=0 then mp^[256*yn+x2]:=ncol(p3+p4,dxy,2);
 if mp^[256*y2+xn]=0 then mp^[256*y2+xn]:=ncol(p2+p4,dxy,2);
 mp^[256*yn+xn]:=ncol(p1+p2+p3+p4,dxy,4);
 plasma(x1,y1,xn,yn); plasma(xn,y1,x2,yn);
 plasma(x1,yn,xn,y2); plasma(xn,yn,x2,y2);
end;

{ 94 的 draw, 结构逐行对齐, 常量原生 480x480(只调参数, 不动算法):
  480/230400 = 320/64000 的面板原生值;  240 = 160/100 的中心/地平线;
  540 = 360 x 1.5(分辨率);  54 = 30 x 1.5 x 1.2(分辨率 x mode-13h 在
  4:3 CRT 上的像素纵横比) - 即方像素面板重现 94 玩家在 CRT 上看到的
  实际比例(世界纵横比 10:1);  478 = 480-2 裁剪;  s 的 450 = 300 x 1.5;
  rng 哨兵 200 -> 480。paint 行当场查 LUT 写 16 位面板缓冲(94 在 DAC);
  scr 指向双缓冲之一, 翻转由 vga_flush 维护。 }
procedure draw(xp,yp,dir : integer);
var z,zobs,ix,iy,iy1,iyp,ixp,x,y,s,csf,snf,mpc,i,j : integer;
begin
 for i:=0 to 481 do rng[i]:=480;  zobs:=100+mp^[256*yp+xp];
 csf:=round(256*cos(dir/180*pi)); snf:=round(256*sin(dir/180*pi));
 fillchar(scr^,480*480*2,0);
 for iy:=yp to yp+55 do
 begin
  iy1:=1+2*(iy-yp); s:=4+450 div iy1;
  for ix:=xp+yp-iy to xp-yp+iy do
  begin
   ixp:=xp+((ix-xp)*csf+(iy-yp)*snf) div 256;
   iyp:=yp+((iy-yp)*csf-(ix-xp)*snf) div 256;
   x:=240+540*(ix-xp) div iy1;
   if (x>=0) and (x+s<=478) then
   begin
    z:=mp^[256*iyp+ixp]; mpc:=z shr 1;
    if z<47 then z:=46;  y:=240+54*(zobs-z) div iy1;
    if (y<=479) and (y>=0) then
     for j:=x to x+s do
     begin
      for i:=y to rng[j] do scr[480*i+j]:=lut[mpc];
      if y<rng[j] then rng[j]:=y
     end;
   end;
  end;
 end;
 vga_flush;               { 94: move(scr^,mem[$A000:0],64000) }
end;

{ ------------------------------------------------------------------ main }

begin
 writeln('Use arrow keys to pan in/out left/right ... any key to continue ..');
 writeln('(ESP port: steer by tilting the board - lean turns, flat/vertical is fwd/back)');
 esp_init;                { 94: readkey - the display chain takes its place }

 randomize; x:=0; y:=0; dir:=0;
 GetMem(raw, MAP_BLOCK);  { 94: new(mp) - padded, see MAP_LOW/MAP_BLOCK }
 mp := pointer(PtrUInt(raw) + MAP_LOW);
 fillchar(raw^, MAP_BLOCK, 0);  { 94: fillchar(mp^,65535,0) - pad included }
 { 94: new(scr) - scr 已由 esp_init 指向面板双缓冲 }
 mp^[$0000]:=128; plasma(0,0,256,256);
 vga_setmode;             { 94: int10 $13 + port[$3C8]/[$3C9] palette }

 repeat
  dir:=dir mod 360; draw(x,y,dir);
  { 94: case readkey of #75/#77/#72/#80 - the "keys" are the ctrl_*
    integers, refreshed by the background task (tilt sensor, or the
    wander simulation when absent); this loop neither knows nor cares }
  dir:=dir+ctrl_dturn;  y:=y+ctrl_dy;  x:=x+ctrl_dx;


  { homing: a held forward tilt is a steady march, and past the map
    edge the map sampling soon leaves the padded block - reads turn to
    neighboring heap garbage, then unmapped memory resets the chip
    (the 94 never guarded this because DOS read past the map
    harmlessly). When the ctrl task sees the camera outside the roam
    box it publishes the heading to the map center; the chase runs
    here, clamped to +-HOME_RATE deg per frame }
  if ctrl_home then
  begin
   diff:=(ctrl_desired-dir) mod 360;
   if diff < -180 then diff:=diff+360;
   if diff >= 180 then diff:=diff-360;
   if diff > HOME_RATE then diff:=HOME_RATE;
   if diff < -HOME_RATE then diff:=-HOME_RATE;
   dir:=dir+diff
  end;
  dir:=((dir mod 360)+360) mod 360;
  { the map edge itself is the hard stop - last-resort guard }
  if x<0 then x:=0; if x>255 then x:=255;
  if y<0 then y:=0; if y>255 then y:=255;
  vTaskDelay(0);          { courtesy yield; never blocks }

 until false;
end.
