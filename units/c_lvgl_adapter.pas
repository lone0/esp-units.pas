{ c_lvgl_adapter - Pascal binding (L1, C-ABI shadow) for the
  espressif__esp_lvgl_adapter C component. Layer grammar
  (units/README.md): `c_<C component short name>` = L1 binding -
  hand-converted C headers only, `cdecl; external` functions keep their C
  names; Pascal-native services live in unprefixed L2 units (see
  boarddisplay for the display-chain facade over this binding).

  Source: managed_components/espressif__esp_lvgl_adapter in the
  lvgl-s31 SDK tree:
    include/esp_lv_adapter.h           core API + worker config
    include/esp_lv_adapter_display.h   display registration + profiles
    include/esp_lv_adapter_input.h     touch registration

  Flattened with the project's toolchain against its sdkconfig
  (ESP-Mosaico): CONFIG_ESP_LVGL_ADAPTER_ENABLE_FS / _DECODER / _FREETYPE /
  _BUTTON / _KNOB / _FPS_STATS are all OFF there, so those API blocks
  compile out in C and are absent here. The binding covers the active
  surface: adapter init/start/deinit, display + touch registration,
  thread-safety lock, activity + wake reporting, pause/resume, sleep
  prepare/recover, dummy draw on/off.

  Struct sizes/offsets are the C ones on riscv32 ILP32 (pointers 4 B,
  enums 4 B via -$MINENUMSIZE 4, C bool 1 B, float 4 B, -$PACKRECORDS C):
  display_config 72 B (profile 24 + te_sync 36), touch_config 36 B,
  adapter_config 52 B (auto_sleep 24).

  The C header builds configs through designated-initializer macros -
  ESP_LV_ADAPTER_DEFAULT_CONFIG(), ESP_LV_ADAPTER_DISPLAY_SPI_WITH_PSRAM_
  DEFAULT_CONFIG(panel, io, w, h, rot), ESP_LV_ADAPTER_TOUCH_DEFAULT_
  CONFIG(disp, handle). Macros cannot be `external`, so the equivalents
  below are plain Pascal record-returning functions expanding to exactly
  the same field values (verified against every macro in the two headers:
  task 8192/prio 6/core -1/tick 1/min 1/max 15/auto sleep off; PSRAM
  profile = interface OTHER + buffer_height = ver_res + use_psram +
  require_double_buffer + PPA off + mono NONE; touch scale 1.0/1.0 +
  SINGLE + zeroed callbacks; TE disabled via gpio_num = -1). }

unit c_lvgl_adapter;

{$mode objfpc}{$H+}
{$packrecords C}
{$minenumsize 4}

interface

uses
  c_bmgr;  { cint/cuint aliases, esp_err_t, the opaque esp_lcd_* handles }

{ ------------------------------------------------------------ constants }

const
  ESP_LV_ADAPTER_DEFAULT_STACK_SIZE            = 8 * 1024;
  ESP_LV_ADAPTER_DEFAULT_TASK_PRIORITY         = 6;
  ESP_LV_ADAPTER_DEFAULT_TASK_CORE_ID          = cint(-1);
  ESP_LV_ADAPTER_DEFAULT_TICK_PERIOD_MS        = 1;
  ESP_LV_ADAPTER_DEFAULT_TASK_MIN_DELAY_MS     = 1;
  ESP_LV_ADAPTER_DEFAULT_TASK_MAX_DELAY_MS     = 15;
  ESP_LV_ADAPTER_DEFAULT_AUTO_SLEEP_TIMEOUT_MS = 5000;

{ --------------------------------------------------------------- enums }

