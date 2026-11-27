{ mosaico_helpers - thin ESP-Mosaico helpers for things BMGR does not model.

  Hardware policy that yaml can express (chip, pins, geometry, SPI pclk /
  psram_dma_direct) lives in esp_mosaico board_devices.yaml + gen_bmgr_codes.
  L2 facades (boarddisplay / boardlvgl) stay yaml-as-is via Start.

  This unit keeps only vendor helpers outside BMGR devices - today the
  CO5300 brightness register. Do not put SPI policy here. App-opt-in.

  Contract:

    uses boarddisplay, mosaico_helpers;
    ret := TBoardDisplay.Start;   { yaml / gen_bmgr defaults }
    panel := TBoardDisplay.Panel;
    ignore := MosaicoSetBrightness(panel, 60);

  {$linklib espressif__esp_lcd_co5300} below pulls the CO5300 archive into
  the link group automatically when this unit is used (apps that do not use
  mosaico_helpers pass --lib espressif__esp_lcd_co5300 for BMGR's panel
  factory). }

unit mosaico_helpers;

{$mode objfpc}{$H+}
{$linklib espressif__esp_lcd_co5300}

interface

uses
  c_bmgr;

{ CO5300 vendor-register brightness (percent). BMGR has no brightness
  device on this board; every panel re-init resets the register to the
  driver default max. }
function MosaicoSetBrightness(panel: esp_lcd_panel_handle_t;
  brightness_percent: cuint8): esp_err_t;

implementation

function esp_lcd_panel_co5300_set_brightness(panel: esp_lcd_panel_handle_t;
  brightness_percent: cuint8): esp_err_t; cdecl; external;

function MosaicoSetBrightness(panel: esp_lcd_panel_handle_t;
  brightness_percent: cuint8): esp_err_t;
begin
  Result := esp_lcd_panel_co5300_set_brightness(panel, brightness_percent);
end;

end.
