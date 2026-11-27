{ boarddisplay - L2 panel chain: bring up BMGR's display_lcd device and
  hand out the esp_lcd panel handle. LVGL-free on purpose (landscape
  drives esp_lcd directly; boardlvgl sits on top for the adapter route).

  Board-agnostic: no panel-chip {$linklib}. The SDK project's yaml /
  gen_bmgr_codes + the app's --lib line resolve CO5300 / whatever IC.
  Put SPI policy (pclk, psram_dma_direct) in board yaml. Start = yaml-as-is.

  The facade does not invent or apply board SPI patches. Apps that really
  want a runtime patch of the BMGR-generated config do it themselves
  (mutate a copy), then call OverrideConfig before Start:

    var
      cfgp: Pdev_display_lcd_config_t;
      cfg:  dev_display_lcd_config_t;
    begin
      if esp_board_manager_get_device_config(
           ESP_BOARD_DEVICE_NAME_DISPLAY_LCD, @cfgp) <> ESP_OK then ...;
      cfg := cfgp^;
      { app mutates cfg — facade does not choose the fields }
      if TBoardDisplay.OverrideConfig(@cfg,
           cuint16(sizeof(cfg))) <> ESP_OK then ...;
      if TBoardDisplay.Start <> ESP_OK then ...;
      panel := TBoardDisplay.Panel;
    end;

  OverrideConfig must run before display_lcd is initialized — i.e. before
  Start, and before esp_board_manager_init if the app calls it — so the
  panel is initialized only once with the patched config (panel IO binds at
  device creation; init→deinit→re-init can hang under esp32sim). }

unit boarddisplay;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{ Transport archives (esp_lcd, spi, i2c) stay on the app --lib
  line — same rule as chip drivers. No {$linklib} here. }

interface

uses
  c_bmgr;

type
  TBoardDisplay = record
  public
    { Optional app-owned patch of the BMGR-generated display_lcd config.
      Pass a full device config the app prepared; this unit does not
      interpret SPI fields. Call before Start (and before
      esp_board_manager_init if used). }
    class function OverrideConfig(Config: Pointer;
      ConfigSize: cuint16): esp_err_t; static;

    { Init display_lcd from BMGR (yaml / gen_bmgr_codes, plus any prior
      OverrideConfig). }
    class function Start: esp_err_t; static;

    class function Panel: esp_lcd_panel_handle_t; static;
  end;

implementation

const
  TAG = 'boarddisplay';

var
  FPanel: esp_lcd_panel_handle_t = nil;
  FStarted: Boolean = False;
  FOverridden: Boolean = False;

class function TBoardDisplay.OverrideConfig(Config: Pointer;
  ConfigSize: cuint16): esp_err_t;
var
  ret: esp_err_t;
begin
  if FStarted then
    exit(ESP_ERR_INVALID_STATE);
  if (Config = nil) or (ConfigSize = 0) then
    exit(ESP_ERR_INVALID_ARG);

  ret := esp_board_device_override_config(
    ESP_BOARD_DEVICE_NAME_DISPLAY_LCD, Config, ConfigSize);
  if ret <> ESP_OK then
  begin
    writeln(TAG, ': E display_lcd override_config: ', ret);
    exit(ret);
  end;
  FOverridden := True;
  Result := ESP_OK;
end;

class function TBoardDisplay.Start: esp_err_t;
var
  ret: esp_err_t;
  lcdh: pointer;
  lcd_handles: Pdev_display_lcd_handles_t;
begin
  if FStarted then
    exit(ESP_ERR_INVALID_STATE);

  ret := esp_board_manager_init_device_by_name(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD);
  if ret <> ESP_OK then
  begin
    writeln(TAG, ': E display_lcd init: ', ret);
    halt
  end;

  lcdh := nil;
  ret := esp_board_manager_get_device_handle(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD, @lcdh);
  if (ret <> ESP_OK) or (lcdh = nil) then
  begin
    writeln(TAG, ': E display_lcd handle: ', ret);
    halt
  end;
  lcd_handles := Pdev_display_lcd_handles_t(lcdh);
  FPanel := lcd_handles^.panel_handle;
  if FPanel = nil then
  begin
    writeln(TAG, ': E display_lcd panel_handle is nil');
    halt
  end;

  FStarted := True;
  if FOverridden then
    writeln(TAG, ': I panel ready (app OverrideConfig)')
  else
    writeln(TAG, ': I panel ready (BMGR defaults)');
  Result := ESP_OK;
end;

class function TBoardDisplay.Panel: esp_lcd_panel_handle_t;
begin
  Result := FPanel;
end;

end.