type
  { esp_lv_adapter_panel_interface_t }
  esp_lv_adapter_panel_interface_t = (
    ESP_LV_ADAPTER_PANEL_IF_RGB      = 0,
    ESP_LV_ADAPTER_PANEL_IF_MIPI_DSI = 1,
    ESP_LV_ADAPTER_PANEL_IF_OTHER    = 2
  );

  { esp_lv_adapter_mono_layout_t }
  esp_lv_adapter_mono_layout_t = (
    ESP_LV_ADAPTER_MONO_LAYOUT_NONE   = 0,
    ESP_LV_ADAPTER_MONO_LAYOUT_HTILED = 1,
    ESP_LV_ADAPTER_MONO_LAYOUT_VTILED = 2
  );

  { esp_lv_adapter_rotation_t }
  esp_lv_adapter_rotation_t = (
    ESP_LV_ADAPTER_ROTATE_0   = 0,
    ESP_LV_ADAPTER_ROTATE_90  = 90,
    ESP_LV_ADAPTER_ROTATE_180 = 180,
    ESP_LV_ADAPTER_ROTATE_270 = 270
  );

  { esp_lv_adapter_tear_avoid_mode_t }
  esp_lv_adapter_tear_avoid_mode_t = (
    ESP_LV_ADAPTER_TEAR_AVOID_MODE_NONE           = 0,
    ESP_LV_ADAPTER_TEAR_AVOID_MODE_DOUBLE_FULL    = 1,
    ESP_LV_ADAPTER_TEAR_AVOID_MODE_TRIPLE_FULL    = 2,
    ESP_LV_ADAPTER_TEAR_AVOID_MODE_DOUBLE_DIRECT  = 3,
    ESP_LV_ADAPTER_TEAR_AVOID_MODE_TRIPLE_PARTIAL = 4,
    ESP_LV_ADAPTER_TEAR_AVOID_MODE_TE_SYNC        = 5,
    ESP_LV_ADAPTER_TEAR_AVOID_MODE_DOUBLE_PARTIAL = 6
  );

  { esp_lv_adapter_te_pipeline_t }
  esp_lv_adapter_te_pipeline_t = (
    ESP_LV_ADAPTER_TE_PIPELINE_SYNC_FULL  = 0,
    ESP_LV_ADAPTER_TE_PIPELINE_ASYNC_FULL = 1
  );

  { esp_lv_adapter_touch_mode_t }
  esp_lv_adapter_touch_mode_t = (
    ESP_LV_ADAPTER_TOUCH_MODE_SINGLE        = 0,
    ESP_LV_ADAPTER_TOUCH_MODE_MULTI_CONTROL = 1
  );

  { esp_lv_adapter_auto_sleep_mode_t }
  esp_lv_adapter_auto_sleep_mode_t = (
    ESP_LV_ADAPTER_AUTO_SLEEP_MODE_DISABLED = 0,
    ESP_LV_ADAPTER_AUTO_SLEEP_MODE_PAUSE    = 1,
    ESP_LV_ADAPTER_AUTO_SLEEP_MODE_USER     = 2
  );

  { ESP_LV_ADAPTER_TEAR_AVOID_MODE_DEFAULT - see the const section below }

{ ------------------------------------------------- opaque LVGL handles }

{ lvgl.h stays out of the binding: the adapter API only passes these
  through. The real LVGL work happens in lvgl_test_ui.c, linked alongside
  by build.sh --c. }
type
  plv_display_t = pointer;         { lv_display_t* }
  plv_indev_t   = pointer;         { lv_indev_t* }

const
  { ESP_LV_ADAPTER_TEAR_AVOID_MODE_DEFAULT - a value macro in C
    (esp_lv_adapter_display.h: ESP_LV_ADAPTER_TEAR_AVOID_MODE_NONE) }
  ESP_LV_ADAPTER_TEAR_AVOID_MODE_DEFAULT =
    Ord(ESP_LV_ADAPTER_TEAR_AVOID_MODE_NONE);

{ -------------------------------------------------------------- records }

