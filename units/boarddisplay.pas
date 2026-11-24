{ boarddisplay - L2 panel chain: bring up BMGR's display_lcd device and
  hand out the esp_lcd panel handle. LVGL-free on purpose (landscape
  drives esp_lcd directly; boardlvgl sits on top for the adapter route).

  Board-agnostic: no panel-chip {$linklib}. The SDK project's yaml /
  gen_bmgr_codes + the app's --lib line resolve CO5300 / whatever IC.
  Panel policy (psram_dma_direct, pclk) is a value-semantics config;
  DefaultConfig = "use BMGR-generated defaults". Board packs (see
  board_mosaico) or apps supply overrides via StartEx.

  Contract:

    uses boarddisplay;
    if TBoardDisplay.Start <> ESP_OK then ...          { BMGR defaults }
    if TBoardDisplay.StartEx(cfg) <> ESP_OK then ...  { with overrides }
    panel := TBoardDisplay.Panel;

  StartEx reads display_lcd config, optionally patches, override_config
  then init once (panel IO binds at creation - override before first
  init; avoids the init→deinit→re-init hang under esp32sim). }

unit boarddisplay;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{ Transport archives (esp_lcd, spi, i2c, ppa) stay on the app --lib
  line — same rule as chip drivers. No {$linklib} here. }

interface

uses
  c_bmgr;

type
  { Value-semantics panel policy. Defaults leave the BMGR-generated
    display_lcd config untouched. }
  TBoardDisplayConfig = record
    { OR SPI_FLAG_psram_dma_direct into io_spi_config.flags when True }
    OverridePsramDmaDirect: Boolean;
    { When non-zero, set io_spi_config.pclk_hz to this value (Hz).
      0 = leave the generated clock alone. }
    PclkHz: cuint32;
  end;

  TBoardDisplay = record
  public
    class function DefaultConfig: TBoardDisplayConfig; static;
    class function Start: esp_err_t; static; overload;
    class function StartEx(const AConfig: TBoardDisplayConfig): esp_err_t; static; overload;
    class function Panel: esp_lcd_panel_handle_t; static;
  end;

implementation

const
  TAG = 'boarddisplay';

var
  FPanel: esp_lcd_panel_handle_t = nil;
  FStarted: Boolean = False;

class function TBoardDisplay.DefaultConfig: TBoardDisplayConfig;
begin
  Result := Default(TBoardDisplayConfig);
  Result.OverridePsramDmaDirect := False;
  Result.PclkHz := 0;
end;

class function TBoardDisplay.Start: esp_err_t;
begin
  Result := StartEx(DefaultConfig);
end;

class function TBoardDisplay.StartEx(const AConfig: TBoardDisplayConfig): esp_err_t;
var
  ret: esp_err_t;
  cfgp: Pdev_display_lcd_config_t;
  devcfg: dev_display_lcd_config_t;
  lcdh: pointer;
  lcd_handles: Pdev_display_lcd_handles_t;
  need_override: Boolean;
begin
  if FStarted then
    exit(ESP_ERR_INVALID_STATE);

  need_override := AConfig.OverridePsramDmaDirect or (AConfig.PclkHz <> 0);
  if need_override then
  begin
    ret := esp_board_manager_get_device_config(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD, @cfgp);
    if (ret <> ESP_OK) or (cfgp = nil) then
    begin
      writeln(TAG, ': E display_lcd config: ', ret);
      halt
    end;
    devcfg := cfgp^;
    if AConfig.OverridePsramDmaDirect then
      devcfg.sub_cfg.spi.io_spi_config.flags :=
        devcfg.sub_cfg.spi.io_spi_config.flags or SPI_FLAG_psram_dma_direct;
    if AConfig.PclkHz <> 0 then
      devcfg.sub_cfg.spi.io_spi_config.pclk_hz := AConfig.PclkHz;
    ret := esp_board_device_override_config(ESP_BOARD_DEVICE_NAME_DISPLAY_LCD,
      @devcfg, cuint16(sizeof(dev_display_lcd_config_t)));
    if ret <> ESP_OK then
    begin
      writeln(TAG, ': E display_lcd override_config: ', ret);
      halt
    end;
  end;

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
  if need_override then
    writeln(TAG, ': I panel ready (overrides applied)')
  else
    writeln(TAG, ': I panel ready (BMGR defaults)');
  Result := ESP_OK;
end;

class function TBoardDisplay.Panel: esp_lcd_panel_handle_t;
begin
  Result := FPanel;
end;

end.
