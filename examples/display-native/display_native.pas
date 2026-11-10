program display_native;

{ Pascal-native display chain demo - the "use -> one Start -> build UI"
  shape over the boardlvgl facade (L2) and the c_lvgl subset (L1).

  No C sources are linked (no --c): every UI element is created from
  Pascal, on the lvgl-s31 SDK project (ESP-Mosaico) with its software USB
  CDC console chain. The program body IS app_main (PASCALMAIN), as in the
  display_lvgl example; the facade's unit initialization has already
  lazily initialized the optional chain devices (touch, brightness) by
  the time the body runs, and TBoardLvgl.Start brings the panel up
  through the boarddisplay chain on the way.

  The red button doubles as the packed-lv_color_t ABI probe: lv_color_t
  is a 3x uint8 C struct passed by value (psABI-bitified into one
  register - see c_lvgl.pas). If the packing were wrong the button would
  not be pure red (255, 0, 0).

  The event callback runs in the adapter worker task and locks around its
  own LVGL calls - the lvgl_test_ui.c ui_acquire/ui_release pattern.

  Build from the repo root of esp-units.pas, against the lvgl-s31 SDK
  project (same link closure as display_lvgl, but no --c):

    cd examples/display-native
    ESP_FPC_ROOT=/mnt/storage/fpc-cross \
    ESP32_SDK_PROJECT=/mnt/storage/fpc-esp/lvgl-s31 \
    ../../scripts/build.sh display_native.pas --soc esp32s31 \
        --lib espressif__esp_board_manager --lib gen_bmgr_codes \
        --lib lvgl__lvgl --lib espressif__esp_lvgl_adapter \
        ... (the full --lib set is in this directory's README.md) ...

  Configurable variant (values are the facade defaults shown):

    var
      cfg: TBoardLvglConfig;
    begin
      cfg := TBoardLvgl.DefaultConfig;
      cfg.TaskPriority  := 5;
      cfg.Rotation      := ESP_LV_ADAPTER_ROTATE_180;
      cfg.TouchScaleY   := 1.0;
      ret := TBoardLvgl.StartEx(cfg);
    end.

  idfheap comes first in uses - the IDF-backed heap manager must be
  installed before anything else allocates (the units' init or the string
  literals this program builds). }

{$mode objfpc}{$H+}

uses
  idfheap,        { MUST be first: installs the IDF heap manager }
  c_bmgr,         { L1: esp_err_t }
  c_lvgl,         { L1: LVGL 9.6 working subset }
  boardlvgl;   { L2: facade - use = display chain initialized }

{ FreeRTOS; pdMS_TO_TICKS(1000) = 100 ticks at this sdkconfig's
  CONFIG_FREERTOS_HZ=100 }
procedure vTaskDelay(ticks: cuint32); cdecl; external;

const
  TAG = 'display_native';
  HEARTBEAT_TICKS = 100;  { 1 s }

{ button event - runs in the adapter worker task; lock around the LVGL
  calls exactly like lvgl_test_ui.c's event callbacks do }
procedure OnBtnClick(e: plv_event_t); cdecl;
begin
  TBoardLvgl.UILock;
  if lv_event_get_code(e) = LV_EVENT_CLICKED then
    writeln(TAG, ': I button clicked');
  TBoardLvgl.UIUnlock;
end;

var
  screen, hint, btn, btn_label: plv_obj_t;
  ret: esp_err_t;
begin
  ret := TBoardLvgl.Start;
  if ret <> ESP_OK then
  begin
    writeln(TAG, ': E TBoardLvgl.Start: ', ret);
    { spin: do not halt - the RTL shutdown would tear the console down }
    while True do
      vTaskDelay(HEARTBEAT_TICKS);
  end;

  { build the UI from the Pascal main task - under the adapter lock }
  TBoardLvgl.UILock;
  screen := lv_screen_active();

  hint := lv_label_create(screen);
  lv_label_set_text(hint, 'display_native: Pascal-built UI');
  lv_obj_align(hint, LV_ALIGN_TOP_MID, 0, 40);
  lv_obj_set_style_text_color(hint, ColorBlack, LV_STYLE_MAIN);
  lv_obj_set_style_text_font(hint, @lv_font_montserrat_28, LV_STYLE_MAIN);

  btn := lv_button_create(screen);
  lv_obj_set_size(btn, 160, 60);
  lv_obj_align(btn, LV_ALIGN_CENTER, 0, 0);
  lv_obj_set_style_bg_color(btn, ColorMake(255, 0, 0), LV_STYLE_MAIN);

  btn_label := lv_label_create(btn);
  lv_label_set_text(btn_label, 'Click me');
  lv_obj_center(btn_label);
  lv_obj_set_style_text_font(btn_label, @lv_font_montserrat_20, LV_STYLE_MAIN);
  lv_obj_add_event_cb(btn, @OnBtnClick, LV_EVENT_CLICKED, nil);
  TBoardLvgl.UIUnlock;

  writeln(TAG, ': I UI up; heartbeat follows (touch the button too)');
  while True do
  begin
    vTaskDelay(HEARTBEAT_TICKS);
    writeln(TAG, ': I alive');
  end;
end.