type
  { struct esp_lv_adapter_te_sync_config_t - 36 B }
  Pesp_lv_adapter_te_sync_config_t = ^esp_lv_adapter_te_sync_config_t;
  esp_lv_adapter_te_sync_config_t = record
    gpio_num:               cint;     { 0; -1 = TE disabled }
    time_tvdl_ms:           cuint;    { 4 }
    time_tvdh_ms:           cuint;    { 8 }
    bus_freq_hz:            cuint;    { 12 }
    data_lines:             cuint8;   { 16 }
    bits_per_pixel:         cuint8;   { 17 }
    { gpio_int_type_t (a 4 B C enum) - cint alias keeps identical layout }
    intr_type:              c_bmgr.gpio_num_t;  { 20 }
    refresh_window_percent: cuint8;   { 24 }
    pipeline:               esp_lv_adapter_te_pipeline_t;  { 28 }
    bounce_buffer_enabled:  cbool;    { 32 }
    bounce_buffer_rows:     cuint16;  { 34 }
  end;  { 36 }

  { struct esp_lv_adapter_display_profile_t - 24 B }
  Pesp_lv_adapter_display_profile_t = ^esp_lv_adapter_display_profile_t;
  esp_lv_adapter_display_profile_t = record
    panel_interface:       esp_lv_adapter_panel_interface_t;  { 0 - C name
                             "interface", a Pascal keyword }
    rotation:              esp_lv_adapter_rotation_t;  { 4 }
    hor_res:               cuint16;  { 8 }
    ver_res:               cuint16;  { 10 }
    buffer_height:         cuint16;  { 12 }
    use_psram:             cbool;    { 14 }
    enable_ppa_accel:      cbool;    { 15 }
    require_double_buffer: cbool;    { 16 }
    mono_layout:           esp_lv_adapter_mono_layout_t;  { 20 }
  end;  { 24 }

  { struct esp_lv_adapter_display_config_t - 72 B }
  Pesp_lv_adapter_display_config_t = ^esp_lv_adapter_display_config_t;
  esp_lv_adapter_display_config_t = record
    panel:           c_bmgr.esp_lcd_panel_handle_t;     { 0 }
    panel_io:        c_bmgr.esp_lcd_panel_io_handle_t;  { 4 }
    profile:         esp_lv_adapter_display_profile_t;    { 8 }
    tear_avoid_mode: esp_lv_adapter_tear_avoid_mode_t;    { 32 }
    te_sync:         esp_lv_adapter_te_sync_config_t;     { 36 }
  end;  { 72 }

  { struct esp_lv_adapter_touch_callbacks_t - 12 B }
  Pesp_lv_adapter_touch_callbacks_t = ^esp_lv_adapter_touch_callbacks_t;
  esp_lv_adapter_touch_callbacks_t = record
    on_interrupt: c_bmgr.TTouchIntrCb;  { 0 }
    { esp_err_t (*custom_touch_read)(tp, points, count, max_count, user_ctx) }
    custom_touch_read: pointer;           { 4 }
    user_ctx: pointer;                    { 8 }
  end;

  { struct esp_lv_adapter_touch_config_t - 36 B }
  Pesp_lv_adapter_touch_config_t = ^esp_lv_adapter_touch_config_t;
  esp_lv_adapter_touch_config_t = record
    disp:   plv_display_t;                { 0 }
    handle: c_bmgr.esp_lcd_touch_handle_t;  { 4 }
    scale: record
      x: single;                          { 8 }
      y: single;                          { 12 }
    end;
    multi_touch: record
      mode:     esp_lv_adapter_touch_mode_t;  { 16 }
      pointers: cuint8;                       { 20 }
    end;
    callbacks: esp_lv_adapter_touch_callbacks_t;  { 24 }
  end;  { 36 }

  { esp_err_t callback shape used by the auto-sleep hook collection }
  TAdapterSleepCb = function(user_ctx: pointer): c_bmgr.esp_err_t; cdecl;

  { struct esp_lv_adapter_auto_sleep_callbacks_t - 12 B }
  Pesp_lv_adapter_auto_sleep_callbacks_t = ^esp_lv_adapter_auto_sleep_callbacks_t;
  esp_lv_adapter_auto_sleep_callbacks_t = record
    on_enter_sleep: TAdapterSleepCb;  { 0 }
    on_exit_sleep:  TAdapterSleepCb;  { 4 }
    user_ctx:       pointer;          { 8 }
  end;

  { struct esp_lv_adapter_auto_sleep_config_t - 24 B }
  Pesp_lv_adapter_auto_sleep_config_t = ^esp_lv_adapter_auto_sleep_config_t;
  esp_lv_adapter_auto_sleep_config_t = record
    enable:          cbool;    { 0 }
    mode:            esp_lv_adapter_auto_sleep_mode_t;  { 4 }
    idle_timeout_ms: cuint;    { 8 }
    callbacks: esp_lv_adapter_auto_sleep_callbacks_t;  { 12 }
  end;  { 24 }

  { struct esp_lv_adapter_config_t - 52 B }
  Pesp_lv_adapter_config_t = ^esp_lv_adapter_config_t;
  esp_lv_adapter_config_t = record
    task_stack_size:   cuint;   { 0 }
    task_priority:     cuint;   { 4 }
    task_core_id:      cint;    { 8 (-1 = no affinity) }
    tick_period_ms:    cuint;   { 12 }
    task_min_delay_ms: cuint;   { 16 }
    task_max_delay_ms: cuint;   { 20 }
    stack_in_psram:    cbool;   { 24 }
    auto_sleep: esp_lv_adapter_auto_sleep_config_t;  { 28 }
  end;  { 52 }

