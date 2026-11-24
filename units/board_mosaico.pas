{ board_mosaico - thin ESP-Mosaico board pack over the generic L2 facades.

  boarddisplay / boardlvgl stay board-agnostic (device names + lifecycle).
  This unit owns Mosaico panel policy and the CO5300 brightness helper.
  Touch IC (CST9220) still belongs on the app's --lib line / SDK yaml.

  Deliberately does NOT use boardlvgl: panel-only apps (landscape, the
  facade demos) must not pull the LVGL adapter archives. LVGL apps set
  cfg.Panel := MosaicoDisplayConfig on a TBoardLvglConfig themselves.

  Contract:

    uses board_mosaico;
    ret := TBoardDisplay.StartEx(MosaicoDisplayConfig);

    { LVGL apps: }
    cfg := TBoardLvgl.DefaultConfig;
    cfg.Panel := MosaicoDisplayConfig;
    ret := TBoardLvgl.StartEx(cfg);

  App link closure (same family as mosaico_sim / display_lvgl):
    --lib espressif__esp_lcd_co5300
    --lib espressif__esp_lcd_touch_cst9220
    (+ BMGR / gen_bmgr_codes / transport libs as usual) }

unit board_mosaico;

{$mode objfpc}{$H+}
{$linklib espressif__esp_lcd_co5300}

interface

uses
  c_bmgr,
  boarddisplay;

{ Mosaico panel policy: PSRAM DMA direct + 80 MHz pclk (hardware-
  verified landscape / display_native values). }
function MosaicoDisplayConfig: TBoardDisplayConfig;

{ CO5300 vendor-register brightness (percent). BMGR has no brightness
  device on this board; every panel re-init resets the register to the
  driver default max. }
function MosaicoSetBrightness(panel: esp_lcd_panel_handle_t;
  brightness_percent: cuint8): esp_err_t;

implementation

function esp_lcd_panel_co5300_set_brightness(panel: esp_lcd_panel_handle_t;
  brightness_percent: cuint8): esp_err_t; cdecl; external;

function MosaicoDisplayConfig: TBoardDisplayConfig;
begin
  Result := TBoardDisplay.DefaultConfig;
  Result.OverridePsramDmaDirect := True;
  Result.PclkHz := 80000000;
end;

function MosaicoSetBrightness(panel: esp_lcd_panel_handle_t;
  brightness_percent: cuint8): esp_err_t;
begin
  Result := esp_lcd_panel_co5300_set_brightness(panel, brightness_percent);
end;

end.
