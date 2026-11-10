program display_lvgl;

{ Pascal port of lvgl-s31/main/main.c (esp_board_manager + esp_lv_adapter
  LVGL display example) - same call sequence, same active branch for the
  ESP-Mosaico sdkconfig:

  CONFIG truth it is written against (verified in that project's
  build/config/sdkconfig.h):
    - CONFIG_SPIRAM = 1                     -> SPI+PSRAM display branch
    - only SUB_SPI survives the dev_display_lcd CONFIG gating (the DSI/
      RGB branches in the C file are compiled out; the Pascal keeps the
      runtime sub_type dispatch shape with the "support not enabled"
      fallbacks main.c has for them)
    - CONFIG_ESP_BOARD_DEV_LCD_TOUCH_SUPPORT = 1 -> touch block included
    - CONFIG_ESP_BOARD_DEV_LCD_BRIGHTNESS (device registered by name)

  Logging: main.c uses ESP_LOGx through the compiled-in console; this
  port uses writeln (same stdout, which the software USB CDC console
  chain of the board routes to /dev/ttyACM*). Every log line is prefixed
  with the C file's TAG "BMGR_DISPLAY_LVGL".

  The program body IS app_main here: FPC's RTL owns the app_main symbol
  (PASCALMAIN) and the software USB console wrap chain of the SDK project
  runs before it (see scripts/build.sh exuberant + README).

  Build from the repo root of esp-units.pas, against the lvgl-s31 SDK
  project (example dir keeps its .ppu next to the .pas):

    cd examples/display_lvgl
    ESP_FPC_ROOT=/mnt/storage/fpc-cross \\
    ESP32_SDK_PROJECT=/mnt/storage/fpc-esp/lvgl-s31 \\
    ../../scripts/build.sh display_lvgl.pas --soc esp32s31 \\
        --c lvgl_test_ui.c \\
        --lib espressif__esp_board_manager --lib gen_bmgr_codes \\
        --lib lvgl__lvgl --lib espressif__esp_lvgl_adapter \\
        --lib espressif__esp_lcd_co5300 \\
        --lib waveshare__esp_lcd_touch_cst9217

  idfheap comes first in uses - the IDF-backed heap manager must be
  installed before anything else allocates (the units' init or the
  string literals this program builds). }

{$mode objfpc}{$H+}

uses
  idfheap,           { MUST be first: installs the IDF heap manager }
  c_bmgr,            { esp_board_manager binding (units/, L1) }
  c_lvgl_adapter;    { esp_lvgl_adapter binding (units/, L1) }

{ C strcmp - newlib, always linked in the IDF build; frees the port of
  any dependence on a Pascal CRT strings runtime }
function strcmp(a, b: PChar): cint; cdecl; external;

{ from main/lvgl_test_ui.c - compiled and linked by build.sh --c }
procedure lvgl_test_start; cdecl; external;