{ --------------------------------------------------- macro equivalents }

{ ESP_LV_ADAPTER_DEFAULT_CONFIG() }
function ESP_LV_ADAPTER_DEFAULT_CONFIG: esp_lv_adapter_config_t;

{ ESP_LV_ADAPTER_DISPLAY_SPI_WITH_PSRAM_DEFAULT_CONFIG(panel, io, w, h, rot)
  - the CONFIG_SPIRAM=y variant (the one active in this board config) }
function ESP_LV_ADAPTER_DISPLAY_SPI_WITH_PSRAM_DEFAULT_CONFIG(
  panel: c_bmgr.esp_lcd_panel_handle_t;
  panel_io: c_bmgr.esp_lcd_panel_io_handle_t;
  hor_res, ver_res: cuint16;
  rotation: esp_lv_adapter_rotation_t
): esp_lv_adapter_display_config_t;

{ ESP_LV_ADAPTER_DISPLAY_SPI_WITHOUT_PSRAM_DEFAULT_CONFIG(...) - the
  CONFIG_SPIRAM-unset twin, kept for parity with the C #if/#else }
function ESP_LV_ADAPTER_DISPLAY_SPI_WITHOUT_PSRAM_DEFAULT_CONFIG(
  panel: c_bmgr.esp_lcd_panel_handle_t;
  panel_io: c_bmgr.esp_lcd_panel_io_handle_t;
  hor_res, ver_res: cuint16;
  rotation: esp_lv_adapter_rotation_t
): esp_lv_adapter_display_config_t;

{ ESP_LV_ADAPTER_TE_SYNC_DISABLED() - record with .gpio_num = -1 }
function ESP_LV_ADAPTER_TE_SYNC_DISABLED: esp_lv_adapter_te_sync_config_t;

{ ESP_LV_ADAPTER_TOUCH_DEFAULT_CONFIG(disp, touch_handle) }
function ESP_LV_ADAPTER_TOUCH_DEFAULT_CONFIG(
  disp: plv_display_t;
  touch_handle: c_bmgr.esp_lcd_touch_handle_t
): esp_lv_adapter_touch_config_t;

{ ----------------------------------------------------------- exported API }

{ adapter lifecycle - sdkconfig needs CONFIG_SPIRAM=y on the S3/S31 to
  honor the PSRAM profile, and CONFIG_ESP_LVGL_ADAPTER_* flags all default
  off in this board config }

function esp_lv_adapter_init(config: Pesp_lv_adapter_config_t): c_bmgr.esp_err_t; cdecl; external;
function esp_lv_adapter_start: c_bmgr.esp_err_t; cdecl; external;
function esp_lv_adapter_deinit: c_bmgr.esp_err_t; cdecl; external;
function esp_lv_adapter_is_initialized: cbool; cdecl; external;

{ thread safety }
function esp_lv_adapter_lock(timeout_ms: cint32): c_bmgr.esp_err_t; cdecl; external;
procedure esp_lv_adapter_unlock; cdecl; external;

{ user activity / wake }
function esp_lv_adapter_report_activity: c_bmgr.esp_err_t; cdecl; external;
procedure esp_lv_adapter_report_activity_from_isr; cdecl; external;
function esp_lv_adapter_request_wake: c_bmgr.esp_err_t; cdecl; external;
procedure esp_lv_adapter_request_wake_from_isr; cdecl; external;

{ immediate refresh / worker pause-resume }
function esp_lv_adapter_refresh_now(disp: plv_display_t): c_bmgr.esp_err_t; cdecl; external;
function esp_lv_adapter_pause(timeout_ms: cint32): c_bmgr.esp_err_t; cdecl; external;
function esp_lv_adapter_resume: c_bmgr.esp_err_t; cdecl; external;

{ display-backed sleep }
function esp_lv_adapter_sleep_prepare: c_bmgr.esp_err_t; cdecl; external;
function esp_lv_adapter_sleep_recover(disp: plv_display_t;
  panel: c_bmgr.esp_lcd_panel_handle_t;
  panel_io: c_bmgr.esp_lcd_panel_io_handle_t): c_bmgr.esp_err_t; cdecl; external;

{ dummy-draw hook (LVGL bypassed, application drives the panel directly) }
function esp_lv_adapter_set_dummy_draw(disp: plv_display_t;
  enable: cbool): c_bmgr.esp_err_t; cdecl; external;
function esp_lv_adapter_get_dummy_draw_enabled(disp: plv_display_t): cbool; cdecl; external;

{ display registration }
function esp_lv_adapter_register_display(
  config: Pesp_lv_adapter_display_config_t): plv_display_t; cdecl; external;
function esp_lv_adapter_unregister_display(disp: plv_display_t): c_bmgr.esp_err_t; cdecl; external;

{ touch registration }
function esp_lv_adapter_register_touch(
  config: Pesp_lv_adapter_touch_config_t): plv_indev_t; cdecl; external;
function esp_lv_adapter_unregister_touch(touch: plv_indev_t): c_bmgr.esp_err_t; cdecl; external;
function esp_lv_adapter_set_touch_callbacks(touch: plv_indev_t;
  cbs: Pesp_lv_adapter_touch_callbacks_t): c_bmgr.esp_err_t; cdecl; external;

implementation

function ESP_LV_ADAPTER_TE_SYNC_DISABLED: esp_lv_adapter_te_sync_config_t;
begin
  Result := Default(esp_lv_adapter_te_sync_config_t);
  Result.gpio_num := -1;              { .gpio_num = -1 => TE disabled }
end;

function ESP_LV_ADAPTER_DEFAULT_CONFIG: esp_lv_adapter_config_t;
begin
  Result := Default(esp_lv_adapter_config_t);
  Result.task_stack_size   := ESP_LV_ADAPTER_DEFAULT_STACK_SIZE;
  Result.task_priority     := ESP_LV_ADAPTER_DEFAULT_TASK_PRIORITY;
  Result.task_core_id      := ESP_LV_ADAPTER_DEFAULT_TASK_CORE_ID;
  Result.tick_period_ms    := ESP_LV_ADAPTER_DEFAULT_TICK_PERIOD_MS;
  Result.task_min_delay_ms := ESP_LV_ADAPTER_DEFAULT_TASK_MIN_DELAY_MS;
  Result.task_max_delay_ms := ESP_LV_ADAPTER_DEFAULT_TASK_MAX_DELAY_MS;
  Result.stack_in_psram    := false;
  { .auto_sleep = { .enable = false, .mode = DISABLED,
                     .idle_timeout_ms = DEFAULT_AUTO_SLEEP_TIMEOUT_MS } }
  Result.auto_sleep.enable          := false;
  Result.auto_sleep.mode            := ESP_LV_ADAPTER_AUTO_SLEEP_MODE_DISABLED;
  Result.auto_sleep.idle_timeout_ms := ESP_LV_ADAPTER_DEFAULT_AUTO_SLEEP_TIMEOUT_MS;
  { .callbacks stays all NULL (zeroed) }
end;

function ESP_LV_ADAPTER_DISPLAY_SPI_WITH_PSRAM_DEFAULT_CONFIG(
  panel: c_bmgr.esp_lcd_panel_handle_t;
  panel_io: c_bmgr.esp_lcd_panel_io_handle_t;
  hor_res, ver_res: cuint16;
  rotation: esp_lv_adapter_rotation_t
): esp_lv_adapter_display_config_t;
begin
  Result := Default(esp_lv_adapter_display_config_t);
  Result.panel    := panel;
  Result.panel_io := panel_io;
  { .profile = SPI_WITH_PSRAM_BASE(...) + require_double_buffer + mono NONE }
  Result.profile.panel_interface       := ESP_LV_ADAPTER_PANEL_IF_OTHER;
  Result.profile.rotation              := rotation;
  Result.profile.hor_res               := hor_res;
  Result.profile.ver_res               := ver_res;
  Result.profile.buffer_height         := ver_res;
  Result.profile.use_psram             := true;
  Result.profile.enable_ppa_accel      := false;
  Result.profile.require_double_buffer := true;
  Result.profile.mono_layout           := ESP_LV_ADAPTER_MONO_LAYOUT_NONE;
  { TEAR_AVOID_MODE_DEFAULT == TEAR_AVOID_MODE_NONE in the C header }
  Result.tear_avoid_mode := ESP_LV_ADAPTER_TEAR_AVOID_MODE_NONE;
  Result.te_sync         := ESP_LV_ADAPTER_TE_SYNC_DISABLED;
end;

function ESP_LV_ADAPTER_DISPLAY_SPI_WITHOUT_PSRAM_DEFAULT_CONFIG(
  panel: c_bmgr.esp_lcd_panel_handle_t;
  panel_io: c_bmgr.esp_lcd_panel_io_handle_t;
  hor_res, ver_res: cuint16;
  rotation: esp_lv_adapter_rotation_t
): esp_lv_adapter_display_config_t;
begin
  Result := ESP_LV_ADAPTER_DISPLAY_SPI_WITH_PSRAM_DEFAULT_CONFIG(panel, panel_io, hor_res, ver_res, rotation);
  Result.profile.use_psram := false;
end;

function ESP_LV_ADAPTER_TOUCH_DEFAULT_CONFIG(
  disp: plv_display_t;
  touch_handle: c_bmgr.esp_lcd_touch_handle_t
): esp_lv_adapter_touch_config_t;
begin
  Result := Default(esp_lv_adapter_touch_config_t);
  Result.disp   := disp;
  Result.handle := touch_handle;
  Result.scale.x := 1.0;
  Result.scale.y := 1.0;
  Result.multi_touch.mode     := ESP_LV_ADAPTER_TOUCH_MODE_SINGLE;
  Result.multi_touch.pointers := 1;   { C macro sets .pointers = 1; SINGLE
    mode hardcodes the effective count to 1 anyway, but this keeps
    field-for-field parity with the header }
  { .callbacks stays zeroed - the adapter then installs its default
    IDF-backed read/interrupt handling }
end;

end.
