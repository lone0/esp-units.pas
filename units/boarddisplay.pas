{ boarddisplay - L2 panel chain: the BMGR display_lcd device brought up
  with this board's two overrides, handing out the esp_lcd panel handle.
  LVGL-free on purpose: this is the half of the display chain that does
  not know LVGL exists (landscape drives esp_lcd directly; the LVGL
  facade boardlvgl sits on top of this unit for the adapter route).

  Layer grammar (units/README.md): unprefixed functional unit name = L2
  Pascal-native service built on the L1 bindings. The API is advanced-
  record static methods; esp_err_t stays visible; no exceptions; the
  rebuilt panel stays BMGR-owned - the unit never duplicates objects or
  config sources.

  Contract:

    uses boarddisplay;                  (panel chain, one Start)
    ...
    if TBoardDisplay.Start <> ESP_OK then ...
    panel := TBoardDisplay.Panel;       (feed esp_lcd_panel_draw_bitmap)

  - Start runs landscape-verified sequence: copy the generated config,
    patch psram_dma_direct + 80 MHz, then the official BMGR re-init
    path (deinit -> override_config -> init - an esp_lcd panel object
    binds its io at creation, so patching means rebuilding), re-fetch
    the NEW panel object, vendor-register brightness. Every failure
    writeln's and halts - a panel that did not come up leaves nothing
    sensible to return to (landscape esp_init semantics).
  - the override is unconditional and is exactly what landscape runs
    on hardware; callers that want the generated defaults (40 MHz,
    io-bounced PSRAM) should not use this unit.
  - brightness: BMGR does not manage it on this board (no brightness
    device in the pack; CO5300 is an AMOLED - brightness is a vendor
    register, and every re-init resets it to the driver default max).
    The register call is carried commented, exactly as landscape runs
    it (driver default max). }

unit boarddisplay;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  c_bmgr;  { esp_err_t, device-name constants, dev_display_lcd_* types,
             SPI flags, BMGR API, esp_lcd opaque handles }

type
  TBoardDisplay = record
  public
    { bring the panel up (see the unit header); stores the handle }
    class function Start: esp_err_t; static;

    { the BMGR-owned panel handle; nil before Start }
    class function Panel: esp_lcd_panel_handle_t; static;
  end;

implementation

const
  TAG = 'boarddisplay';

  BRIGHTNESS = 60;       { percent, AMOLED unattended (landscape value) }

{ espressif__esp_lcd_co5300 - AMOLED brightness (a vendor register call;
  the board pack models no brightness device, and every panel re-init
  resets the register to the driver default max) }
function esp_lcd_panel_co5300_set_brightness(panel: esp_lcd_panel_handle_t;
  brightness_percent: cuint8): esp_err_t; cdecl; external;

var
  FPanel: esp_lcd_panel_handle_t = nil;
  FStarted: Boolean = False;

{ --------------------------------------------------------------- TBoardDisplay }

class function TBoardDisplay.Start: esp_err_t;
var
  ret: esp_err_t;
  cfgp: Pdev_display_lcd_config_t;
  devcfg: dev_display_lcd_config_t;
  lcdh: pointer;
  lcd_handles: Pdev_display_lcd_handles_t;
begin
  if FStarted then
    exit(ESP_ERR_INVALID_STATE);

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
  FPanel := lcd_handles^.panel_handle;
  if FPanel = nil then
  begin
    writeln(TAG, ': E display_lcd panel_handle is nil');
    halt
  end;

  { see the unit header: brightness is a vendor register on this board;
    carried commented, exactly as landscape runs it }
  {if esp_lcd_panel_co5300_set_brightness(FPanel, BRIGHTNESS) <> ESP_OK then
    writeln(TAG, ': W set_brightness failed (running at driver default)');}

  FStarted := True;
  writeln(TAG, ': I panel ready (psram_dma_direct, 80 MHz)');
  Result := ESP_OK;
end;

class function TBoardDisplay.Panel: esp_lcd_panel_handle_t;
begin
  Result := FPanel;
end;

end.
