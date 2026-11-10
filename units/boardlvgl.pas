{ boardlvgl - L2 native facade over the board display chain
  (esp_board_manager devices -> esp_lvgl_adapter -> live LVGL screen).

  Layer grammar (units/README.md): unprefixed functional unit name = L2
  Pascal-native service built on the L1 bindings. The API is advanced-
  record static methods; esp_err_t
  stays visible; no exceptions; no state beyond the two stored handles
  and the optional-device init snapshot - every Start call re-queries
  the C registry, nothing is cached.

  Contract:

    uses boardlvgl;                       (bmgr display-chain devices
                                             auto-initialized here)
    ...
    if TBoardLvgl.Start <> ESP_OK then   (adapter init + register
                                             display/touch + start)
      ...;
    TBoardLvgl.UILock;
    lv_label_create(lv_screen_active());    (Pascal UI over c_lvgl)
    TBoardLvgl.UIUnlock;

  - auto-init at use covers lcd_touch/lcd_brightness only (lazy
    init_device_by_name, warn-and-continue, exactly like lvgl-s31
    main.c); display_lcd is brought up inside Start by the boarddisplay
    panel chain (psram_dma_direct + 80 MHz overrides included). Full-
    board initialization (audio, buttons, battery, ...) stays L1: call
    esp_board_manager_init() from c_bmgr yourself.
  - configuration is a value-semantics record (TBoardLvglConfig,
    DefaultConfig = the display_lvgl-verified behavior). Callback hooks
    (auto-sleep, touch custom read) and the TE/mono display profiles are
    NOT in the L2 config - those need the L1 c_lvgl_adapter full API.
  - after a successful Start, lv_screen_active() is live but the LVGL
    worker task owns rendering: wrap EVERY app-side LVGL call in
    UILock/UIUnlock (the lvgl_test_ui.c ui_acquire/ui_release pattern),
    including inside event callbacks.
  - Stop is terminal: it tears the chain down exactly like main.c's
    cleanup path (adapter deinit + the three devices deinit) and the
    unit does not re-initialize afterwards. }

unit boardlvgl;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  c_bmgr,          { esp_err_t, device-name constants, ppvoid }
  c_lvgl_adapter,  { adapter config types, macro equivalents, API, handles }
  boarddisplay;    { L2 panel chain: display_lcd bring-up + board overrides }