{ tag mirror of the C file's TAG constant, used in every log line }
const
  TAGmsg = 'BMGR_DISPLAY_LVGL';

{ --------------------------------------------------------------- helpers }

{ lcd_lvgl_adapter_register_display(lcd_cfg, lcd_handles), main.c.
  Runtime dispatch on sub_type; the DSI / RGB branches exist in the C
  file behind CONFIG gating that this board's sdkconfig validates off -
  written here as the same runtime fallbacks (behave like the C
  #else-branch: log and give up so cleanup paths run) }
function LCDLVGLAdapterRegisterDisplay(
  lcd_cfg: Pdev_display_lcd_config_t;
  lcd_handles: Pdev_display_lcd_handles_t
): plv_display_t;
var
  rotation: esp_lv_adapter_rotation_t;
  disp_cfg: esp_lv_adapter_display_config_t;
begin
  rotation := ESP_LV_ADAPTER_ROTATE_0;

  if strcmp(lcd_cfg^.sub_type, ESP_BOARD_DEVICE_LCD_SUB_TYPE_DSI) = 0 then
  begin
    { #else-branch of CONFIG_ESP_BOARD_DEV_DISPLAY_LCD_SUB_DSI_SUPPORT }
    writeln(TAGmsg, ': E (DSI support not enabled)');
    exit(nil);
  end
  else if (strcmp(lcd_cfg^.sub_type, ESP_BOARD_DEVICE_LCD_SUB_TYPE_RGB) = 0) or
          (strcmp(lcd_cfg^.sub_type, ESP_BOARD_DEVICE_LCD_SUB_TYPE_RGB_3WIRE_SPI) = 0) then
  begin
    { #else-branch of the RGB / RGB_3WIRE_SPI gating }
    writeln(TAGmsg, ': E (RGB support not enabled)');
    exit(nil);
  end
  else if (strcmp(lcd_cfg^.sub_type, ESP_BOARD_DEVICE_LCD_SUB_TYPE_SPI) = 0) or
          (strcmp(lcd_cfg^.sub_type, ESP_BOARD_DEVICE_LCD_SUB_TYPE_I80) = 0) or
          (strcmp(lcd_cfg^.sub_type, ESP_BOARD_DEVICE_LCD_SUB_TYPE_PARLIO) = 0) then
  begin
    { #ifdef CONFIG_SPIRAM branch (CONFIG_SPIRAM = 1 in this sdkconfig);
      rotation stays 0 exactly like the C file }
    disp_cfg := ESP_LV_ADAPTER_DISPLAY_SPI_WITH_PSRAM_DEFAULT_CONFIG(
      lcd_handles^.panel_handle,
      lcd_handles^.io_handle,
      lcd_cfg^.lcd_width,
      lcd_cfg^.lcd_height,
      rotation);
  end
  else
  begin
    writeln(TAGmsg, ': E Unknown LCD sub_type: ', lcd_cfg^.sub_type);
    exit(nil);
  end;

  { mirror of the ESP_LOGI before esp_lv_adapter_register_display() }
  writeln(TAGmsg, ': I Register LCD to LVGL adapter: sub_type=',
          lcd_cfg^.sub_type, ', size=', lcd_cfg^.lcd_width, 'x',
          lcd_cfg^.lcd_height, ', rotation=', Ord(rotation), ', tear_mode=',
          Ord(disp_cfg.tear_avoid_mode));

  Result := esp_lv_adapter_register_display(@disp_cfg);
end;

{ lcd_lvgl_adapter_init(), main.c: default adapter config + the same
  overrides, then esp_lv_adapter_init }
function LCDLVGLAdapterInit: esp_err_t;
var
  adapter_config: esp_lv_adapter_config_t;
  ret: esp_err_t;
begin
  writeln(TAGmsg, ': I Initializing LVGL adapter...');
  adapter_config := ESP_LV_ADAPTER_DEFAULT_CONFIG;
  adapter_config.task_priority   := 4;
  adapter_config.task_stack_size := 6 * 1024;
  adapter_config.task_core_id    := 1;
  adapter_config.tick_period_ms  := 5;
  adapter_config.task_max_delay_ms := 500;

  ret := esp_lv_adapter_init(@adapter_config);
  if ret <> ESP_OK then
  begin
    writeln(TAGmsg, ': E Failed to initialize LVGL adapter: ', ret);
    Result := ESP_FAIL;
    exit;
  end;
  Result := ESP_OK;
end;

{ --------------------------------------------------------------- app_main }

label
  cleanup_lvgl, cleanup_adapter, cleanup_devices;

var
  ret: esp_err_t;
  lcd_cfg: Pdev_display_lcd_config_t;
  lcd_handle: pointer;
  lcd_handles: Pdev_display_lcd_handles_t;
  disp: plv_display_t;
  touch_indev: plv_indev_t;
  touch_handle: pointer;
  touch_handles: Pdev_lcd_touch_handles_t;
  touch_cfg: esp_lv_adapter_touch_config_t;
begin
  { CONFIG_ESP_BOARD_DEV_LCD_TOUCH_SUPPORT = 1 in this sdkconfig - the
    C touch block is active; no #if around the Pascal twin }
  writeln(TAGmsg, ': I Starting LVGL Example');

  ret := esp_board_manager_init_device_by_name(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD);
  if ret <> ESP_OK then
  begin
    writeln(TAGmsg, ': E Failed to initialize display_lcd: ', ret);
    exit;
  end;

  ret := esp_board_manager_init_device_by_name(ESP_BOARD_DEVICE_NAME_LCD_TOUCH);
  if ret <> ESP_OK then
    writeln(TAGmsg, ': W Failed to initialize lcd_touch: ', ret, ', continue');

  ret := esp_board_manager_init_device_by_name(ESP_BOARD_DEVICE_NAME_LCD_BRIGHTNESS);
  if ret <> ESP_OK then
    writeln(TAGmsg, ': W Failed to initialize lcd_brightness: ', ret, ', continue');

  { Initialize LVGL adapter }
  if LCDLVGLAdapterInit <> ESP_OK then
    goto cleanup_devices;

  { Initialize LCD Display }
  lcd_handle := nil;
  ret := esp_board_manager_get_device_handle(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD, @lcd_handle);
  if (ret <> ESP_OK) or (lcd_handle = nil) then
  begin
    writeln(TAGmsg, ': E Failed to get LCD device handle');
    goto cleanup_adapter;
  end;

  { Get LCD Configuration }
  lcd_cfg := nil;
  ret := esp_board_manager_get_device_config('display_lcd', @lcd_cfg);
  if ret <> ESP_OK then
  begin
    writeln(TAGmsg, ': E Failed to get LCD config');
    goto cleanup_adapter;
  end;

  { Add display to LVGL adapter }
  lcd_handles := Pdev_display_lcd_handles_t(lcd_handle);
  disp := LCDLVGLAdapterRegisterDisplay(lcd_cfg, lcd_handles);
  if disp = nil then
  begin
    writeln(TAGmsg, ': E Failed to register display to LVGL adapter');
    goto cleanup_adapter;
  end;

  { Initialize Touch (Optional) }
  touch_indev := nil;
  { #ifdef CONFIG_ESP_BOARD_DEV_LCD_TOUCH_SUPPORT branch (active) }
  touch_handle := nil;
  if (esp_board_manager_get_device_handle(ESP_BOARD_DEVICE_NAME_LCD_TOUCH, @touch_handle) = ESP_OK)
     and (touch_handle <> nil) then
  begin
    touch_handles := Pdev_lcd_touch_handles_t(touch_handle);
    touch_cfg := ESP_LV_ADAPTER_TOUCH_DEFAULT_CONFIG(disp, touch_handles^.touch_handle);
    touch_indev := esp_lv_adapter_register_touch(@touch_cfg);
    if touch_indev = nil then
      writeln(TAGmsg, ': W Failed to add touch input')
    else
      writeln(TAGmsg, ': I Touch input added');
  end;

  ret := esp_lv_adapter_start;
  if ret <> ESP_OK then
  begin
    writeln(TAGmsg, ': E Failed to start LVGL adapter: ', ret);
    goto cleanup_lvgl;
  end;

  { Run Test UI }
  writeln(TAGmsg, ': I Running LVGL Test UI');
  lvgl_test_start;

cleanup_lvgl:
  { Deinitialize LVGL adapter }
  if touch_indev <> nil then
    esp_lv_adapter_unregister_touch(touch_indev);
  if disp <> nil then
    esp_lv_adapter_unregister_display(disp);

cleanup_adapter:
  esp_lv_adapter_deinit;

  writeln(TAGmsg, ': I Example Finished. Exiting app_main...');

cleanup_devices:
  esp_board_manager_deinit_device_by_name(ESP_BOARD_DEVICE_NAME_LCD_BRIGHTNESS);
  esp_board_manager_deinit_device_by_name(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD);
  esp_board_manager_deinit_device_by_name(ESP_BOARD_DEVICE_NAME_LCD_TOUCH);
end.