type
  { Value-semantics configuration. Field defaults = the behavior of the
    verified display_lvgl example (its main.c overrides + the PSRAM display
    profile macro this board's CONFIG_SPIRAM=y selects). hor_res/ver_res
    and the panel/io handles are deliberately absent - the facade reads
    them from the bmgr device config at Start; that is the point of the
    chain. }
  TBoardLvglConfig = record
    { --- adapter worker: 1:1 with esp_lv_adapter_config_t values --- }
    TaskStackSize: cuint;        { default 6*1024, example-verified }
    TaskPriority: cuint;         { default 4 }
    TaskCoreID: cint;            { default 1 }
    TickPeriodMs: cuint;         { default 5 }
    TaskMinDelayMs: cuint;       { default 1 }
    TaskMaxDelayMs: cuint;       { default 500 }
    StackInPsram: cbool;         { default false }
    { --- auto-sleep (callbacks stay L1) --- }
    AutoSleepEnable: cbool;                            { default false }
    AutoSleepMode: esp_lv_adapter_auto_sleep_mode_t;   { default DISABLED }
    AutoSleepTimeoutMs: cuint;                         { default 5000 }
    { --- display profile overrides on the SPI macro base --- }
    Rotation: esp_lv_adapter_rotation_t;               { default ROTATE_0
                                  (the C SPI branch keeps rotation 0) }
    UsePsram: cbool;                                   { default true
                                  (CONFIG_SPIRAM=y in this sdkconfig) }
    EnablePpaAccel: cbool;                             { default false }
    RequireDoubleBuffer: cbool;                        { default true }
    BufferHeight: cuint16;                             { default 0 = follow
                                  ver_res (the PSRAM macro behavior) }
    TearAvoidMode: esp_lv_adapter_tear_avoid_mode_t;   { default NONE
                                  (= TEAR_AVOID_MODE_DEFAULT) }
    { --- touch overrides --- }
    TouchScaleX: single;                               { default 1.0 }
    TouchScaleY: single;                               { default 1.0 }
    TouchMultiMode: esp_lv_adapter_touch_mode_t;       { default SINGLE }
    TouchMultiPointers: cuint8;                        { default 1 }
  end;

  TBoardLvgl = record
  public
    { the verified-default configuration }
    class function DefaultConfig: TBoardLvglConfig; static;

    { zero-arg default path: "one call lights the screen" }
    class function Start: esp_err_t; static; overload;

    { fully configurable path. Brings the panel up through the
      boarddisplay chain (TBoardDisplay.Start), brings the adapter up,
      registers the display (SPI+PSRAM branch, runtime sub_type fallbacks
      mirror
      main.c's CONFIG-gated #else branches) and - if lcd_touch
      initialized - touch, then starts the worker. Stores the handles. }
    class function StartEx(
      const AConfig: TBoardLvglConfig): esp_err_t; static; overload;

    { terminal teardown: unregister touch/display, adapter deinit, the
      three devices deinit - main.c's cleanup path as a function }
    class function Stop: esp_err_t; static;

    { app-side UI mutex: wrap EVERY LVGL call (including inside event
      callbacks, like lvgl_test_ui.c does) in UILock/UIUnlock }
    class procedure UILock; static;
    class procedure UIUnlock; static;

    { registered handles; nil before Start / after failed registration }
    class function Display: plv_display_t; static;
    class function Touch: plv_indev_t; static;
  end;

implementation

const
  TAG = 'boardlvgl';

{ C strcmp - newlib, always linked in the IDF build; same approach as the
  display_lvgl example's port }
function strcmp(a, b: PChar): cint; cdecl; external;

var
  { optional-device init snapshots, taken once when the unit is
    initialized; display_lcd is not here - TBoardDisplay.Start owns it }
  TouchInited: esp_err_t;
  BrightnessInited: esp_err_t;

  FDisplay: plv_display_t = nil;
  FTouch: plv_indev_t = nil;
  FStarted: Boolean = False;

{ --------------------------------------------------------------- TBoardLvgl }

class function TBoardLvgl.DefaultConfig: TBoardLvglConfig;
begin
  Result := Default(TBoardLvglConfig);
  Result.TaskStackSize     := 6 * 1024;
  Result.TaskPriority      := 4;
  Result.TaskCoreID        := 1;
  Result.TickPeriodMs      := 5;
  Result.TaskMinDelayMs    := 1;
  Result.TaskMaxDelayMs    := 500;
  Result.StackInPsram      := False;
  Result.AutoSleepEnable   := False;
  Result.AutoSleepMode     := ESP_LV_ADAPTER_AUTO_SLEEP_MODE_DISABLED;
  Result.AutoSleepTimeoutMs := ESP_LV_ADAPTER_DEFAULT_AUTO_SLEEP_TIMEOUT_MS;
  Result.Rotation          := ESP_LV_ADAPTER_ROTATE_0;
  Result.UsePsram          := True;
  Result.EnablePpaAccel    := False;
  Result.RequireDoubleBuffer := True;
  Result.BufferHeight      := 0;
  Result.TearAvoidMode     := ESP_LV_ADAPTER_TEAR_AVOID_MODE_NONE;
  Result.TouchScaleX       := 1.0;
  Result.TouchScaleY       := 1.0;
  Result.TouchMultiMode    := ESP_LV_ADAPTER_TOUCH_MODE_SINGLE;
  Result.TouchMultiPointers := 1;
end;

class function TBoardLvgl.Start: esp_err_t;
begin
  Result := StartEx(DefaultConfig);
end;

class function TBoardLvgl.StartEx(
  const AConfig: TBoardLvglConfig): esp_err_t;
var
  adapter_config: esp_lv_adapter_config_t;
  disp_cfg: esp_lv_adapter_display_config_t;
  touch_cfg: esp_lv_adapter_touch_config_t;
  ret: esp_err_t;
  lcd_handle: pointer;
  lcd_cfg: Pdev_display_lcd_config_t;
  lcd_handles: Pdev_display_lcd_handles_t;
  touch_handle: pointer;
  touch_handles: Pdev_lcd_touch_handles_t;
begin
  if FStarted then
    exit(ESP_ERR_INVALID_STATE);
  { the panel chain (display_lcd bring-up + this board's
    psram_dma_direct + 80 MHz overrides) lives in the boarddisplay unit;
    it writeln's and halts inside on failure - a panel that did not come
    up leaves nothing to return to }
  ret := TBoardDisplay.Start;
  if ret <> ESP_OK then
    exit(ret);

  writeln(TAG, ': I Initializing LVGL adapter...');
  adapter_config := Default(esp_lv_adapter_config_t);
  adapter_config.task_stack_size   := AConfig.TaskStackSize;
  adapter_config.task_priority     := AConfig.TaskPriority;
  adapter_config.task_core_id      := AConfig.TaskCoreID;
  adapter_config.tick_period_ms    := AConfig.TickPeriodMs;
  adapter_config.task_min_delay_ms := AConfig.TaskMinDelayMs;
  adapter_config.task_max_delay_ms := AConfig.TaskMaxDelayMs;
  adapter_config.stack_in_psram    := AConfig.StackInPsram;
  adapter_config.auto_sleep.enable          := AConfig.AutoSleepEnable;
  adapter_config.auto_sleep.mode            := AConfig.AutoSleepMode;
  adapter_config.auto_sleep.idle_timeout_ms := AConfig.AutoSleepTimeoutMs;
  { .auto_sleep.callbacks stay zeroed - callback hooks are L1 territory }

  ret := esp_lv_adapter_init(@adapter_config);
  if ret <> ESP_OK then
  begin
    writeln(TAG, ': E esp_lv_adapter_init: ', ret);
    exit(ret);
  end;

  lcd_handle := nil;
  ret := esp_board_manager_get_device_handle(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD,
    @lcd_handle);
  if (ret <> ESP_OK) or (lcd_handle = nil) then
  begin
    writeln(TAG, ': E Failed to get display_lcd device handle');
    esp_lv_adapter_deinit;
    exit(ESP_FAIL);
  end;

  lcd_cfg := nil;
  ret := esp_board_manager_get_device_config('display_lcd', @lcd_cfg);
  if (ret <> ESP_OK) or (lcd_cfg = nil) then
  begin
    writeln(TAG, ': E Failed to get display_lcd config');
    esp_lv_adapter_deinit;
    exit(ESP_FAIL);
  end;

  lcd_handles := Pdev_display_lcd_handles_t(lcd_handle);

  { runtime sub_type dispatch, main.c's shape with this board's
    CONFIG-gated branches as logged fallbacks }
  if (strcmp(lcd_cfg^.sub_type, ESP_BOARD_DEVICE_LCD_SUB_TYPE_SPI) = 0) or
     (strcmp(lcd_cfg^.sub_type, ESP_BOARD_DEVICE_LCD_SUB_TYPE_I80) = 0) or
     (strcmp(lcd_cfg^.sub_type, ESP_BOARD_DEVICE_LCD_SUB_TYPE_PARLIO) = 0) then
  begin
    if AConfig.UsePsram then
      disp_cfg := ESP_LV_ADAPTER_DISPLAY_SPI_WITH_PSRAM_DEFAULT_CONFIG(
        lcd_handles^.panel_handle, lcd_handles^.io_handle,
        lcd_cfg^.lcd_width, lcd_cfg^.lcd_height, AConfig.Rotation)
    else
      disp_cfg := ESP_LV_ADAPTER_DISPLAY_SPI_WITHOUT_PSRAM_DEFAULT_CONFIG(
        lcd_handles^.panel_handle, lcd_handles^.io_handle,
        lcd_cfg^.lcd_width, lcd_cfg^.lcd_height, AConfig.Rotation);
    disp_cfg.profile.enable_ppa_accel     := AConfig.EnablePpaAccel;
    disp_cfg.profile.require_double_buffer := AConfig.RequireDoubleBuffer;
    if AConfig.BufferHeight <> 0 then
      disp_cfg.profile.buffer_height := AConfig.BufferHeight;
    disp_cfg.tear_avoid_mode := AConfig.TearAvoidMode;
  end
  else if strcmp(lcd_cfg^.sub_type, ESP_BOARD_DEVICE_LCD_SUB_TYPE_DSI) = 0 then
  begin
    writeln(TAG, ': E DSI support not enabled');
    esp_lv_adapter_deinit;
    exit(ESP_FAIL);
  end
  else if (strcmp(lcd_cfg^.sub_type, ESP_BOARD_DEVICE_LCD_SUB_TYPE_RGB) = 0) or
          (strcmp(lcd_cfg^.sub_type, ESP_BOARD_DEVICE_LCD_SUB_TYPE_RGB_3WIRE_SPI) = 0) then
  begin
    writeln(TAG, ': E RGB support not enabled');
    esp_lv_adapter_deinit;
    exit(ESP_FAIL);
  end
  else
  begin
    writeln(TAG, ': E Unknown LCD sub_type: ', lcd_cfg^.sub_type);
    esp_lv_adapter_deinit;
    exit(ESP_FAIL);
  end;

  writeln(TAG, ': I Register LCD to LVGL adapter: sub_type=', lcd_cfg^.sub_type,
    ', size=', lcd_cfg^.lcd_width, 'x', lcd_cfg^.lcd_height,
    ', rotation=', Ord(AConfig.Rotation), ', tear_mode=',
    Ord(disp_cfg.tear_avoid_mode));

  FDisplay := esp_lv_adapter_register_display(@disp_cfg);
  if FDisplay = nil then
  begin
    writeln(TAG, ': E Failed to register display to LVGL adapter');
    esp_lv_adapter_deinit;
    exit(ESP_FAIL);
  end;

  { touch: optional, warn-and-continue like main.c }
  if TouchInited = ESP_OK then
  begin
    touch_handle := nil;
    if (esp_board_manager_get_device_handle(ESP_BOARD_DEVICE_NAME_LCD_TOUCH,
          @touch_handle) = ESP_OK) and (touch_handle <> nil) then
    begin
      touch_handles := Pdev_lcd_touch_handles_t(touch_handle);
      touch_cfg := ESP_LV_ADAPTER_TOUCH_DEFAULT_CONFIG(FDisplay,
        touch_handles^.touch_handle);
      touch_cfg.scale.x := AConfig.TouchScaleX;
      touch_cfg.scale.y := AConfig.TouchScaleY;
      touch_cfg.multi_touch.mode := AConfig.TouchMultiMode;
      touch_cfg.multi_touch.pointers := AConfig.TouchMultiPointers;
      FTouch := esp_lv_adapter_register_touch(@touch_cfg);
      if FTouch = nil then
        writeln(TAG, ': W Failed to add touch input')
      else
        writeln(TAG, ': I Touch input added');
    end;
  end;

  ret := esp_lv_adapter_start;
  if ret <> ESP_OK then
  begin
    writeln(TAG, ': E esp_lv_adapter_start: ', ret);
    if FTouch <> nil then
      esp_lv_adapter_unregister_touch(FTouch);
    esp_lv_adapter_unregister_display(FDisplay);
    esp_lv_adapter_deinit;
    FTouch := nil;
    FDisplay := nil;
    exit(ret);
  end;

  FStarted := True;
  writeln(TAG, ': I Display chain started, lv_screen_active() is live');
  Result := ESP_OK;
end;

class function TBoardLvgl.Stop: esp_err_t;
begin
  if not FStarted then
    exit(ESP_ERR_INVALID_STATE);
  if FTouch <> nil then
    esp_lv_adapter_unregister_touch(FTouch);
  if FDisplay <> nil then
    esp_lv_adapter_unregister_display(FDisplay);
  esp_lv_adapter_deinit;
  FTouch := nil;
  FDisplay := nil;
  FStarted := False;

  { device teardown in main.c's cleanup order: brightness, display, touch }
  esp_board_manager_deinit_device_by_name(ESP_BOARD_DEVICE_NAME_LCD_BRIGHTNESS);
  esp_board_manager_deinit_device_by_name(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD);
  esp_board_manager_deinit_device_by_name(ESP_BOARD_DEVICE_NAME_LCD_TOUCH);

  writeln(TAG, ': I Display chain stopped (terminal)');
  Result := ESP_OK;
end;

class procedure TBoardLvgl.UILock;
begin
  esp_lv_adapter_lock(-1);
end;

class procedure TBoardLvgl.UIUnlock;
begin
  esp_lv_adapter_unlock;
end;

class function TBoardLvgl.Display: plv_display_t;
begin
  Result := FDisplay;
end;

class function TBoardLvgl.Touch: plv_indev_t;
begin
  Result := FTouch;
end;

initialization

{ use = the optional display-chain devices are initialized: lazy
  init_device_by_name, warn-and-continue - the lvgl-s31 main.c behavior.
  display_lcd is deliberately absent: TBoardDisplay.Start (boarddisplay
  panel chain) owns its whole lifecycle, overrides included.
  Runs inside PASCALMAIN (app_main context), after the software USB
  console wrap chain is up, so writeln is live. }
TouchInited := esp_board_manager_init_device_by_name(
  ESP_BOARD_DEVICE_NAME_LCD_TOUCH);
if TouchInited <> ESP_OK then
  writeln(TAG, ': W init lcd_touch: ', TouchInited, ', continue');

BrightnessInited := esp_board_manager_init_device_by_name(
  ESP_BOARD_DEVICE_NAME_LCD_BRIGHTNESS);
if BrightnessInited <> ESP_OK then
  writeln(TAG, ': W init lcd_brightness: ', BrightnessInited, ', continue');

end.
